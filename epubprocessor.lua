--[[--
EPUB Processor - Extracts, modifies, and repackages EPUB files
]]--

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5
local Archiver = require("ffi/archiver")

local EpubProcessor = {}

function EpubProcessor:new(cache_dir)
    local o = {
        cache_dir = cache_dir,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function EpubProcessor:processEpub(epub_path, replacements)
    logger.info("EpubProcessor: Processing", epub_path)
    
    -- Generate cache file path based on original file only (not rules)
    local cache_file = self:getCacheFilePath(epub_path, replacements)
    
    -- Always regenerate - don't use old cache with potentially different rules
    logger.info("EpubProcessor: Generating cache file:", cache_file)
    
    -- Extract EPUB
    local temp_dir = self:extractEpub(epub_path)
    if not temp_dir then
        logger.err("EpubProcessor: Failed to extract EPUB")
        return nil
    end
    
    -- Apply replacements to HTML files
    local html_count = self:applyReplacements(temp_dir, replacements)
    logger.info("EpubProcessor: Modified", html_count, "HTML files")
    
    -- Repackage EPUB (will overwrite existing cache if present)
    local success = self:repackageEpub(temp_dir, cache_file)
    
    -- Clean up temp directory
    self:cleanupTempDir(temp_dir)
    
    if success then
        return cache_file
    else
        return nil
    end
end

function EpubProcessor:getCacheFilePath(epub_path, replacements)
    -- Create a hash based ONLY on the original file path
    -- This way each book has one cache file that gets updated when rules change
    local hash = md5(epub_path)
    local filename = hash:sub(1, 16) .. ".epub"
    return self.cache_dir .. "/" .. filename
end

function EpubProcessor:serializeReplacements(replacements)
    local parts = {}
    for _, rule in ipairs(replacements) do
        if rule.enabled then
            table.insert(parts, rule.pattern .. "|" .. rule.replacement)
        end
    end
    return table.concat(parts, "\n")
end

function EpubProcessor:isCacheValid(cache_file, original_file)
    local cache_attr = lfs.attributes(cache_file)
    local orig_attr = lfs.attributes(original_file)
    
    if not cache_attr or not orig_attr then
        return false
    end
    
    -- Check if cache is newer than original
    return cache_attr.modification >= orig_attr.modification
end

function EpubProcessor:extractEpub(epub_path)
    -- EPUBs are ZIP files
    -- We need to extract them to a temp directory
    
    -- Create temp directory (Android-safe approach)
    local temp_base = os.tmpname()
    if not temp_base then
        logger.err("EpubProcessor: os.tmpname() returned nil")
        return nil
    end
    
    os.remove(temp_base) -- Remove the file that os.tmpname() created
    local temp_dir = temp_base .. "_epub_proc"
    
    local mkdir_result = lfs.mkdir(temp_dir)
    if not mkdir_result then
        logger.err("EpubProcessor: Failed to create temp directory:", temp_dir)
        return nil
    end
    
    logger.info("EpubProcessor: Created temp directory:", temp_dir)
    
    -- Use system unzip command (most e-readers have this)
    local cmd = string.format("unzip -q %q -d %q", epub_path, temp_dir)
    logger.dbg("EpubProcessor: Running unzip command:", cmd)
    local result = os.execute(cmd)
    
    if result == 0 or result == true then
        logger.dbg("EpubProcessor: Unzip successful")
        return temp_dir
    else
        logger.err("EpubProcessor: unzip failed with result:", result)
        -- Clean up failed temp directory
        os.execute(string.format("rm -rf %q", temp_dir))
        return nil
    end
end

function EpubProcessor:applyReplacements(temp_dir, rules)
    local count = 0
    
    -- Separate rules by type
    local replacement_rules = {}
    local footnote_rules = {}
    
    for _, rule in ipairs(rules) do
        if rule.enabled then
            if rule.type == "footnote" then
                table.insert(footnote_rules, rule)
            else
                -- Default to replacement type for backward compatibility
                table.insert(replacement_rules, rule)
            end
        end
    end
    
    logger.info("EpubProcessor: Processing", #replacement_rules, "replacement rules and", #footnote_rules, "footnote rules")
    
    -- Find all HTML/XHTML files
    local function processDirectory(dir)
        for entry in lfs.dir(dir) do
            if entry ~= "." and entry ~= ".." then
                local path = dir .. "/" .. entry
                local attr = lfs.attributes(path)
                
                if attr.mode == "directory" then
                    processDirectory(path)
                elseif attr.mode == "file" then
                    if path:match("%.x?html$") or path:match("%.xhtml$") then
                        local modified = false
                        
                        -- First apply replacement rules
                        if #replacement_rules > 0 then
                            if self:processReplacementRules(path, replacement_rules) then
                                modified = true
                            end
                        end
                        
                        -- Then apply footnote rules
                        if #footnote_rules > 0 then
                            if self:processFootnoteRules(path, footnote_rules) then
                                modified = true
                            end
                        end
                        
                        if modified then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    
    processDirectory(temp_dir)
    return count
end

function EpubProcessor:processReplacementRules(filepath, replacement_rules)
    local f = io.open(filepath, "r")
    if not f then
        logger.warn("EpubProcessor: Cannot open", filepath)
        return false
    end
    
    local content = f:read("*all")
    f:close()
    
    local modified = false
    
    -- Apply each enabled replacement
    for _, rule in ipairs(replacement_rules) do
        -- Wrap in pcall to catch pattern errors
        local success, new_content = pcall(function()
            return content:gsub(rule.pattern, rule.replacement)
        end)
        
        if not success then
            logger.err("EpubProcessor: Pattern/replacement error for rule:", rule.pattern, "Error:", new_content)
            -- Continue with other rules instead of failing completely
        elseif new_content ~= content then
            content = new_content
            modified = true
            logger.dbg("EpubProcessor: Applied replacement rule to", filepath)
        end
    end
    
    if modified then
        -- Write back modified content
        f = io.open(filepath, "w")
        if f then
            f:write(content)
            f:close()
            return true
        else
            logger.err("EpubProcessor: Failed to write modified file:", filepath)
        end
    end
    
    return false
end

function EpubProcessor:processFootnoteRules(filepath, footnote_rules)
    -- Load FootnoteProcessor
    local FootnoteProcessor = require("footnoteprocessor")
    local processor = FootnoteProcessor:new()
    
    return processor:processHtmlFile(filepath, footnote_rules)
end

function EpubProcessor:repackageEpub(temp_dir, output_path)
    -- Ensure cache directory exists
    local cache_dir_path = output_path:match("(.*/)")
    if cache_dir_path then
        if lfs.attributes(cache_dir_path, "mode") ~= "directory" then
            local ok = lfs.mkdir(cache_dir_path)
            if not ok then
                logger.err("EpubProcessor: Failed to create cache directory:", cache_dir_path)
                return false
            end
        end
    end
    
    -- Remove existing file if present
    if lfs.attributes(output_path) then
        os.remove(output_path)
    end
    
    -- Use KOReader's archiver to create EPUB (ZIP format)
    local writer = Archiver.Writer:new()
    if not writer:open(output_path, "zip") then
        logger.err("EpubProcessor: Failed to open archive for writing:", writer.err)
        return false
    end
    
    -- EPUB spec requires mimetype file to be first and uncompressed
    writer:setZipCompression("store")
    local mimetype_path = temp_dir .. "/mimetype"
    local mimetype_content = nil
    
    -- Try to read existing mimetype file
    local f = io.open(mimetype_path, "r")
    if f then
        mimetype_content = f:read("*all")
        f:close()
        logger.dbg("EpubProcessor: Read mimetype from extracted EPUB")
    else
        -- Create default mimetype if not present
        logger.warn("EpubProcessor: mimetype file not found, creating default")
        mimetype_content = "application/epub+zip"
    end
    
    if not writer:addFileFromMemory("mimetype", mimetype_content) then
        logger.err("EpubProcessor: Failed to add mimetype:", writer.err)
        writer:close()
        return false
    end
    
    -- Now add everything else with compression
    writer:setZipCompression("deflate")
    
    -- Recursively add all other files and directories
    for entry in lfs.dir(temp_dir) do
        if entry ~= "." and entry ~= ".." and entry ~= "mimetype" then
            local path = temp_dir .. "/" .. entry
            writer:addPath(entry, path, true)
            -- Check for actual errors (err will be nil on success or EOF)
            if writer.err then
                logger.err("EpubProcessor: Failed to add", entry, ":", writer.err)
                writer:close()
                return false
            end
        end
    end
    
    writer:close()
    logger.info("EpubProcessor: Successfully created EPUB:", output_path)
    return true
end

function EpubProcessor:cleanupTempDir(temp_dir)
    if temp_dir and lfs.attributes(temp_dir, "mode") == "directory" then
        -- Recursively remove directory
        local cmd = string.format("rm -rf %q", temp_dir)
        os.execute(cmd)
    end
end

return EpubProcessor

