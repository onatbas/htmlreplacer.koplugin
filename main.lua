--[[--
HTML Replacer Plugin for KOReader
Applies regex-based replacements to EPUB HTML content before rendering.
]]--

local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local HtmlReplacer = WidgetContainer:extend{
    name = "htmlreplacer",
    is_doc_only = true,
}

-- Cache directory for modified EPUBs (hidden from normal browsing)
local cache_dir = DataStorage:getDataDir() .. "/htmlreplacer_cache"

function HtmlReplacer:init()
    -- Create cache directory if it doesn't exist
    if lfs.attributes(cache_dir, "mode") ~= "directory" then
        lfs.mkdir(cache_dir)
    end
    
    -- Replacements will be loaded per-document in onReadSettings
    self.replacements = {}
    
    -- Track original file path
    self.original_file = nil
    self.modified_file = nil
    self.is_using_cache = false
    
    self.ui.menu:registerToMainMenu(self)
end

function HtmlReplacer:onReadSettings(config)
    local current_file = self.ui.document.file
    logger.warn("HtmlReplacer: onReadSettings called for file:", current_file)
    logger.warn("HtmlReplacer: Cache dir is:", cache_dir)
    
    -- Check if we're opening a cached file
    if current_file:match("^" .. cache_dir:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) then
        logger.warn("HtmlReplacer: Detected we're in cache directory")
        -- We're in cache, read the marker to find original
        local marker_file = current_file .. ".original_path"
        logger.warn("HtmlReplacer: Looking for marker at:", marker_file)
        
        local f = io.open(marker_file, "r")
        if f then
            self.original_file = f:read("*line")
            f:close()
            self.modified_file = current_file
            self.is_using_cache = true
            logger.warn("HtmlReplacer: Found marker! Original:", self.original_file)
            
            -- CRITICAL: Replace ui.doc_settings to point to original file
            -- This ensures ALL settings (including our rules) use the original
            local DocSettings = require("docsettings")
            self.ui.doc_settings = DocSettings:open(self.original_file)
            logger.warn("HtmlReplacer: Replaced doc_settings to point to original")
            
            -- Load rules from the now-correct doc_settings
            self.replacements = self.ui.doc_settings:readSetting("htmlreplacer_rules") or {}
            logger.warn("HtmlReplacer: Loaded", #self.replacements, "rules from original file")
            return
        else
            logger.warn("HtmlReplacer: Cache file but no marker found at:", marker_file)
            self.original_file = current_file
            self.is_using_cache = false
        end
    else
        logger.warn("HtmlReplacer: Not in cache, using normal file")
        -- Normal file
        self.original_file = current_file
        self.is_using_cache = false
    end
    
    -- Load book-specific replacement rules from current file
    self.replacements = config:readSetting("htmlreplacer_rules") or {}
    logger.warn("HtmlReplacer: Loaded", #self.replacements, "rules for this book")
end

function HtmlReplacer:onSaveSettings()
    -- doc_settings now always points to the right place (original when using cache)
    self.ui.doc_settings:saveSetting("htmlreplacer_rules", self.replacements)
    logger.info("HtmlReplacer: Saved", #self.replacements, "rules")
    
    -- Update BookList cache for the original file
    if self.is_using_cache and self.original_file then
        local BookList = require("readcollection")
        BookList.setBookInfoCache(self.original_file, self.ui.doc_settings)
    end
end

function HtmlReplacer:onReaderReady()
    -- If viewing cache, intercept history to track original file
    if self.is_using_cache and self.original_file then
        logger.info("HtmlReplacer: Viewing cached file, will track original in history")
        
        -- Remove cache from history and add original instead
        local ReadHistory = require("readhistory")
        ReadHistory:removeItemByPath(self.ui.document.file)
        ReadHistory:addItem(self.original_file)
        
        return
    end
    
    -- Check if current document needs processing
    if self.ui.document and self.ui.document.file then
        local file = self.ui.document.file
        
        -- Only process EPUBs, not cache files
        if (file:match("%.epub$") or file:match("%.epub3$")) and not file:match("^" .. cache_dir:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) then
            self.original_file = file
            
            -- Check if we have any enabled replacements
            if self:hasEnabledReplacements() then
                -- Check if cache exists and is up-to-date
                local cache_file = self:getCacheFilePath(file)
                local rules_hash = self:getRulesHash()
                
                if self:isCacheValid(cache_file, rules_hash) then
                    logger.info("HtmlReplacer: Using existing cache (rules unchanged)")
                    self:switchToCachedFile(cache_file)
                else
                    logger.info("HtmlReplacer: Rules changed or no cache, regenerating...")
                    self:processAndReload()
                end
            end
        end
    end
end

function HtmlReplacer:hasEnabledReplacements()
    for _, rule in ipairs(self.replacements) do
        if rule.enabled then
            return true
        end
    end
    return false
end

function HtmlReplacer:getRulesHash()
    -- Create hash of enabled rules
    local md5 = require("ffi/sha2").md5
    local parts = {}
    for _, rule in ipairs(self.replacements) do
        if rule.enabled then
            table.insert(parts, rule.pattern .. "|" .. rule.replacement)
        end
    end
    return md5(table.concat(parts, "\n"))
end

function HtmlReplacer:getCacheFilePath(original_file)
    -- Same logic as EpubProcessor
    local md5 = require("ffi/sha2").md5
    local hash = md5(original_file)
    local filename = hash:sub(1, 16) .. ".epub"
    return cache_dir .. "/" .. filename
end

function HtmlReplacer:isCacheValid(cache_file, current_rules_hash)
    -- Check if cache file exists
    if lfs.attributes(cache_file, "mode") ~= "file" then
        return false
    end
    
    -- Check if marker exists and has matching rules hash
    local marker_file = cache_file .. ".original_path"
    local hash_file = cache_file .. ".rules_hash"
    
    if lfs.attributes(marker_file, "mode") ~= "file" then
        return false
    end
    
    -- Read stored hash
    local f = io.open(hash_file, "r")
    if not f then
        return false
    end
    
    local stored_hash = f:read("*line")
    f:close()
    
    -- Compare hashes
    local valid = stored_hash == current_rules_hash
    logger.info("HtmlReplacer: Cache hash check - stored:", stored_hash, "current:", current_rules_hash, "valid:", valid)
    return valid
end

function HtmlReplacer:switchToCachedFile(cache_file)
    self.modified_file = cache_file
    self.is_using_cache = true
    
    -- Always ensure symlink exists, even for existing cache
    self:ensureCacheSymlink(cache_file, self.original_file)
    
    UIManager:show(InfoMessage:new{
        text = _("Loading cached version..."),
        timeout = 1,
    })
    
    UIManager:scheduleIn(0.1, function()
        if self.ui.switchDocument then
            self.ui:switchDocument(cache_file, true)
        end
    end)
end

function HtmlReplacer:processAndReload()
    if not self.original_file then
        UIManager:show(InfoMessage:new{
            text = _("No EPUB file to process."),
        })
        return
    end
    
    UIManager:show(InfoMessage:new{
        text = _("Processing EPUB with HTML replacements...\nThis may take a moment."),
        timeout = 3,
    })
    
    -- Process EPUB in background (or at least show we're working)
    UIManager:scheduleIn(0.1, function()
        local EpubProcessor = require("epubprocessor")
        local processor = EpubProcessor:new(cache_dir) -- Use cache directory
        
        local modified_file = processor:processEpub(self.original_file, self.replacements)
        
        if modified_file then
            self.modified_file = modified_file
            self.is_using_cache = true
            
            -- Set up symlink BEFORE switching documents
            self:setupCacheSymlinks(modified_file, self.original_file)
            
            -- Now trigger a document reload with the modified file
            UIManager:show(InfoMessage:new{
                text = _("Processing complete. Reloading document..."),
                timeout = 2,
            })
            
            -- Wait a bit then reload
            UIManager:scheduleIn(0.5, function()
                self:reloadWithModifiedFile(modified_file)
            end)
        else
            UIManager:show(InfoMessage:new{
                text = _("Failed to process EPUB. Check logs for details."),
            })
        end
    end)
end

function HtmlReplacer:setupCacheSymlinks(cache_file, original_file)
    -- Save settings to original first
    self:onSaveSettings()
    
    -- Write marker file with original path so we can find it later
    local marker_file = cache_file .. ".original_path"
    logger.warn("HtmlReplacer: Writing marker file:", marker_file)
    logger.warn("HtmlReplacer: Original file path:", original_file)
    
    local f = io.open(marker_file, "w")
    if f then
        f:write(original_file)
        f:close()
        logger.warn("HtmlReplacer: Successfully wrote marker file")
    else
        logger.err("HtmlReplacer: Failed to write marker file!")
    end
    
    -- Write rules hash so we can check if cache is still valid
    local hash_file = cache_file .. ".rules_hash"
    local rules_hash = self:getRulesHash()
    f = io.open(hash_file, "w")
    if f then
        f:write(rules_hash)
        f:close()
        logger.info("HtmlReplacer: Wrote rules hash:", rules_hash)
    else
        logger.err("HtmlReplacer: Failed to write rules hash!")
    end
    
    -- Create the symlink
    self:ensureCacheSymlink(cache_file, original_file)
end

function HtmlReplacer:ensureCacheSymlink(cache_file, original_file)
    -- Symlink the entire .sdr directory so ALL settings use the original
    local DocSettings = require("docsettings")
    local original_sdr = DocSettings:getSidecarDir(original_file)
    local cache_sdr = DocSettings:getSidecarDir(cache_file)
    
    logger.info("HtmlReplacer: Ensuring .sdr symlink")
    logger.info("HtmlReplacer: Original .sdr:", original_sdr)
    logger.info("HtmlReplacer: Cache .sdr:", cache_sdr)
    
    -- Ensure original .sdr exists
    if lfs.attributes(original_sdr, "mode") ~= "directory" then
        lfs.mkdir(original_sdr)
        logger.info("HtmlReplacer: Created original .sdr")
    end
    
    -- Check if symlink already exists and is correct
    local cache_sdr_mode = lfs.attributes(cache_sdr, "mode")
    if cache_sdr_mode == "link" then
        -- Check if it points to the right place
        local util = require("util")
        local target = io.popen("readlink " .. util.shell_escape({cache_sdr})):read("*line")
        if target == original_sdr then
            logger.info("HtmlReplacer: .sdr symlink already correct")
            return
        else
            logger.info("HtmlReplacer: Removing incorrect symlink")
            os.remove(cache_sdr)
        end
    elseif cache_sdr_mode == "directory" then
        -- Remove existing directory
        local util = require("util")
        os.execute("rm -rf " .. util.shell_escape({cache_sdr}))
        logger.info("HtmlReplacer: Removed cache .sdr directory")
    end
    
    -- Create symlink from cache .sdr to original .sdr
    local util = require("util")
    local ln_cmd = "ln -s " .. util.shell_escape({original_sdr}) .. " " .. util.shell_escape({cache_sdr})
    local result = os.execute(ln_cmd)
    
    if result == 0 or result == true then
        logger.info("HtmlReplacer: Created .sdr symlink - ALL settings now use original")
    else
        logger.err("HtmlReplacer: Failed to create .sdr symlink:", ln_cmd)
    end
end

function HtmlReplacer:reloadWithModifiedFile(modified_file)
    -- Symlinks already set up by setupCacheSymlinks(), just switch documents
    if self.ui.switchDocument then
        self.ui:switchDocument(modified_file, true)
    end
end

function HtmlReplacer:addToMainMenu(menu_items)
    menu_items.content_tweaks = {
        text_func = function()
            local enabled_count = 0
            for _, rule in ipairs(self.replacements) do
                if rule.enabled then
                    enabled_count = enabled_count + 1
                end
            end
            if enabled_count > 0 then
                return _("Content tweaks") .. " (" .. enabled_count .. ")"
            else
                return _("Content tweaks")
            end
        end,
        sub_item_table = {
            {
                text = _("Toggle Replacement Rules"),
                keep_menu_open = true,
                callback = function()
                    self:showReplacementsDialog()
                end,
            },
            {
                text = _("Add New Rule"),
                keep_menu_open = true,
                callback = function()
                    self:addNewRuleDialog()
                end,
            },
            {
                text = _("Manage Rules"),
                keep_menu_open = true,
                callback = function()
                    self:manageRulesDialog()
                end,
            },
            {
                text = _("View Current Rules"),
                callback = function()
                    self:editReplacementRules()
                end,
            },
            {
                text = _("Reload with Replacements"),
                callback = function()
                    -- Always allow reload, even with no rules (creates clean cache)
                    self:processAndReload()
                end,
                separator = true,
            },
            {
                text = _("Clear Cache"),
                callback = function()
                    self:clearCache()
                end,
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _([[HTML Replacer Plugin

Apply regex-based replacements to EPUB HTML content before rendering.

• All rules are BOOK-SPECIFIC
• Rules saved in book's .sdr folder
• Changes require document reload
• See examples.lua for pattern ideas

Pattern syntax: Lua regex
Examples:
  <span>(.-)</span> → %1
  <b>(.-)</b> → <strong>%1</strong>]]),
                    })
                end,
            },
        },
    }
end

function HtmlReplacer:showReplacementsDialog()
    local buttons = {}
    
    for i, rule in ipairs(self.replacements) do
        local display_text = rule.description or rule.pattern:sub(1, 40)
        table.insert(buttons, {{
            text = string.format("%s %s", 
                rule.enabled and "☑" or "☐",
                display_text),
            align = "left",
            callback = function()
                rule.enabled = not rule.enabled
                self:onSaveSettings()
                UIManager:show(InfoMessage:new{
                    text = _("Replacement rule toggled.\n\nUse 'Reload with Replacements' to apply changes."),
                    timeout = 2,
                })
            end,
        }})
    end
    
    -- Add button to add new rule
    table.insert(buttons, {{
        text = "+ " .. _("Add New Rule"),
        align = "left",
        callback = function()
            self:addNewRuleDialog()
        end,
    }})
    
    local ButtonDialog = require("ui/widget/buttondialog")
    UIManager:show(ButtonDialog:new{
        title = _("Toggle Replacement Rules (Book-Specific)"),
        buttons = buttons,
    })
end

function HtmlReplacer:editReplacementRules()
    -- Show current rules for this book
    local TextViewer = require("ui/widget/textviewer")
    local content_lines = {
        "-- HTML Replacer Rules for This Book",
        "-- These rules are book-specific (stored in .sdr folder)",
        "",
    }
    
    if #self.replacements == 0 then
        table.insert(content_lines, "-- No rules defined yet")
        table.insert(content_lines, "-- Use 'Add New Rule' to create rules")
    else
        for i, rule in ipairs(self.replacements) do
            local status = rule.enabled and "ENABLED" or "DISABLED"
            table.insert(content_lines, string.format("-- Rule %d: %s", i, status))
            if rule.description then
                table.insert(content_lines, string.format("-- Description: %s", rule.description))
            end
            table.insert(content_lines, string.format('pattern = %q', rule.pattern))
            table.insert(content_lines, string.format('replacement = %q', rule.replacement))
            table.insert(content_lines, "")
        end
    end
    
    table.insert(content_lines, "")
    table.insert(content_lines, "-- See examples.lua in plugin folder for more patterns")
    
    local content = table.concat(content_lines, "\n")
    
    UIManager:show(TextViewer:new{
        title = _("HTML Replacer Rules (This Book)"),
        text = content,
        text_face = Font:getFace("smallinfont"),
        justified = false,
    })
end

function HtmlReplacer:addNewRuleDialog()
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    
    local input_dialog
    input_dialog = MultiInputDialog:new{
        title = _("Add New Replacement Rule"),
        fields = {
            {
                text = "",
                hint = "Pattern (Lua regex): <span>(.-)</span>",
                input_type = "string",
            },
            {
                text = "",
                hint = "Replacement: %1 or new text",
                input_type = "string",
            },
            {
                text = "",
                hint = "Description (optional)",
                input_type = "string",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Check"),
                    callback = function()
                        local fields = input_dialog:getFields()
                        if fields[1] ~= "" then
                            self:checkPattern(fields[1])
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Pattern is required to check."),
                            })
                        end
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local fields = input_dialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" then
                            table.insert(self.replacements, {
                                pattern = fields[1],
                                replacement = fields[2],
                                description = fields[3] ~= "" and fields[3] or nil,
                                enabled = true, -- Enabled by default
                            })
                            self:onSaveSettings()
                            UIManager:close(input_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("Rule added and enabled.\n\nUse 'Reload with Replacements' to apply."),
                                timeout = 3,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Pattern and replacement are required."),
                            })
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function HtmlReplacer:manageRulesDialog()
    if #self.replacements == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No rules to manage.\n\nUse 'Add New Rule' to create rules."),
        })
        return
    end
    
    local buttons = {}
    
    for i, rule in ipairs(self.replacements) do
        local display_text = rule.description or rule.pattern:sub(1, 40)
        table.insert(buttons, {{
            text = string.format("%s %s", 
                rule.enabled and "☑" or "☐",
                display_text),
            align = "left",
            callback = function()
                self:showRuleActions(i, rule)
            end,
        }})
    end
    
    local ButtonDialog = require("ui/widget/buttondialog")
    UIManager:show(ButtonDialog:new{
        title = _("Manage Rules (Tap to Edit/Delete)"),
        buttons = buttons,
    })
