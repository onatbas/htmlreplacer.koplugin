# HTML Replacer Plugin

Apply regex-based replacements and add footnotes to EPUB HTML content with a preview-and-apply workflow.

## Features

- **Two Rule Types**: Replacement rules and Footnote rules
- Apply Lua regex patterns to modify EPUB HTML content
- Remove unwanted elements (spans, divs, etc.)
- Add or modify content
- **Insert footnotes** with proper EPUB structure (links, backlinks, footnote sections)
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

### Quick Rule Creation from Selected Text

1. **Select any text** in your EPUB
2. In the selection menu, choose:
   - **"Replacement rule"** - Creates a replacement rule with the selected text as the pattern
   - **"Footnote rule"** - Creates a footnote rule with the selected text as the pattern
3. Fill in the remaining fields (replacement/footnote text, description)
4. The pattern field is automatically populated with your selection!

## Adding Rules

You can add rules in two ways:

### Method 1: From Selected Text (Quick & Easy!)

1. **Select text** in your EPUB (e.g., select "Vernon" or "tuberculosis")
2. In the popup menu, tap **"Replacement rule"** or **"Footnote rule"**
3. The pattern field is pre-filled with your selected text
4. Fill in the remaining fields and save

### Method 2: From the Menu

### Replacement Rules

**Menu → HTML Replacer → Add Replacement Rule**

Fill in:
- **Pattern**: Lua regex like `<span>(.-)</span>`
- **Replacement**: What to replace with, like `%1` (captured content)
- **Description**: Optional, helps you remember what the rule does

### Footnote Rules

**Menu → HTML Replacer → Add Footnote Rule**

Fill in:
- **Pattern**: Lua regex to match where to insert the footnote, like `tuberculosis`
- **Delimiter**: The footnote indicator (*, **, †, ‡, §, etc.)
- **Footnote text**: The actual footnote content that appears at the bottom
- **Repeat limiter**: Minimum characters between repeated footnotes (0 = add to all occurrences, 2000 = only repeat every 2000+ characters)
- **Description**: Optional, helps you remember what the rule does

The plugin will automatically:
- Insert inline footnote references with proper links (e.g., `Vernon` with superscript `*`)
- Create a footnotes section at the end of each HTML file
- Format footnotes as: `Delimiter (MatchedText): YourFootnoteText`
- Add proper EPUB structure with backlinks
- Delimiters appear as superscript (small and raised)

## Example Patterns

### Replacement Rules

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

### Footnote Rules

```lua
-- Add footnote to every occurrence of "tuberculosis"
-- Result inline: tuberculosis^* (superscript asterisk)
-- Result at bottom: * (tuberculosis): An infectious disease caused by...
pattern = "tuberculosis"
delimiter = "*"
footnote_text = "An infectious disease caused by Mycobacterium tuberculosis"
repeat_limiter = 0  -- 0 = add to ALL occurrences

-- Add footnote with repeat limiter (for common names that appear frequently)
-- Result inline: Vernon^† (superscript dagger) - but only every 2000+ chars
-- Result at bottom: † (Vernon): Harry's uncle
pattern = "Vernon"
delimiter = "†"
footnote_text = "Harry Potter's uncle, Vernon Dursley"
repeat_limiter = 2000  -- Only add footnote if 2000+ chars since last one

-- Add footnote to specific HTML patterns with high repeat limit
-- Result inline: pandemic^** (superscript double asterisk)
-- Result at bottom: ** (pandemic): An epidemic occurring worldwide...
pattern = '<span class="term">pandemic</span>'
delimiter = "**"
footnote_text = "An epidemic occurring worldwide, or over a very wide area"
repeat_limiter = 5000  -- Only repeat every 5000+ characters
```

**Repeat Limiter:**
- `0` = Add footnote to EVERY occurrence (default)
- `2000` = Add footnote only if 2000+ characters since the last one
- `5000` = Add footnote only if 5000+ characters since the last one

Note: The `^` symbol represents superscript formatting - the delimiter appears small and raised.

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
- **Apply creates backup ONCE**: Original is backed up to `htmlreplacer_cache/originals/` on first apply
- **Backup is never overwritten**: Once backed up, the original is preserved forever - you can always revert to the true original
- **Multiple edits safe**: You can apply changes multiple times; only the working copy gets updated
- **CSS tweaks auto-copied**: Any CSS tweaks in cache are appended to original on apply
- **Revert available**: Restore the true original anytime using "Revert to Original"
- **Rules are preserved**: Even after reverting, your rules remain in `.sdr` folder

## Testing Footnote Rules

To test the new footnote functionality:

1. Open an EPUB in KOReader
2. Go to **Menu → Style tweaks → HTML content tweaks**
3. Select **Add Footnote Rule**
4. Enter:
   - **Pattern**: A word or phrase that appears in your book (e.g., "tuberculosis")
   - **Delimiter**: `*` (or any symbol you prefer)
   - **Footnote text**: Your footnote content
5. Select **Reload with Replacements**
6. Navigate to a page where your pattern appears
7. You should see:
   - The inline reference `[*]` next to the matched text
   - When clicking the footnote link, it jumps to the footnote at the bottom
   - The footnote has a backlink to return to the text

## Troubleshooting

1. **Processing fails**: Check KOReader logs for specific errors
2. **Rules not applying**: Verify patterns with the "Check" button before saving
3. **Document won't open**: Try "Clear Cache" and reload
4. **Lost progress/settings**: Use "Revert to Original" then re-apply with corrected rules
5. **Footnotes not appearing**: Check that the pattern matches actual text in the EPUB
6. **Footnote format issues**: Ensure your EPUB reader supports EPUB 3 footnote structure
7. **Check logs**: Look in KOReader logs for detailed error messages

