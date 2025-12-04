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
local util = require("util")
local _ = require("gettext")

local HtmlReplacer = WidgetContainer:extend{
    name = "htmlreplacer",
    is_doc_only = true,
}

-- Cache directory for modified EPUBs (hidden from normal browsing)
local cache_dir = DataStorage:getDataDir() .. "/htmlreplacer_cache"

function HtmlReplacer:init()
    logger.info("HtmlReplacer: === Plugin Initialization ===")
    logger.info("HtmlReplacer: Cache directory:", cache_dir)
    
    -- Create cache directory if it doesn't exist
    if lfs.attributes(cache_dir, "mode") ~= "directory" then
        logger.info("HtmlReplacer: Cache directory does not exist, creating it...")
        local success = lfs.mkdir(cache_dir)
        if success then
            logger.info("HtmlReplacer: Cache directory created successfully")
        else
            logger.err("HtmlReplacer: Failed to create cache directory!")
        end
    else
        logger.info("HtmlReplacer: Cache directory already exists")
    end
    
    -- Replacements will be loaded per-document in onReadSettings
    self.replacements = {}
    
    -- Track original file path
    self.original_file = nil
    self.modified_file = nil
    self.is_using_cache = false
    
    self.ui.menu:registerToMainMenu(self)
    
    -- Register text selection menu items
    if self.ui.highlight then
        logger.info("HtmlReplacer: Registering highlight menu items")
        self:addToHighlightDialog()
    end
    
    logger.info("HtmlReplacer: Plugin initialization complete")
end

-- Add items to the text selection / highlight dialog
function HtmlReplacer:addToHighlightDialog()
    -- Add "Replacement rule" item
    self.ui.highlight:addToHighlightDialog("12_html_replacement_rule", function(highlight)
        return {
            text = _("Replacement rule"),
            callback = function()
                local selected_text = highlight.selected_text and highlight.selected_text.text
                if selected_text and selected_text ~= "" then
                    highlight:onClose()
                    self:addNewReplacementRuleDialog(selected_text)
                else
                    UIManager:show(InfoMessage:new{
                        text = _("No text selected."),
                    })
                end
            end,
        }
    end)
    
    -- Add "Footnote rule" item
    self.ui.highlight:addToHighlightDialog("12_html_footnote_rule", function(highlight)
        return {
            text = _("Footnote rule"),
            callback = function()
                local selected_text = highlight.selected_text and highlight.selected_text.text
                if selected_text and selected_text ~= "" then
                    highlight:onClose()
                    self:addNewFootnoteRuleDialog(selected_text)
                else
                    UIManager:show(InfoMessage:new{
                        text = _("No text selected."),
                    })
                end
            end,
        }
    end)
end

-- Add items to dictionary popup (for single word selections)
function HtmlReplacer:onDictButtonsReady(dict_popup, buttons)
    -- Add our buttons as a new row
    table.insert(buttons, {
        {
            text = _("Replacement rule"),
            callback = function()
                -- Try to get original selected text first, fallback to dictionary lookup word
                local selected_text = nil
                if dict_popup.highlight and dict_popup.highlight.selected_text then
                    selected_text = util.cleanupSelectedText(dict_popup.highlight.selected_text.text)
                end
                if not selected_text or selected_text == "" then
                    selected_text = dict_popup.lookupword
                end
                
                if selected_text and selected_text ~= "" then
                    dict_popup:onClose()
                    self:addNewReplacementRuleDialog(selected_text)
                end
            end,
        },
        {
            text = _("Footnote rule"),
            callback = function()
                -- Try to get original selected text first, fallback to dictionary lookup word
                local selected_text = nil
                if dict_popup.highlight and dict_popup.highlight.selected_text then
                    selected_text = util.cleanupSelectedText(dict_popup.highlight.selected_text.text)
                end
                if not selected_text or selected_text == "" then
                    selected_text = dict_popup.lookupword
                end
                
                if selected_text and selected_text ~= "" then
                    dict_popup:onClose()
                    self:addNewFootnoteRuleDialog(selected_text)
                end
            end,
        },
    })
end

