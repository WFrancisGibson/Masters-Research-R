##########################################
#########  Word reference document for R Markdown reports
#########  styles of project_folder_guide.docx + the styles pandoc needs
##########################################

## run once (and again if the guide changes); writes
## thesis/guide_reference.docx, the reference_docx of the Word reports in
## thesis/ (their tables are styled by thesis/guide_tables.lua)
guide_path <- here::here("project_folder_guide.docx")
out_path <- here::here("thesis", "guide_reference.docx")

##########################################
#########  read the styles of the guide
##########################################

tmp <- file.path(tempdir(), "guide_reference")
unlink(tmp, recursive = TRUE)
unzip(guide_path, exdir = tmp)
styles_path <- file.path(tmp, "word", "styles.xml")
styles <- paste(readLines(styles_path, encoding = "UTF-8", warn = FALSE),
                collapse = "\n")

## one style as xml: paragraph (ppr), run (rpr) properties
word_names <- c("Date", "Bibliography", "Block Text", "Footnote Text",
                "Footnote Reference", "Hyperlink")  # built-in Word styles
style_xml <- function(type, id, name, based_on, ppr = "", rpr = "") {
  paste0(
    "<w:style w:type=\"", type, "\"",
    if (!name %in% word_names) " w:customStyle=\"1\"",
    " w:styleId=\"", id, "\"><w:name w:val=\"", name,
    "\"/><w:basedOn w:val=\"", based_on, "\"/><w:qFormat/>",
    if (nchar(ppr) > 0) paste0("<w:pPr>", ppr, "</w:pPr>"),
    if (nchar(rpr) > 0) paste0("<w:rPr>", rpr, "</w:rPr>"),
    "</w:style>"
  )
}
font_size <- function(pt) {
  paste0("<w:sz w:val=\"", 2 * pt, "\"/><w:szCs w:val=\"", 2 * pt, "\"/>")
}
spacing <- function(before, after) {
  paste0(
    "<w:spacing w:before=\"", before, "\" w:after=\"", after,
    "\" w:line=\"240\" w:lineRule=\"auto\"/>"
  )
}
heading_font <- paste0(
  "<w:rFonts w:asciiTheme=\"majorHAnsi\" w:eastAsiaTheme=\"majorEastAsia\"",
  " w:hAnsiTheme=\"majorHAnsi\" w:cstheme=\"majorBidi\"/>"
)
accent <- "<w:color w:val=\"4F81BD\" w:themeColor=\"accent1\"/>"

##########################################
#########  table styles
##########################################

## Light Grid Accent 1 of the guide; pandoc always writes the table look
## firstRow = 1, firstColumn = 0, noHBand = 0, noVBand = 0, the guide has
## noVBand = 1: drop the column banding so the tables look like the guide
light_grid <- regmatches(
  styles,
  regexpr("<w:style [^>]*w:styleId=\"LightGrid-Accent1\".*?</w:style>",
          styles, perl = TRUE)
)
band_vert <- "<w:tblStylePr w:type=\"band1Vert\">.*?</w:tblStylePr>"
light_grid_new <- sub(band_vert, "", light_grid, perl = TRUE)
styles <- sub(light_grid, light_grid_new, styles, fixed = TRUE)

## "Table": the style pandoc gives a table when no filter is used
table_default <- sub("w:styleId=\"LightGrid-Accent1\"",
                     "w:customStyle=\"1\" w:styleId=\"Table\"",
                     light_grid_new, fixed = TRUE)
table_default <- sub("<w:name w:val=\"Light Grid Accent 1\"/>",
                     "<w:name w:val=\"Table\"/>", table_default, fixed = TRUE)

## tight copy for wide tables: left and right cell margin 0.03 in
table_tight <- sub("w:styleId=\"LightGrid-Accent1\"",
                   "w:customStyle=\"1\" w:styleId=\"LightGrid-Accent1-Tight\"",
                   light_grid_new, fixed = TRUE)
table_tight <- sub("<w:name w:val=\"Light Grid Accent 1\"/>",
                   "<w:name w:val=\"Light Grid Accent 1 Tight\"/>",
                   table_tight, fixed = TRUE)
table_tight <- gsub("<w:(left|right) w:w=\"108\" w:type=\"dxa\"/>",
                    "<w:\\1 w:w=\"43\" w:type=\"dxa\"/>", table_tight)

##########################################
#########  paragraph and character styles of pandoc
##########################################

## body text as the Normal paragraphs of the guide (11 pt, 10 pt after)
styles <- sub("(w:styleId=\"BodyText\".*?)<w:pPr><w:spacing[^>]*/></w:pPr>",
              "\\1", styles, perl = TRUE)