end

function HtmlReplacer:showRuleActions(index, rule)
    local ButtonDialog = require("ui/widget/buttondialog")
    local display = rule.description or rule.pattern
    
    UIManager:show(ButtonDialog:new{
        title = display,
        buttons = {
            {
                {
                    text = rule.enabled and _("Disable") or _("Enable"),
                    callback = function()
                        rule.enabled = not rule.enabled
                        self:onSaveSettings()
                        UIManager:show(InfoMessage:new{
                            text = rule.enabled and _("Rule enabled.") or _("Rule disabled."),
                            timeout = 1,
                        })
                    end,
                },
            },
            {
                {
                    text = _("Edit"),
                    callback = function()
                        self:editRule(index, rule)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        self:confirmDeleteRule(index, rule)
                    end,
                },
            },
        },
    })
end

function HtmlReplacer:editRule(index, rule)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    
    local input_dialog
    input_dialog = MultiInputDialog:new{
        title = _("Edit Replacement Rule"),
        fields = {
            {
                text = rule.pattern or "",
                hint = "Pattern (Lua regex): <span>(.-)</span>",
                input_type = "string",
            },
            {
                text = rule.replacement or "",
                hint = "Replacement: %1 or new text",
                input_type = "string",
            },
            {
                text = rule.description or "",
                hint = "Description (optional)",
                input_type = "string",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Check"),
                    callback = function()
                        local fields = input_dialog:getFields()
                        if fields[1] ~= "" then
                            self:checkPattern(fields[1])
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Pattern is required to check."),
                            })
                        end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = input_dialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" then
                            -- Update the rule
                            self.replacements[index].pattern = fields[1]
                            self.replacements[index].replacement = fields[2]
                            self.replacements[index].description = fields[3] ~= "" and fields[3] or nil
                            
                            self:onSaveSettings()
                            UIManager:close(input_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("Rule updated."),
                                timeout = 2,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Pattern and replacement are required."),
                            })
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function HtmlReplacer:confirmDeleteRule(index, rule)
    local ConfirmBox = require("ui/widget/confirmbox")
    local display = rule.description or rule.pattern:sub(1, 50)
    
    UIManager:show(ConfirmBox:new{
        text = _("Delete this rule?\n\n") .. display,
        ok_callback = function()
            table.remove(self.replacements, index)
            self:onSaveSettings()
            UIManager:show(InfoMessage:new{
                text = _("Rule deleted."),
                timeout = 2,
            })
        end,
    })