function HtmlReplacer:onReadSettings(config)
    local current_file = self.ui.document.file
    logger.info("HtmlReplacer: === onReadSettings START ===")
    logger.info("HtmlReplacer: Current file:", current_file)
    logger.info("HtmlReplacer: Cache directory:", cache_dir)
    
    -- Check if we're opening a cached file (simple path check)
    if current_file:find(cache_dir, 1, true) then
        logger.info("HtmlReplacer: Detected cached file")
        -- Read marker to find original
        local marker_file = current_file .. ".original_path"
        logger.dbg("HtmlReplacer: Looking for marker at:", marker_file)
        local f = io.open(marker_file, "r")
        if f then
            self.original_file = f:read("*line")
            f:close()
            self.modified_file = current_file
            self.is_using_cache = true
            logger.info("HtmlReplacer: Successfully read original file from marker:", self.original_file)
            
            -- Load rules from ORIGINAL file (so we can manage them)
            local DocSettings = require("docsettings")
            local original_settings = DocSettings:open(self.original_file)
            self.replacements = original_settings:readSetting("htmlreplacer_rules") or {}
            logger.info("HtmlReplacer: Loaded", #self.replacements, "rules from original file")
            
            -- Log each rule for debugging
            for i, rule in ipairs(self.replacements) do
                logger.dbg("HtmlReplacer: Rule", i, "- enabled:", rule.enabled, "pattern:", rule.pattern:sub(1, 50))
            end
            return
        else
            logger.warn("HtmlReplacer: Cache file detected but marker not found at:", marker_file)
            self.original_file = current_file
            self.is_using_cache = false
        end
    else
        -- Normal file
        logger.info("HtmlReplacer: Normal (non-cached) file detected")
        self.original_file = current_file
        self.is_using_cache = false
    end
    
    -- Load book-specific replacement rules
    self.replacements = config:readSetting("htmlreplacer_rules") or {}
    logger.info("HtmlReplacer: Loaded", #self.replacements, "rules from config")
    
    -- Log each rule for debugging
    for i, rule in ipairs(self.replacements) do
        logger.dbg("HtmlReplacer: Rule", i, "- enabled:", rule.enabled, "pattern:", rule.pattern:sub(1, 50))
    end
    
    logger.info("HtmlReplacer: === onReadSettings END ===")
end

function HtmlReplacer:onSaveSettings()
    logger.info("HtmlReplacer: === onSaveSettings START ===")
    logger.info("HtmlReplacer: is_using_cache:", self.is_using_cache)
    logger.info("HtmlReplacer: original_file:", self.original_file or "nil")
    logger.info("HtmlReplacer: Number of rules to save:", #self.replacements)
    
    -- If viewing cache, save to ORIGINAL file's settings
    if self.is_using_cache and self.original_file then
        local DocSettings = require("docsettings")
        local original_settings = DocSettings:open(self.original_file)
        original_settings:saveSetting("htmlreplacer_rules", self.replacements)
        original_settings:flush()
        logger.info("HtmlReplacer: Successfully saved", #self.replacements, "rules to original file")
    else
        -- Normal file, save to current
        self.ui.doc_settings:saveSetting("htmlreplacer_rules", self.replacements)
        logger.info("HtmlReplacer: Successfully saved", #self.replacements, "rules to current file")
    end
    logger.info("HtmlReplacer: === onSaveSettings END ===")
end

function HtmlReplacer:onReaderReady()
    -- Cache is just a preview now, no special handling needed
    -- User will manually "Apply" when they want permanent changes
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
            local rule_type = rule.type or "replacement"
            if rule_type == "footnote" then
                table.insert(parts, string.format("%s|%s|%s|%s", 
                    rule_type, rule.pattern, rule.delimiter or "*", rule.footnote_text or ""))
            else
                table.insert(parts, string.format("%s|%s|%s", 
                    rule_type, rule.pattern, rule.replacement or ""))
            end
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
    
    UIManager:show(InfoMessage:new{
        text = _("Loading cached preview..."),
        timeout = 1,
        flush_events_on_show = true,
    })
    
    UIManager:scheduleIn(0.1, function()
        if self.ui.switchDocument then
            self.ui:switchDocument(cache_file, true)
        end
    end)
end

function HtmlReplacer:processAndReload()
    logger.info("HtmlReplacer: === processAndReload START ===")
    logger.info("HtmlReplacer: original_file:", self.original_file or "nil")
    logger.info("HtmlReplacer: Number of rules:", #self.replacements)
    
    if not self.original_file then
        logger.err("HtmlReplacer: No original file set, cannot process")
        UIManager:show(InfoMessage:new{
            text = _("No EPUB file to process."),
        })
        return
    end
    
    -- Count enabled rules
    local enabled_count = 0
    for _, rule in ipairs(self.replacements) do
        if rule.enabled then
            enabled_count = enabled_count + 1
        end
    end
    logger.info("HtmlReplacer: Enabled rules:", enabled_count)
    
    UIManager:show(InfoMessage:new{
        text = _("Creating preview with replacements...\nThis may take a moment."),
        timeout = 3,
        flush_events_on_show = true,
    })
    
    -- Process EPUB in background (or at least show we're working)
    UIManager:scheduleIn(0.1, function()
        logger.info("HtmlReplacer: Starting EPUB processing...")
        local EpubProcessor = require("epubprocessor")
        local processor = EpubProcessor:new(cache_dir) -- Use cache directory
        
        local modified_file = processor:processEpub(self.original_file, self.replacements)
        
        if modified_file then
            logger.info("HtmlReplacer: EPUB processing successful, cache file:", modified_file)
            self.modified_file = modified_file
            self.is_using_cache = true
            
            -- Set up symlink BEFORE switching documents
            logger.info("HtmlReplacer: Setting up cache symlinks...")
            self:setupCacheSymlinks(modified_file, self.original_file)
            
            -- Now trigger a document reload with the modified file
            UIManager:show(InfoMessage:new{
                text = _("Preview ready! Loading...\n\nUse 'Apply Changes' to make permanent."),
                timeout = 2,
                flush_events_on_show = true,
            })
            
            -- Wait a bit then reload
            UIManager:scheduleIn(0.5, function()
                logger.info("HtmlReplacer: Reloading with modified file...")
                self:reloadWithModifiedFile(modified_file)
            end)
        else
            logger.err("HtmlReplacer: EPUB processing failed - processor returned nil")
            UIManager:show(InfoMessage:new{
                text = _("Failed to process EPUB. Check logs for details."),
            })
        end
    end)
    logger.info("HtmlReplacer: === processAndReload END (scheduled) ===")
end

function HtmlReplacer:setupCacheSymlinks(cache_file, original_file)
    -- Just write marker files, no settings sync needed
    
    -- Write marker file with original path
    local marker_file = cache_file .. ".original_path"
    local f = io.open(marker_file, "w")
    if f then
        f:write(original_file)
        f:close()
        logger.info("HtmlReplacer: Wrote marker file")
    else
        logger.err("HtmlReplacer: Failed to write marker file!")
    end
    
    -- Write rules hash for cache validation
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
end


function HtmlReplacer:reloadWithModifiedFile(modified_file)
    -- Just switch to the cached preview
    if self.ui.switchDocument then
        self.ui:switchDocument(modified_file, true)
    end
end

function HtmlReplacer:addToMainMenu(menu_items)
    -- Add as a submenu under Style tweaks for better organization
    if not menu_items.style_tweaks then
        -- Fallback: create our own top-level menu if style_tweaks doesn't exist
        menu_items.content_tweaks = self:getMenuTable()
        return
    end
    
    -- Check if we've already added ourselves (to prevent duplicates)
    local style_tweaks_table = menu_items.style_tweaks.sub_item_table
    for _, item in ipairs(style_tweaks_table) do
        if item.text_func then
            local text = item.text_func()
            if text and text:match("HTML content tweaks") then
                -- Already in menu, skip
                return
            end
        end
    end
    
    -- Insert our menu as first item in style_tweaks submenu
    table.insert(style_tweaks_table, 1, {
        text_func = function()
            local replacement_count = 0
            local footnote_count = 0
            for _, rule in ipairs(self.replacements) do
                if rule.enabled then
                    local rule_type = rule.type or "replacement"
                    if rule_type == "footnote" then
                        footnote_count = footnote_count + 1
                    else
                        replacement_count = replacement_count + 1
                    end
                end
            end
            if replacement_count > 0 or footnote_count > 0 then
                return string.format(_("HTML content tweaks") .. " (%d+%d)", replacement_count, footnote_count)
            else
                return _("HTML content tweaks")
            end
        end,
        sub_item_table = self:getMenuTable(),
        separator = true,
    })
end

function HtmlReplacer:getMenuTable()
    return {
            {
                text = _("Toggle Rules"),
                keep_menu_open = true,
                callback = function()
                    self:showAllRulesDialog()
                end,
            },
            {
                text = _("Add Replacement Rule"),
                keep_menu_open = true,
                callback = function()
                    self:addNewReplacementRuleDialog()
                end,
            },
            {
                text = _("Add Footnote Rule"),
                keep_menu_open = true,
                callback = function()
                    self:addNewFootnoteRuleDialog()
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
                text = _("Apply Changes to Original"),
                enabled_func = function()
                    return self.is_using_cache
                end,
                callback = function()
                    self:applyChanges()
                end,
            },
            {
                text = _("Revert to Original"),
                enabled_func = function()
                    return self:hasBackup()
                end,
                callback = function()
                    self:revertChanges()
                end,
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

Apply regex-based replacements and add footnotes to EPUB HTML content.

RULE TYPES:
• Replacement Rules - Replace matched text
• Footnote Rules - Add footnotes with proper EPUB structure

WORKFLOW:
1. Add rules (book-specific)
2. "Reload with Replacements" - preview in cache
3. Optionally create CSS tweaks in cache
4. "Apply Changes" - make permanent (backs up original)
5. "Revert" - restore from backup if needed

• All rules are BOOK-SPECIFIC
• Preview creates temporary cache
• CSS tweaks in cache auto-copied to original on apply
• Apply replaces original file
• Original backed up to cache/originals/

Lua Pattern Syntax (IMPORTANT):
  .-  = non-greedy (matches MINIMUM)
  .+  = greedy (matches MAXIMUM)

Examples:
  Replacement: <span>(.-)</span> → %1
  Footnote: Pattern + Delimiter + Text
  
Use "Check" button to verify matches!]]),
                    })
                end,
            },
        }
end

function HtmlReplacer:showAllRulesDialog()
    local buttons = {}
    
    for i, rule in ipairs(self.replacements) do
        local rule_type = rule.type or "replacement"
        local type_icon = rule_type == "footnote" and "📝" or "🔄"
        local display_text = rule.description or rule.pattern:sub(1, 35)
        
        table.insert(buttons, {{
            text = string.format("%s %s %s", 
                rule.enabled and "☑" or "☐",
                type_icon,
                display_text),
            align = "left",
            callback = function()
                rule.enabled = not rule.enabled
                self:onSaveSettings()
                UIManager:show(InfoMessage:new{
                    text = _("Rule toggled.\n\nUse 'Reload with Replacements' to preview."),
                    timeout = 2,
                })
            end,
        }})
    end
    
    local ButtonDialog = require("ui/widget/buttondialog")
    UIManager:show(ButtonDialog:new{
        title = _("Toggle All Rules (Book-Specific)"),
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
        table.insert(content_lines, "-- Use 'Add Replacement Rule' or 'Add Footnote Rule'")
    else
        for i, rule in ipairs(self.replacements) do
            local rule_type = rule.type or "replacement"
            local status = rule.enabled and "ENABLED" or "DISABLED"
            
            table.insert(content_lines, string.format("-- Rule %d: %s (%s)", i, rule_type:upper(), status))
            if rule.description then
                table.insert(content_lines, string.format("-- Description: %s", rule.description))
            end
            table.insert(content_lines, string.format('pattern = %q', rule.pattern))
            
            if rule_type == "footnote" then
                table.insert(content_lines, string.format('delimiter = %q', rule.delimiter or "*"))
                table.insert(content_lines, string.format('footnote_text = %q', rule.footnote_text or ""))
            else
                table.insert(content_lines, string.format('replacement = %q', rule.replacement))
            end
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

function HtmlReplacer:addNewReplacementRuleDialog(default_pattern)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    default_pattern = default_pattern or ""
    
    local input_dialog
    input_dialog = MultiInputDialog:new{
        title = _("Add New Replacement Rule"),
        fields = {
            {
                text = default_pattern,
                hint = "Pattern (use .- not .+ ): <span>(.-)</span>",
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
                            self:checkPattern(fields[1], fields[2])
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
                                type = "replacement",
                                pattern = fields[1],
                                replacement = fields[2],
                                description = fields[3] ~= "" and fields[3] or nil,
                                enabled = true, -- Enabled by default
                            })
                            self:onSaveSettings()
                            UIManager:close(input_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("Replacement rule added and enabled.\n\nUse 'Reload with Replacements' to preview."),
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

function HtmlReplacer:addNewFootnoteRuleDialog(default_pattern)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    default_pattern = default_pattern or ""
    
    local input_dialog
    input_dialog = MultiInputDialog:new{
        title = _("Add New Footnote Rule"),
        fields = {
            {
                text = default_pattern,
                hint = "Pattern to match: <span>tuberculosis</span>",
                input_type = "string",
            },
            {
                text = "*",
                hint = "Delimiter: *, **, †, etc.",
                input_type = "string",
            },
            {
                text = "",
                hint = "Footnote text (will appear at bottom)",
                input_type = "text",
            },
            {
                text = "",
                hint = "Repeat limiter (chars, 0=all): 2000",
                input_type = "number",
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
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local fields = input_dialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" and fields[3] ~= "" then
                            local repeat_limiter = tonumber(fields[4]) or 0
                            table.insert(self.replacements, {
                                type = "footnote",
                                pattern = fields[1],
                                delimiter = fields[2],
                                footnote_text = fields[3],
                                repeat_limiter = repeat_limiter,
                                description = fields[5] ~= "" and fields[5] or nil,
                                enabled = true, -- Enabled by default
                            })
                            self:onSaveSettings()
                            UIManager:close(input_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("Footnote rule added and enabled.\n\nUse 'Reload with Replacements' to preview."),
                                timeout = 3,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Pattern, delimiter, and footnote text are required."),
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
            text = _("No rules to manage.\n\nUse 'Add Replacement Rule' or 'Add Footnote Rule' to create rules."),
        })
        return
    end
    
    local buttons = {}
    
    for i, rule in ipairs(self.replacements) do
        local rule_type = rule.type or "replacement"
        local type_icon = rule_type == "footnote" and "📝" or "🔄"
        local display_text = rule.description or rule.pattern:sub(1, 35)
        
        table.insert(buttons, {{
            text = string.format("%s %s %s", 
                rule.enabled and "☑" or "☐",
                type_icon,
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
    local rule_type = rule.type or "replacement"
    
    if rule_type == "footnote" then
        self:editFootnoteRule(index, rule)
    else
        self:editReplacementRule(index, rule)
    end
end

function HtmlReplacer:editReplacementRule(index, rule)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    
    local input_dialog
    input_dialog = MultiInputDialog:new{
        title = _("Edit Replacement Rule"),
        fields = {
            {
                text = rule.pattern or "",
                hint = "Pattern (use .- not .+ ): <span>(.-)</span>",
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
                            self:checkPattern(fields[1], fields[2])
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

function HtmlReplacer:editFootnoteRule(index, rule)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    
    local input_dialog
    input_dialog = MultiInputDialog:new{
        title = _("Edit Footnote Rule"),
        fields = {
            {
                text = rule.pattern or "",
                hint = "Pattern to match: <span>tuberculosis</span>",
                input_type = "string",
            },
            {
                text = rule.delimiter or "*",
                hint = "Delimiter: *, **, †, etc.",
                input_type = "string",
            },
            {
                text = rule.footnote_text or "",
                hint = "Footnote text (will appear at bottom)",
                input_type = "text",
            },
            {
                text = tostring(rule.repeat_limiter or 0),
                hint = "Repeat limiter (chars, 0=all): 2000",
                input_type = "number",
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
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = input_dialog:getFields()
                        if fields[1] ~= "" and fields[2] ~= "" and fields[3] ~= "" then
                            -- Update the rule
                            self.replacements[index].pattern = fields[1]
                            self.replacements[index].delimiter = fields[2]
                            self.replacements[index].footnote_text = fields[3]
                            self.replacements[index].repeat_limiter = tonumber(fields[4]) or 0
                            self.replacements[index].description = fields[5] ~= "" and fields[5] or nil
                            
                            self:onSaveSettings()
                            UIManager:close(input_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("Footnote rule updated."),
                                timeout = 2,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Pattern, delimiter, and footnote text are required."),
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
    local rule_type = rule.type or "replacement"
    
    local details
    if rule_type == "footnote" then
        details = string.format([[Type: Footnote Rule
Status: %s

Pattern:
%s

Delimiter:
%s

Footnote Text:
%s

%s]],
            rule.enabled and "ENABLED" or "DISABLED",
            rule.pattern,
            rule.delimiter or "*",
            rule.footnote_text or "",
            rule.description and ("Description:\n" .. rule.description) or "")
    else
        details = string.format([[Type: Replacement Rule
Status: %s

Pattern:
%s

Replacement:
%s

%s]],
            rule.enabled and "ENABLED" or "DISABLED",
            rule.pattern,
            rule.replacement,
            rule.description and ("Description:\n" .. rule.description) or "")
    end
    
    UIManager:show(TextViewer:new{
        title = _("Rule Details"),
        text = details,
        text_face = Font:getFace("smallinfont"),
    })
end

function HtmlReplacer:checkPattern(pattern, replacement)
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
        flush_events_on_show = true,
    })
    
    UIManager:scheduleIn(0.1, function()
        local matches = {}
        local total_count = 0
        
        -- Extract EPUB to temp directory (Android-safe approach)
        local temp_base = os.tmpname()
        if temp_base then
            os.remove(temp_base)  -- Remove the file that os.tmpname() created
        else
            logger.err("HtmlReplacer: os.tmpname() returned nil")
            UIManager:show(InfoMessage:new{
                text = _("Failed to create temporary file name."),
            })
            return
        end
        
        local temp_dir = temp_base .. "_epub_check"
        local mkdir_result = lfs.mkdir(temp_dir)
        
        if not mkdir_result then
            logger.err("HtmlReplacer: Failed to create temp directory:", temp_dir)
            UIManager:show(InfoMessage:new{
                text = _("Failed to create temporary directory.\n\nPath: ") .. temp_dir,
            })
            return
        end
        
        logger.info("HtmlReplacer: Created temp directory:", temp_dir)
        
        local cmd = string.format("unzip -q %q -d %q", file, temp_dir)
        logger.info("HtmlReplacer: Running unzip command:", cmd)
        local result = os.execute(cmd)
        
        if result == 0 or result == true then
            logger.info("HtmlReplacer: Unzip successful, searching for pattern matches")
            
            -- Search all HTML files
            local pattern_error = nil
            local function searchDirectory(dir)
                -- Check if we already hit an error
                if pattern_error then
                    return
                end
                
                local dir_iter, dir_obj = lfs.dir(dir)
                if not dir_iter then
                    logger.warn("HtmlReplacer: Cannot read directory:", dir)
                    return
                end
                
                for entry in dir_iter, dir_obj do
                    if entry ~= "." and entry ~= ".." then
                        local path = dir .. "/" .. entry
                        local attr = lfs.attributes(path)
                        
                        if not attr then
                            logger.warn("HtmlReplacer: Cannot get attributes for:", path)
                        elseif attr.mode == "directory" then
                            searchDirectory(path)
                        elseif attr.mode == "file" and path:match("%.x?html$") then
                            local f = io.open(path, "r")
                            if f then
                                local content = f:read("*all")
                                f:close()
                                
                                -- Find all matches and show what will be replaced
                                -- Wrap in pcall to catch pattern errors
                                local search_pos = 1
                                while search_pos <= #content do
                                    -- Safely try to find the pattern
                                    local success, match_start, match_end = pcall(function()
                                        return content:find(pattern, search_pos)
                                    end)
                                    
                                    if not success then
                                        -- Pattern error occurred
                                        pattern_error = match_start
                                        logger.err("HtmlReplacer: Pattern error:", match_start)
                                        break
                                    end
                                    
                                    if match_start then
                                        total_count = total_count + 1
                                        if #matches < 5 then
                                            -- Extract the full matched text
                                            local matched_text = content:sub(match_start, match_end)
                                            
                                            -- Apply the replacement to show what it becomes
                                            local replace_success, replaced_text = pcall(function()
                                                return matched_text:gsub(pattern, replacement or "")
                                            end)
                                            
                                            if not replace_success then
                                                logger.warn("HtmlReplacer: Replacement error:", replaced_text)
                                                replaced_text = "[Replacement Error]"
                                            end
                                            
                                            table.insert(matches, {
                                                before = matched_text,
                                                after = replaced_text
                                            })
                                        end
                                        search_pos = match_end + 1
                                    else
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            searchDirectory(temp_dir)
            
            -- Cleanup
            logger.info("HtmlReplacer: Cleaning up temp directory")
            os.execute(string.format("rm -rf %q", temp_dir))
            
            -- Check if we hit a pattern error
            if pattern_error then
                UIManager:show(InfoMessage:new{
                    text = _("Pattern syntax error:\n\n") .. tostring(pattern_error),
                    timeout = 5,
                })
                return
            end
            
            -- Show results
            local TextViewer = require("ui/widget/textviewer")
            local result_text = string.format("Pattern: %s\nReplacement: %s\n\nTotal matches: %d\n\n", 
                pattern, replacement or "(none)", total_count)
            
            if #matches > 0 then
                result_text = result_text .. "First " .. #matches .. " examples:\n\n"
                result_text = result_text .. "NOTE: In Lua patterns, '.+' is greedy (matches maximum).\n"
                result_text = result_text .. "Use '.-' for non-greedy (matches minimum).\n\n"
                for i, match_pair in ipairs(matches) do
                    result_text = result_text .. string.format("--- Example %d ---\n", i)
                    result_text = result_text .. string.format("BEFORE (%d chars): %s\n", 
                        #match_pair.before, match_pair.before:sub(1, 200))
                    if #match_pair.before > 200 then
                        result_text = result_text .. "... (truncated)\n"
                    end
                    if replacement and replacement ~= "" then
                        result_text = result_text .. string.format("AFTER  (%d chars): %s\n", 
                            #match_pair.after, match_pair.after:sub(1, 200))
                        if #match_pair.after > 200 then
                            result_text = result_text .. "... (truncated)\n"
                        end
                    end
                    result_text = result_text .. "\n"
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
            -- Cleanup temp directory even on failure
            logger.err("HtmlReplacer: unzip command failed, result code:", result)
            os.execute(string.format("rm -rf %q", temp_dir))
            
            UIManager:show(InfoMessage:new{
                text = _("Failed to extract EPUB for pattern checking.\n\nCheck that the file is a valid EPUB.\n\nSee logs for details."),
                timeout = 5,
            })
        end
    end)
end

function HtmlReplacer:clearCache()
    UIManager:show(InfoMessage:new{
        text = _("Clearing cache..."),
        timeout = 1,
        flush_events_on_show = true,
    })
    
    -- Remove all files in cache directory (but not originals folder)
    local count = 0
    if lfs.attributes(cache_dir, "mode") == "directory" then
        for file in lfs.dir(cache_dir) do
            if file ~= "." and file ~= ".." and file ~= "originals" then
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

function HtmlReplacer:hasBackup()
    if not self.original_file then
        return false
    end
    
    local backup_path = self:getBackupPath(self.original_file)
    return lfs.attributes(backup_path, "mode") == "file"
end

function HtmlReplacer:getBackupPath(original_file)
    -- Store backups in cache/originals/
    local originals_dir = cache_dir .. "/originals"
    
    -- Create originals directory if it doesn't exist
    if lfs.attributes(originals_dir, "mode") ~= "directory" then
        lfs.mkdir(originals_dir)
    end
    
    -- Use filename from original path
    local filename = original_file:match("([^/]+)$")
    return originals_dir .. "/" .. filename
end

function HtmlReplacer:applyChanges()
    if not self.is_using_cache or not self.original_file or not self.modified_file then
        UIManager:show(InfoMessage:new{
            text = _("Not viewing a cached file. Nothing to apply."),
        })
        return
    end
    
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = _("This will REPLACE the original EPUB with the modified version.\n\nThe original will be backed up to the cache folder.\n\nContinue?"),
        ok_text = _("Apply"),
        ok_callback = function()
            self:doApplyChanges()
        end,
    })
end

function HtmlReplacer:doApplyChanges()
    logger.info("HtmlReplacer: === doApplyChanges START ===")
    logger.info("HtmlReplacer: is_using_cache:", self.is_using_cache)
    logger.info("HtmlReplacer: original_file:", self.original_file or "nil")
    logger.info("HtmlReplacer: modified_file:", self.modified_file or "nil")
    
    UIManager:show(InfoMessage:new{
        text = _("Applying changes..."),
        timeout = 2,
        flush_events_on_show = true,
    })
    
    UIManager:scheduleIn(0.1, function()
        logger.info("HtmlReplacer: Step 0 - Checking for CSS tweaks to copy...")
        -- Step 0: Copy CSS tweaks from cache to original if they exist
        local DocSettings = require("docsettings")
        local cache_settings = DocSettings:open(self.modified_file)
        local original_settings = DocSettings:open(self.original_file)
        
        local cache_css = cache_settings:readSetting("book_style_tweak")
        logger.dbg("HtmlReplacer: Cache CSS length:", cache_css and #cache_css or 0)
        
        if cache_css and cache_css ~= "" then
            logger.info("HtmlReplacer: Found CSS tweaks in cache, copying to original...")
            local original_css = original_settings:readSetting("book_style_tweak") or ""
            logger.dbg("HtmlReplacer: Original CSS length:", #original_css)
            
            -- Append cache CSS with a marker
            if original_css ~= "" then
                original_css = original_css .. "\n\n"
            end
            original_css = original_css .. "/* ========== COPIED FROM CACHE FILE ========== */\n" .. cache_css
            
            original_settings:saveSetting("book_style_tweak", original_css)
            original_settings:saveSetting("book_style_tweak_enabled", true) -- Enable it
            original_settings:flush()
            
            logger.info("HtmlReplacer: Successfully copied CSS tweaks from cache to original")
        else
            logger.info("HtmlReplacer: No CSS tweaks in cache to copy")
        end
        
        -- Step 1: Backup original to cache/originals/ (only if backup doesn't exist)
        logger.info("HtmlReplacer: Step 1 - Checking backup...")
        local backup_path = self:getBackupPath(self.original_file)
        logger.info("HtmlReplacer: Backup path:", backup_path)
        
        -- Check if backup already exists
        if lfs.attributes(backup_path, "mode") == "file" then
            logger.info("HtmlReplacer: Backup already exists, preserving original backup")
        else
            logger.info("HtmlReplacer: No backup found, creating first backup")
            -- Copy original to backup (only once!)
            local success = self:copyFile(self.original_file, backup_path)
            if not success then
                logger.err("HtmlReplacer: Failed to backup original file!")
                UIManager:show(InfoMessage:new{
                    text = _("Failed to backup original file."),
                })
                return
            end
            logger.info("HtmlReplacer: Successfully created original backup at", backup_path)
        end
        
        -- Step 2: Copy modified cache to original location
        logger.info("HtmlReplacer: Step 2 - Replacing original with modified version...")
        logger.info("HtmlReplacer: Source (modified):", self.modified_file)
        logger.info("HtmlReplacer: Destination (original):", self.original_file)
        success = self:copyFile(self.modified_file, self.original_file)
        if not success then
            logger.err("HtmlReplacer: Failed to replace original file!")
            UIManager:show(InfoMessage:new{
                text = _("Failed to replace original file."),
            })
            return
        end
        
        logger.info("HtmlReplacer: Successfully replaced original with modified version")
        
        -- Step 3: Clean up cache files for this book
        logger.info("HtmlReplacer: Step 3 - Cleaning up cache files...")
        logger.info("HtmlReplacer: Removing cache file:", self.modified_file)
        os.remove(self.modified_file)
        logger.info("HtmlReplacer: Removing marker file:", self.modified_file .. ".original_path")
        os.remove(self.modified_file .. ".original_path")
        logger.info("HtmlReplacer: Removing hash file:", self.modified_file .. ".rules_hash")
        os.remove(self.modified_file .. ".rules_hash")
        
        -- Remove cache .sdr folder if it exists
        local DocSettings = require("docsettings")
        local cache_sdr = DocSettings:getSidecarDir(self.modified_file)
        logger.dbg("HtmlReplacer: Cache .sdr directory:", cache_sdr)
        if lfs.attributes(cache_sdr, "mode") == "directory" then
            logger.info("HtmlReplacer: Removing cache .sdr directory...")
            local rm_cmd = string.format("rm -rf %q", cache_sdr)
            os.execute(rm_cmd)
        else
            logger.info("HtmlReplacer: No cache .sdr directory to remove")
        end
        
        logger.info("HtmlReplacer: Successfully cleaned up cache files")
        
        -- Step 4: Reload with the original file (which now has modifications)
        logger.info("HtmlReplacer: Step 4 - Preparing to reload document...")
        local message = _("Changes applied! Reloading...")
        if cache_css and cache_css ~= "" then
            message = _("Changes applied!\n\nCSS tweaks also copied from cache.\n\nReloading...")
        end
        
        UIManager:show(InfoMessage:new{
            text = message,
            timeout = 2,
            flush_events_on_show = true,
        })
        
        UIManager:scheduleIn(0.5, function()
            logger.info("HtmlReplacer: Resetting cache state...")
            -- Reset state
            self.is_using_cache = false
            self.modified_file = nil
            
            -- Reload the original file
            logger.info("HtmlReplacer: Switching document to original file:", self.original_file)
            if self.ui.switchDocument then
                self.ui:switchDocument(self.original_file, true)
                logger.info("HtmlReplacer: Document switch initiated")
            else
                logger.err("HtmlReplacer: switchDocument function not available!")
            end
        end)
        logger.info("HtmlReplacer: === doApplyChanges END ===")
    end)
end

function HtmlReplacer:revertChanges()
    local backup_path = self:getBackupPath(self.original_file)
    
    if lfs.attributes(backup_path, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = _("No backup found."),
        })
        return
    end
    
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = _("This will REPLACE the current EPUB with the backed-up original.\n\nAny applied changes will be lost (but rules are kept).\n\nContinue?"),
        ok_text = _("Revert"),
        ok_callback = function()
            self:doRevertChanges(backup_path)
        end,
    })
end

function HtmlReplacer:doRevertChanges(backup_path)
    UIManager:show(InfoMessage:new{
        text = _("Reverting to original..."),
        timeout = 2,
        flush_events_on_show = true,
    })
    
    UIManager:scheduleIn(0.1, function()
        -- Copy backup to original location
        local success = self:copyFile(backup_path, self.original_file)
        if not success then
            UIManager:show(InfoMessage:new{
                text = _("Failed to restore original file."),
            })
            return
        end
        
        logger.info("HtmlReplacer: Restored original from backup")
        
        -- Clear any cache for this book
        local cache_file = self:getCacheFilePath(self.original_file)
        if lfs.attributes(cache_file, "mode") == "file" then
            os.remove(cache_file)
            os.remove(cache_file .. ".original_path")
            os.remove(cache_file .. ".rules_hash")
            
            -- Remove cache .sdr folder if it exists
            local DocSettings = require("docsettings")
            local cache_sdr = DocSettings:getSidecarDir(cache_file)
            if lfs.attributes(cache_sdr, "mode") == "directory" then
                os.execute(string.format("rm -rf %q", cache_sdr))
            end
        end
        
        -- Reload the reverted file
        UIManager:show(InfoMessage:new{
            text = _("Original restored! Reloading..."),
            timeout = 2,
            flush_events_on_show = true,
        })
        
        UIManager:scheduleIn(0.5, function()
            -- Reset state
            self.is_using_cache = false
            self.modified_file = nil
            
            -- Reload the original file
            if self.ui.switchDocument then
                self.ui:switchDocument(self.original_file, true)
            end
        end)
    end)
end

function HtmlReplacer:copyFile(src, dst)
    logger.dbg("HtmlReplacer: copyFile() - Source:", src)
    logger.dbg("HtmlReplacer: copyFile() - Destination:", dst)
    
    -- Check source file attributes
    local src_attr = lfs.attributes(src)
    if not src_attr then
        logger.err("HtmlReplacer: Source file does not exist or cannot be accessed:", src)
        return false
    end
    logger.dbg("HtmlReplacer: Source file size:", src_attr.size, "bytes")
    logger.dbg("HtmlReplacer: Source file mode:", src_attr.mode)
    
    local src_file = io.open(src, "rb")
    if not src_file then
        logger.err("HtmlReplacer: Failed to open source file for reading:", src)
        return false
    end
    
    local content = src_file:read("*all")
    src_file:close()
    
    if not content then
        logger.err("HtmlReplacer: Failed to read content from source file:", src)
        return false
    end
    logger.dbg("HtmlReplacer: Successfully read", #content, "bytes from source")
    
    local dst_file = io.open(dst, "wb")
    if not dst_file then
        logger.err("HtmlReplacer: Failed to open destination file for writing:", dst)
        return false
    end
    
    local write_result = dst_file:write(content)
    dst_file:close()
    
    if not write_result then
        logger.err("HtmlReplacer: Failed to write content to destination file:", dst)
        return false
    end
    
    -- Verify destination file was created
    local dst_attr = lfs.attributes(dst)
    if not dst_attr then
        logger.err("HtmlReplacer: Destination file was not created:", dst)
        return false
    end
    logger.dbg("HtmlReplacer: Successfully wrote", dst_attr.size, "bytes to destination")
    
    logger.info("HtmlReplacer: copyFile() successful -", src_attr.size, "bytes copied")
    return true
end

return HtmlReplacer

