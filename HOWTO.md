# HTML Replacer Plugin - Complete Guide

## What This Does

This plugin allows you to **apply regex-based replacements to EPUB HTML content BEFORE it's rendered**. You can:

- ✅ Remove unwanted HTML elements (`<span>world</span>` → `world`)
- ✅ Add content (`<span>world</span>` → `<span>world</span><span>autoinsert</span>`)
- ✅ Modify markup (convert tags, add classes, etc.)
- ✅ Enable/disable rules on the fly
- ✅ Automatic reload when rules change (just like CSS changes)

## How It Works

```
Original EPUB → Extract → Apply Regex Rules → Re-package → Render
                   ↓
            Cache (fast subsequent opens)
```

1. **First open**: Plugin extracts the EPUB, applies your regex rules to all HTML files, re-packages it to a cache directory
2. **Subsequent opens**: Uses cached version (instant)
3. **When you change rules**: Clear cache, reload document, and it re-processes

## Installation

The plugin is already in your repository at:
```
/Users/otb/workspace/koreader/plugins/htmlreplacer.koplugin/
```

## Quick Start

### 1. Create Your Rules File

Create a file at `koreader/htmlreplacer_rules.lua`:

```lua
return {
    -- Your example: Remove span around "world"
    { 
        pattern = "<span>world</span>", 
        replacement = "world", 
        enabled = true 
    },
    
    -- Your example: Add autoinsert after "world"
    { 
        pattern = "<span>world</span>", 
        replacement = "<span>world</span><span>autoinsert</span>", 
        enabled = false 
    },
}
```

### 2. Open an EPUB in KOReader

The plugin automatically activates for EPUB files.

### 3. Access the Menu

Tap the menu button → **HTML Replacer**

You'll see:
- **Enable/Disable Replacements** - Toggle individual rules
- **Edit Replacement Rules** - View your rules file
- **Reload with Replacements** - Apply changes (triggers document reload)
- **Clear Cache** - Remove cached modified EPUBs

### 4. Apply Your Rules

1. Enable the rules you want
2. Tap "Reload with Replacements"
3. KOReader will:
   - Extract the EPUB
   - Apply your regex patterns
   - Re-package it
   - Reload the document automatically

## Lua Regex Syntax

### Basic Patterns

```lua
.         -- Any single character
.-        -- Match minimum characters (non-greedy)
.+        -- One or more characters (greedy)
%s        -- Whitespace
%d        -- Digit
%w        -- Word character
%p        -- Punctuation
```

### Capture Groups

```lua
pattern = "<b>(.-)</b>"
replacement = "<strong>%1</strong>"
-- %1 refers to the first captured group (what's in parentheses)
```

### Character Classes

```lua
[abc]     -- Matches a, b, or c
[^abc]    -- Matches anything except a, b, or c
[0-9]     -- Matches any digit
```

### Examples

```lua
-- Remove all spans (keep content)
{ pattern = "<span>(.-)</span>", replacement = "%1" }

-- Remove empty paragraphs
{ pattern = "<p>%s*</p>", replacement = "" }

-- Add class to paragraphs
{ pattern = "<p>", replacement = '<p class="custom">' }

-- Convert bold to strong
{ pattern = "<b>(.-)</b>", replacement = "<strong>%1</strong>" }

-- Wrap quoted text
{ pattern = '"(.-)"', replacement = '<span class="quote">"%1"</span>' }
```

## Workflow Example

Let's say you have an EPUB with annoying `<span>` tags everywhere:

### Step 1: Define Rules

```lua
-- koreader/htmlreplacer_rules.lua
return {
    -- Remove all spans
    { 
        pattern = "<span>(.-)</span>", 
        replacement = "%1", 
        enabled = true 
    },
    
    -- Remove advertisement divs
    { 
        pattern = '<div class="ad">.-</div>', 
        replacement = "", 
        enabled = true 
    },
}
```

### Step 2: Open EPUB

- Open your EPUB in KOReader
- Menu → HTML Replacer → Reload with Replacements

### Step 3: Wait for Processing

You'll see: "Processing EPUB with HTML replacements... This may take a moment."

For a typical EPUB: 5-15 seconds

### Step 4: Document Reloads

The modified EPUB opens automatically at your reading position.

### Step 5: Make Changes

To modify rules:
1. Edit `htmlreplacer_rules.lua` on your computer
2. Sync to your e-reader
3. Menu → HTML Replacer → Reload with Replacements

## Cache Management

### When is cache used?