end

function HtmlReplacer:showRuleDetails(rule)
    local TextViewer = require("ui/widget/textviewer")
    local details = string.format([[Status: %s

Pattern:
%s

Replacement:
%s

%s]],
        rule.enabled and "ENABLED" or "DISABLED",
        rule.pattern,
        rule.replacement,
        rule.description and ("Description:\n" .. rule.description) or "")
    
    UIManager:show(TextViewer:new{
        title = _("Rule Details"),
        text = details,
        text_face = Font:getFace("smallinfont"),
    })
end

function HtmlReplacer:checkPattern(pattern)
    -- Get current document HTML content to check pattern against
    if not self.ui.document or not self.ui.document.file then
        UIManager:show(InfoMessage:new{
            text = _("No document loaded."),
        })
        return
    end
    
    -- For EPUBs, we need to extract and check HTML files
    local file = self.ui.document.file
    if not (file:match("%.epub$") or file:match("%.epub3$")) then
        UIManager:show(InfoMessage:new{
            text = _("Pattern checking only works with EPUB files."),
        })
        return
    end
    
    UIManager:show(InfoMessage:new{
        text = _("Checking pattern..."),
        timeout = 1,
    })
    
    UIManager:scheduleIn(0.1, function()
        local matches = {}
        local total_count = 0
        
        -- Extract EPUB to temp directory
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        lfs.mkdir(temp_dir)
        
        local cmd = string.format("unzip -q %q -d %q", file, temp_dir)
        local result = os.execute(cmd)
        
        if result == 0 or result == true then
            -- Search all HTML files
            local function searchDirectory(dir)
                for entry in lfs.dir(dir) do
                    if entry ~= "." and entry ~= ".." then
                        local path = dir .. "/" .. entry
                        local attr = lfs.attributes(path)
                        
                        if attr.mode == "directory" then
                            searchDirectory(path)
                        elseif attr.mode == "file" and path:match("%.x?html$") then
                            local f = io.open(path, "r")
                            if f then
                                local content = f:read("*all")
                                f:close()
                                
                                -- Count matches
                                for match in content:gmatch(pattern) do
                                    total_count = total_count + 1
                                    if #matches < 5 then
                                        table.insert(matches, match)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            searchDirectory(temp_dir)
            
            -- Cleanup
            os.execute(string.format("rm -rf %q", temp_dir))
            
            -- Show results
            local TextViewer = require("ui/widget/textviewer")
            local result_text = string.format("Pattern: %s\n\nTotal matches: %d\n\n", pattern, total_count)
            
            if #matches > 0 then
                result_text = result_text .. "First " .. #matches .. " matches:\n\n"
                for i, match in ipairs(matches) do
                    result_text = result_text .. string.format("%d. %s\n\n", i, match:sub(1, 100))
                end
            else
                result_text = result_text .. "No matches found."
            end
            
            UIManager:show(TextViewer:new{
                title = _("Pattern Check Results"),
                text = result_text,
                text_face = Font:getFace("smallinfont"),
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Failed to extract EPUB for pattern checking."),
            })
        end
    end)
end

function HtmlReplacer:clearCache()
    UIManager:show(InfoMessage:new{
        text = _("Clearing cache..."),
        timeout = 1,
    })
    
    -- Remove all files in cache directory
    local count = 0
    if lfs.attributes(cache_dir, "mode") == "directory" then
        for file in lfs.dir(cache_dir) do
            if file ~= "." and file ~= ".." then
                local filepath = cache_dir .. "/" .. file
                os.remove(filepath)
                logger.info("HtmlReplacer: Removed cached file:", filepath)
                count = count + 1
            end
        end
    end
    
    UIManager:show(InfoMessage:new{
        text = count > 0 and _("Cache cleared.") or _("Cache was already empty."),
        timeout = 2,
    })
end

return HtmlReplacer

