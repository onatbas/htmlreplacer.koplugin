local _ = require("gettext")
return {
    name = "htmlreplacer",
    fullname = _("HTML Replacer"),
    description = _([[Apply regex-based replacements to EPUB HTML content before rendering.
Useful for removing unwanted elements, adding content, or modifying markup.]]),
}

