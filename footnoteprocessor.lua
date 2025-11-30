--[[--
Footnote Processor - Handles insertion of footnotes into HTML files
]]--

local logger = require("logger")

local FootnoteProcessor = {}

function FootnoteProcessor:new()
    local o = {
        footnote_counter = 0,
        footnotes = {},
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function FootnoteProcessor:reset()
    self.footnote_counter = 0
    self.footnotes = {}
end

function FootnoteProcessor:processHtmlFile(filepath, footnote_rules)
    -- Read file
    local f = io.open(filepath, "rb")  -- Binary mode for faster read
    if not f then
        logger.warn("FootnoteProcessor: Cannot open", filepath)
        return false
    end
    
    local content = f:read("*all")
    f:close()
    
    if not content or content == "" then
        return false
    end
    
    -- Reset footnotes for this file
    self:reset()
    
    local modified = false
    
    -- Apply each enabled footnote rule
    for _, rule in ipairs(footnote_rules) do
        if rule.enabled and rule.type == "footnote" then
            local repeat_limiter = rule.repeat_limiter or 0
            local success, result = pcall(function()
                return self:insertFootnotes(content, rule.pattern, rule.delimiter, rule.footnote_text, filepath, repeat_limiter)
            end)
            
            if not success then
                logger.err("FootnoteProcessor: Error processing footnote rule:", result)
            elseif result ~= content then
                content = result
                modified = true
            end
        end
    end
    
    -- If we added footnotes, append the footnotes section
    if modified and #self.footnotes > 0 then
        content = self:appendFootnotesSection(content)
        
        -- Write back modified content
        f = io.open(filepath, "wb")  -- Binary mode for faster write
        if f then
            f:write(content)
            f:close()
            logger.info("FootnoteProcessor: Added", #self.footnotes, "footnotes to", filepath)
            return true
        else
            logger.err("FootnoteProcessor: Failed to write modified file:", filepath)
        end
    end
    
    return false
end

function FootnoteProcessor:insertFootnotes(content, pattern, delimiter, footnote_text, filepath, repeat_limiter)
    -- Find the filename without path for unique IDs
    local filename = filepath:match("([^/]+)%.x?html$") or "file"
    
    -- Collect all matches first
    local matches = {}
    local search_pos = 1
    local last_footnote_pos = -999999  -- Initialize far in the past
    
    repeat_limiter = repeat_limiter or 0
    
    while search_pos <= #content do
        local match_start, match_end = content:find(pattern, search_pos)
        
        if match_start then
            -- Check if we should add this footnote based on repeat limiter
            local should_add = true
            if repeat_limiter > 0 then
                local distance = match_start - last_footnote_pos
                if distance < repeat_limiter then
                    should_add = false
                end
            end
            
            if should_add then
                self.footnote_counter = self.footnote_counter + 1
                
                local footnote_id = string.format("footnote-%s-%03d", filename, self.footnote_counter)
                local backlink_id = footnote_id .. "-backlink"
                local matched_text = content:sub(match_start, match_end)
                
                table.insert(matches, {
                    start_pos = match_start,
                    end_pos = match_end,
                    matched_text = matched_text,
                    footnote_id = footnote_id,
                    backlink_id = backlink_id
                })
                
                -- Store the footnote immediately in correct order with matched text
                table.insert(self.footnotes, {
                    id = footnote_id,
                    backlink_id = backlink_id,
                    delimiter = delimiter,
                    matched_text = matched_text,  -- Include matched text for footnote display
                    text = footnote_text,
                })
                
                last_footnote_pos = match_start
            end
            
            search_pos = match_end + 1
        else
            break
        end
    end
    
    if #matches == 0 then
        return content
    end
    
    logger.info("FootnoteProcessor: Found", #matches, "matches for pattern:", pattern:sub(1, 50))
    
    -- Build the result by processing matches in reverse order
    -- This way we don't need to adjust positions as we insert
    local result_parts = {}
    local last_pos = #content + 1
    
    for i = #matches, 1, -1 do
        local match = matches[i]
        
        -- Create the inline footnote reference - NO square brackets, with superscript
        local inline_ref = string.format(
            '%s<sup><a class="Footnote-Reference" epub:type="noteref" href="#%s" id="%s" role="doc-noteref" title="footnote">%s</a></sup>',
            match.matched_text,
            match.footnote_id,
            match.backlink_id,
            delimiter
        )
        
        -- Add the part after this match
        table.insert(result_parts, 1, content:sub(match.end_pos + 1, last_pos - 1))
        
        -- Add the inline reference
        table.insert(result_parts, 1, inline_ref)
        
        last_pos = match.start_pos
    end
    
    -- Add the part before the first match
    table.insert(result_parts, 1, content:sub(1, last_pos - 1))
    
    -- Concatenate all parts once
    return table.concat(result_parts)
end

function FootnoteProcessor:appendFootnotesSection(content)
    -- Generate the footnotes HTML once
    local footnotes_html = self:generateFootnotesHtml(true) -- Always include wrapper for now
    
    -- Simple approach: Just insert before </body> if it exists
    local body_end = content:find('</body>', 1, true)
    
    if body_end then
        -- Insert right before </body>
        return content:sub(1, body_end - 1) .. "\n" .. footnotes_html .. "\n" .. content:sub(body_end)
    else
        -- Fallback: append at the end
        return content .. "\n" .. footnotes_html
    end
end

function FootnoteProcessor:generateFootnotesHtml(include_wrapper)
    local html_parts = {}
    
    if include_wrapper then
        table.insert(html_parts, '\t\t\t<div class="footnotes" epub:type="footnotes">')
    end
    
    for _, footnote in ipairs(self.footnotes) do
        -- Format: Delimiter (Matched Text): Description
        local footnote_content
        if footnote.matched_text then
            footnote_content = string.format('%s (%s): %s', 
                footnote.delimiter,
                footnote.matched_text,
                footnote.text
            )
        else
            -- Fallback to old format if matched_text not available
            footnote_content = string.format('%s %s', 
                footnote.delimiter,
                footnote.text
            )
        end
        
        table.insert(html_parts, string.format(
            '\t\t\t\t<div class="footnote" epub:type="footnote" id="%s" role="doc-footnote">',
            footnote.id
        ))
        table.insert(html_parts, string.format(
            '\t\t\t\t\t<p class="xFootnote"><a class="_idFootnoteAnchor" href="#%s" role="doc-backlink" title="footnote reference">%s</a></p>',
            footnote.backlink_id,
            footnote_content
        ))
        table.insert(html_parts, '\t\t\t\t</div>')
    end
    
    if include_wrapper then
        table.insert(html_parts, '\t\t\t</div>')
    end
    
    return table.concat(html_parts, "\n")
end

return FootnoteProcessor

