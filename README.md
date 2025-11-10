# HTML Replacer Plugin

Apply regex-based replacements to EPUB HTML content with a preview-and-apply workflow.

## Features

- Apply Lua regex patterns to modify EPUB HTML content
- Remove unwanted elements (spans, divs, etc.)
- Add or modify content
- Enable/disable rules individually
- **All rules are BOOK-SPECIFIC** (stored with each book's metadata)
- **Preview changes** in a temporary cache before applying
- **Apply permanently** to replace the original EPUB (with backup)
- **Revert** to restore original from backup

## Workflow

1. **Add Rules**: Define regex patterns specific to this book
2. **Preview**: Use "Reload with Replacements" to create a temporary cached version
3. **Inspect**: Read the cached version to verify your changes
4. **Optional**: Create CSS tweaks while viewing the cache (they'll be copied on apply)
5. **Apply**: Use "Apply Changes to Original" to permanently replace the EPUB (original is backed up)
6. **Revert** (if needed): Use "Revert to Original" to restore from backup

### Important: Rules Are Book-Specific!

Each book has its own set of replacement rules, stored in the book's `.sdr` folder (just like CSS tweaks). Rules you create for one book won't affect other books.

## Quick Start

1. **Open an EPUB** in KOReader
2. **Access the menu**: Tap menu → Style → Content tweaks
3. **Add New Rule** to create patterns
4. **Reload with Replacements** to preview
5. **Apply Changes to Original** when satisfied

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

- "Reload with Replacements" creates a temporary cache for preview
- Cache is automatically managed (one cache per book)
- Cache is updated when rules change
- **Apply Changes** removes the cache and replaces the original permanently
- Use "Clear Cache" to manually remove all cached preview files

## Limitations

- Only works with EPUB files (not PDF, TXT, etc.)
- Uses KOReader's built-in archiver (no external dependencies)
- Processing large EPUBs may take a few seconds
- Malformed regex patterns may cause issues

## CSS Tweaks Integration

While viewing the cached preview, you can create CSS tweaks via **Style tweaks → Book-specific tweak**. When you click "Apply Changes to Original", these CSS tweaks will be automatically copied to the original file's settings with a marker comment:

```css
/* ========== COPIED FROM CACHE FILE ========== */
```

This lets you experiment with both HTML replacements and CSS tweaks together, then apply them all at once.

## Safety & Backups

- **Preview is non-destructive**: Cache files don't modify your original EPUB
- **Apply creates backup**: Original is backed up to `htmlreplacer_cache/originals/`
- **CSS tweaks auto-copied**: Any CSS tweaks in cache are appended to original on apply
- **Revert available**: Restore original anytime using "Revert to Original"
- **Rules are preserved**: Even after reverting, your rules remain in `.sdr` folder

## Troubleshooting

1. **Processing fails**: Check KOReader logs for specific errors
2. **Rules not applying**: Verify patterns with the "Check" button before saving
3. **Document won't open**: Try "Clear Cache" and reload
4. **Lost progress/settings**: Use "Revert to Original" then re-apply with corrected rules
5. **Check logs**: Look in KOReader logs for detailed error messages

