# HTML Replacer Plugin

Apply regex-based replacements to EPUB HTML content before rendering.

## Features

- Apply Lua regex patterns to modify EPUB HTML content
- Remove unwanted elements (spans, divs, etc.)
- Add or modify content
- Enable/disable rules individually
- **All rules are BOOK-SPECIFIC** (stored with each book's metadata)
- Automatic caching (only reprocesses when needed)
- Triggers document reload when replacements change

## Usage

1. **Open an EPUB** in KOReader
2. **Access the menu**: Tap menu → HTML Replacer
3. **Add New Rule** to create patterns (or enable example rules)
4. **Toggle Replacement Rules** to enable/disable rules
5. **Reload with Replacements** to apply changes

### Important: Rules Are Book-Specific!

Each book has its own set of replacement rules, stored in the book's `.sdr` folder (just like CSS tweaks). Rules you create for one book won't affect other books.

## Adding Rules

You can add rules directly from the KOReader menu:

**Menu → HTML Replacer → Add New Rule**

Fill in:
- **Pattern**: Lua regex like `<span>(.-)</span>`
- **Replacement**: What to replace with, like `%1` (captured content)
- **Description**: Optional, helps you remember what the rule does

Or use the default example rules that come with each book:
- Remove all span tags (disabled by default)
- Add "autoinsert" after "world" (disabled by default)

## Example Patterns

```lua
-- Remove all span tags but keep content
pattern = "<span>(.-)</span>"
replacement = "%1"

-- Add content after specific text
pattern = "<span>world</span>"
replacement = "<span>world</span><span> [INSERTED]</span>"

-- Remove specific classes
pattern = '<div class="advertisement">.-</div>'
replacement = ""

-- Convert bold to italic
pattern = "<b>(.-)</b>"
replacement = "<i>%1</i>"
```

## Lua Pattern Syntax

- `.` = any character
- `.-` = match minimum characters (non-greedy)
- `%1` = first captured group (in parentheses)
- `%d` = digit
- `%s` = whitespace
- `[abc]` = character class
- See: https://www.lua.org/manual/5.1/manual.html#5.4.1

## Performance Notes

- First load processes the EPUB and caches it
- Subsequent opens use the cached version (very fast)
- Cache is invalidated when:
  - Original EPUB is modified
  - Replacement rules change
- Use "Clear Cache" to manually remove cached files

## Limitations

- Only works with EPUB files (not PDF, TXT, etc.)
- Requires `unzip` and `zip` commands on device
- Processing large EPUBs may take a few seconds
- Malformed regex patterns may cause issues

## Troubleshooting

1. **Processing fails**: Check that `unzip` and `zip` are available
2. **Rules not applying**: Ensure patterns are valid Lua regex
3. **Document won't open**: Try "Clear Cache" and reload
4. **Check logs**: Look in KOReader logs for error messages

