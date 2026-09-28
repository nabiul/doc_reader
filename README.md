# DocReader

Flutter document reader with PDF tools, scanning, OCR, annotation, and a
backend-free native OOXML renderer.

## Native Office renderer

DOCX, XLSX, PPTX, and RTF files are parsed and rendered locally in Flutter. No
network connection or conversion backend is required. The renderer currently
supports:

- Word paragraphs, headings, run formatting, alignment, highlights, and tables
- Excel worksheets, tabs, shared strings, column widths, and core cell styles
- PowerPoint slide geometry, text boxes, fills, font styles, and embedded images
- Local RTF text decoding

Legacy binary DOC, XLS, and PPT files still require a compatible external app.
