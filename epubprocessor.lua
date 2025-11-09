--[[--
EPUB Processor - Extracts, modifies, and repackages EPUB files
]]--

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5

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
    
    -- Create temp directory
    local temp_dir = os.tmpname()
    os.remove(temp_dir) -- Remove the file
    lfs.mkdir(temp_dir) -- Create as directory
    
    -- Use system unzip command (most e-readers have this)
    local cmd = string.format("unzip -q %q -d %q", epub_path, temp_dir)
    local result = os.execute(cmd)
    
    if result == 0 or result == true then
        return temp_dir
    else
        logger.err("EpubProcessor: unzip failed")
        return nil
    end
end

function EpubProcessor:applyReplacements(temp_dir, replacements)
    local count = 0
    
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
                        if self:processHtmlFile(path, replacements) then
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

function EpubProcessor:processHtmlFile(filepath, replacements)
    local f = io.open(filepath, "r")
    if not f then
        logger.warn("EpubProcessor: Cannot open", filepath)
        return false
    end
    
    local content = f:read("*all")
    f:close()
    
    local modified = false
    
    -- Apply each enabled replacement
    for _, rule in ipairs(replacements) do
        if rule.enabled then
            local new_content = content:gsub(rule.pattern, rule.replacement)
            if new_content ~= content then
                content = new_content
                modified = true
                logger.dbg("EpubProcessor: Applied rule to", filepath)
            end
        end
    end
    
    if modified then
        -- Write back modified content
        f = io.open(filepath, "w")
        if f then
            f:write(content)
            f:close()
            return true
        end
    end
    
    return false
end

function EpubProcessor:repackageEpub(temp_dir, output_path)
    -- Ensure cache directory exists and use absolute path
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
    
    -- Convert to absolute path if relative
    if not output_path:match("^/") then
        output_path = lfs.currentdir() .. "/" .. output_path
    end
    
    -- EPUB spec requires mimetype file to be first and uncompressed
    -- Then we can zip everything else
    
    -- First, create the mimetype file (uncompressed)
    local cmd = string.format("cd %q && zip -0 -X %q mimetype", temp_dir, output_path)
    local result = os.execute(cmd)
    
    if result ~= 0 and result ~= true then
        logger.err("EpubProcessor: Failed to create mimetype")
        return false
    end
    
    -- Then add everything else (compressed)
    cmd = string.format("cd %q && zip -r -X %q * -x mimetype", temp_dir, output_path)
    result = os.execute(cmd)
    
    if result == 0 or result == true then
        return true
    else
        logger.err("EpubProcessor: Failed to repackage EPUB")
        return false
    end
end

function EpubProcessor:cleanupTempDir(temp_dir)
    if temp_dir and lfs.attributes(temp_dir, "mode") == "directory" then
        -- Recursively remove directory
        local cmd = string.format("rm -rf %q", temp_dir)
        os.execute(cmd)
    end
end

return EpubProcessor