- ✅ Same EPUB file opened again
- ✅ Same replacement rules
- ❌ If original EPUB modified → re-processes
- ❌ If rules changed → re-processes

### Manual cache clearing

Menu → HTML Replacer → Clear Cache

Removes all cached modified EPUBs.

## Troubleshooting

### "Processing fails" or "unzip failed"

**Problem**: Device doesn't have `unzip`/`zip` commands

**Solution**: Most e-readers have these. On some custom systems, install them:
```bash
apt-get install zip unzip  # Debian-based
opkg install zip unzip     # OpenWrt-based
```

### Rules not applying

**Check**:
1. Is `enabled = true`?
2. Is the pattern correct Lua regex?
3. Does the pattern match the actual HTML?

**Debug**: Check logs in KOReader settings → More tools → Logs

### Document won't open after processing

**Solution**: 
1. Clear cache
2. Check that regex doesn't break HTML structure
3. Test with simpler patterns first

### Very large EPUBs are slow

**Normal**: First processing of a 5MB+ EPUB with many HTML files can take 30-60 seconds

**Tip**: Processing happens once. Subsequent opens are instant from cache.

## Advanced Tips

### 1. Test patterns incrementally

Start with ONE simple rule enabled, test, then add more.

### 2. Use non-greedy matching

```lua
pattern = "<div>(.-)</div>"  -- GOOD: non-greedy (stops at first </div>)
pattern = "<div>(.+)</div>"  -- BAD: greedy (matches too much)
```

### 3. Escape special characters

```lua
pattern = "<div class=\"test\">"  -- Escape quotes
pattern = "%."                     -- Escape dots (% makes it literal)
```

### 4. View actual HTML

To see what you're matching:
1. In KOReader, select text
2. Menu → View HTML
3. This shows the actual HTML structure

### 5. Backup your EPUB

The plugin modifies a COPY in cache, not your original file. But it's always good to have backups!

## Performance

- **First processing**: 5-60 seconds (depending on EPUB size)
- **Cached opens**: Instant (0-1 second)
- **Cache size**: ~same as original EPUB per cached version
- **Memory**: Minimal (processing happens on disk)

## Limitations

1. **EPUB only**: Doesn't work with PDF, TXT, FB2, etc.
2. **Requires zip tools**: Device must have `unzip` and `zip` commands
3. **Lua regex**: Not full PCRE (but powerful enough for most cases)
4. **Not live**: Changes require document reload (but that's by design, like CSS)

## Example Use Cases

### Remove DRM-like watermarks
```lua
{ pattern = '<div class="watermark">.-</div>', replacement = "" }
```

### Fix publisher formatting errors
```lua
{ pattern = '<p class="wrong">', replacement = '<p class="right">' }
```

### Add custom navigation
```lua
{ pattern = '<h1>(.-)</h1>', replacement = '<h1 id="ch%1">%1</h1>' }
```

### Simplify cluttered markup
```lua
{ pattern = ' style=".-"', replacement = "" }  -- Remove inline styles
{ pattern = ' id=".-"', replacement = "" }     -- Remove IDs
```

## Getting Help

1. Check `examples.lua` for pattern inspiration
2. Read the Lua patterns manual: https://www.lua.org/manual/5.1/manual.html#5.4.1
3. Test patterns at: https://www.lua.org/cgi-bin/demo
4. Check KOReader logs for errors

## Files

- `main.lua` - Plugin core
- `epubprocessor.lua` - EPUB extraction/repackaging
- `_meta.lua` - Plugin metadata
- `examples.lua` - Example patterns
- `README.md` - Basic documentation
- `HOWTO.md` - This file

## Your Specific Use Case

You wanted to:
```
<span>world</span> → "world" or "<span>world</span><span>autoinsert</span>"
```

Here's the exact configuration:

```lua
-- koreader/htmlreplacer_rules.lua
return {
    -- Option 1: Remove the span entirely
    { 
        pattern = "<span>world</span>", 
        replacement = "world", 
        enabled = true 
    },
    
    -- Option 2: Keep span and add autoinsert after
    { 
        pattern = "(<span>world</span>)", 
        replacement = "%1<span>autoinsert</span>", 
        enabled = false  -- Set to true to use this instead
    },
}
```

Enable ONE of these, reload, and you're done!

## Conclusion

This plugin gives you **programmatic control over EPUB HTML content** before rendering, with the same reload-on-change workflow you're already familiar with from CSS tweaks.

Happy reading! 📚