## table cells: "Compact" 10 pt as in the guide, smaller for wide tables,
## kept with the next row so that a table is not split over two pages;
## "Table Spacer" is the 6 pt gap the filter puts after every table
cell_sizes <- 9:6
new_styles <- c(
  table_default,
  table_tight,
  style_xml("paragraph", "FirstParagraph", "First Paragraph", "BodyText"),
  style_xml("paragraph", "Compact", "Compact", "Normal",
            paste0("<w:keepNext/><w:keepLines/>", spacing(0, 0)),
            font_size(10)),
  sapply(cell_sizes, function(pt) {
    style_xml("paragraph", paste0("TableText", pt), paste("Table Text", pt),
              "Compact", rpr = font_size(pt))
  }),
  style_xml("character", "TableFirstColumn", "Table First Column",
            "DefaultParagraphFont",
            rpr = paste0(heading_font, "<w:b/><w:bCs/>")),
  style_xml("paragraph", "TableSpacer", "Table Spacer", "Normal",
            paste0("<w:spacing w:before=\"0\" w:after=\"0\" w:line=\"120\"",
                   " w:lineRule=\"exact\"/>"), font_size(4)),
  style_xml("paragraph", "TableCaption", "Table Caption", "Caption",
            paste0("<w:keepNext/>", spacing(120, 60))),
  style_xml("paragraph", "ImageCaption", "Image Caption", "Caption",
            spacing(60, 200)),
  style_xml("paragraph", "Figure", "Figure", "Normal", spacing(120, 0)),
  style_xml("paragraph", "CaptionedFigure", "Captioned Figure", "Figure",
            "<w:keepNext/>"),
  style_xml("paragraph", "Author", "Author", "Normal",
            paste0("<w:keepNext/>", spacing(0, 60)),
            paste0(heading_font, "<w:i/><w:iCs/>", accent, font_size(12))),
  style_xml("paragraph", "Date", "Date", "Author"),
  style_xml("paragraph", "AbstractTitle", "Abstract Title", "Normal",
            paste0("<w:keepNext/>", spacing(300, 0)),
            paste0("<w:b/><w:bCs/>", font_size(10))),
  style_xml("paragraph", "Abstract", "Abstract", "Normal",
            spacing(100, 300), font_size(10)),
  style_xml("paragraph", "Bibliography", "Bibliography", "Normal"),
  style_xml("paragraph", "BlockText", "Block Text", "BodyText",
            "<w:ind w:left=\"480\" w:right=\"480\"/>"),
  style_xml("paragraph", "FootnoteText", "Footnote Text", "Normal",
            spacing(0, 0), font_size(9)),
  style_xml("paragraph", "FootnoteBlockText", "Footnote Block Text",
            "FootnoteText", "<w:ind w:left=\"480\" w:right=\"480\"/>"),
  style_xml("paragraph", "DefinitionTerm", "Definition Term", "Normal",
            "<w:keepNext/>", "<w:b/><w:bCs/>"),
  style_xml("paragraph", "Definition", "Definition", "Normal"),
  style_xml("character", "VerbatimChar", "Verbatim Char",
            "DefaultParagraphFont",
            rpr = paste0("<w:rFonts w:ascii=\"Consolas\"",
                         " w:hAnsi=\"Consolas\"/>", font_size(10))),
  style_xml("character", "SectionNumber", "Section Number",
            "DefaultParagraphFont"),
  style_xml("character", "FootnoteReference", "Footnote Reference",
            "DefaultParagraphFont",
            rpr = "<w:vertAlign w:val=\"superscript\"/>"),
  style_xml("character", "Hyperlink", "Hyperlink", "DefaultParagraphFont",
            rpr = accent)
)

## only the styles the guide does not have yet
ids <- sub(".*?w:styleId=\"([^\"]+)\".*", "\\1", new_styles, perl = TRUE)
has_id <- sapply(ids, function(id) {
  grepl(paste0("w:styleId=\"", id, "\""), styles, fixed = TRUE)
})
print(ids[has_id])  # already in the guide: kept as they are
styles <- sub("</w:styles>",
              paste0(paste(new_styles[!has_id], collapse = ""), "</w:styles>"),
              styles, fixed = TRUE)

##########################################
#########  write the reference document
##########################################

con <- file(styles_path, open = "wb", encoding = "UTF-8")
writeLines(styles, con, useBytes = FALSE)
close(con)

## [Content_Types].xml first, then the other parts
parts <- list.files(tmp, recursive = TRUE, all.files = TRUE)
parts <- c("[Content_Types].xml", setdiff(parts, "[Content_Types].xml"))
unlink(out_path)
zip::zip(normalizePath(out_path, mustWork = FALSE), parts, root = tmp)
print(out_path)
