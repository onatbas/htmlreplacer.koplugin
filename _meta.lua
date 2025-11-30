local _ = require("gettext")
return {
    name = "htmlreplacer",
    fullname = _("HTML Replacer"),
    description = _([[Apply regex-based replacements and add footnotes to EPUB HTML content before rendering.
Useful for removing unwanted elements, adding content, modifying markup, or inserting footnotes with proper EPUB structure.]]),
}

