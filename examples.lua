--[[--
HTML Replacer - Example Replacement Rules

Copy rules from here to your htmlreplacer_rules.lua file
Location: koreader/htmlreplacer_rules.lua

Each rule has three parts:
  pattern     = Lua regex pattern to match
  replacement = What to replace the match with
  enabled     = true/false to enable/disable the rule
]]--

return {
    --------------------------------------------------------
    -- REMOVING ELEMENTS
    --------------------------------------------------------
    
    -- Remove all <span> tags (keep content)
    { 
        pattern = "<span>(.-)</span>", 
        replacement = "%1", 
        enabled = false 
    },
    
    -- Remove all <div> with specific class
    { 
        pattern = '<div class="advertisement">.-</div>', 
        replacement = "", 
        enabled = false 
    },
    
    -- Remove empty paragraphs
    { 
        pattern = "<p>%s*</p>", 
        replacement = "", 
        enabled = false 
    },
    
    --------------------------------------------------------
    -- ADDING CONTENT
    --------------------------------------------------------
    
    -- Add content after specific text
    { 
        pattern = "<span>world</span>", 
        replacement = "<span>world</span><span class='inserted'> [INSERTED]</span>", 
        enabled = false 
    },
    
    -- Add footnote markers
    { 
        pattern = "(%d+)", 
        replacement = "<sup>%1</sup>", 
        enabled = false 
    },
    
    --------------------------------------------------------
    -- MODIFYING TAGS
    --------------------------------------------------------
    
    -- Convert <b> to <strong>
    { 
        pattern = "<b>(.-)</b>", 
        replacement = "<strong>%1</strong>", 
        enabled = false 
    },
    
    -- Convert <i> to <em>
    { 
        pattern = "<i>(.-)</i>", 
        replacement = "<em>%1</em>", 
        enabled = false 
    },
    
    -- Add class to all paragraphs
    { 
        pattern = "<p>", 
        replacement = '<p class="custom">', 
        enabled = false 
    },
    
    --------------------------------------------------------
    -- FIXING FORMATTING
    --------------------------------------------------------
    
    -- Fix non-breaking spaces
    { 
        pattern = "&nbsp;", 
        replacement = " ", 
        enabled = false 
    },
    
    -- Remove inline styles
    { 
        pattern = ' style=".-"', 
        replacement = "", 
        enabled = false 
    },
    
    -- Remove specific attributes
    { 
        pattern = ' id=".-"', 
        replacement = "", 
        enabled = false 
    },
    
    --------------------------------------------------------
    -- ADVANCED PATTERNS
    --------------------------------------------------------
    
    -- Wrap text in quotes with special span
    { 
        pattern = '"(.-)"', 
        replacement = '<span class="quote">"%1"</span>', 
        enabled = false 
    },
    
    -- Replace multiple line breaks with single
    { 
        pattern = "<br/>%s*<br/>", 
        replacement = "<br/>", 
        enabled = false 
    },
    
    -- Add auto-generated content based on context
    { 
        pattern = "<h1>(.-)</h1>", 
        replacement = '<h1>%1</h1><p class="chapter-subtitle">Chapter content follows...</p>', 
        enabled = false 
    },
    
    --------------------------------------------------------
    -- SPECIFIC USE CASES
    --------------------------------------------------------
    
    -- Example: Your specific use case from the question
    -- Remove span around "world"
    { 
        pattern = "<span>world</span>", 
        replacement = "world", 
        enabled = false 
    },
    
    -- Or add auto-insert after it
    { 
        pattern = "(<span>world</span>)", 
        replacement = "%1<span>autoinsert</span>", 
        enabled = false 
    },
    
    --------------------------------------------------------
    -- PATTERN SYNTAX REFERENCE
    --------------------------------------------------------
    --
    -- .         Any character
    -- .-        Match minimum chars (non-greedy)
    -- .+        Match one or more (greedy)
    -- %s        Whitespace
    -- %d        Digit
    -- %w        Word character (letter/digit)
    -- %p        Punctuation
    -- [abc]     Character class (a, b, or c)
    -- [^abc]    Negated class (not a, b, or c)
    -- ()        Capture group (use %1, %2, etc. in replacement)
    -- ^         Start of string
    -- $         End of string
    -- %         Escape special characters
    --
    -- More info: https://www.lua.org/manual/5.1/manual.html#5.4.1
    --------------------------------------------------------
}

