import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfOfficeExporter {
  static Future<List<String>> extractPages(String path) async {
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(path);
      final pages = <String>[];
      for (final page in document.pages) {
        final text = await page.loadText();
        pages.add(text?.fullText.trim() ?? '');
      }
      if (pages.every((page) => page.isEmpty)) {
        throw const FormatException(
          'No selectable text was found. Run OCR on this scanned PDF first.',
        );
      }
      return pages;
    } finally {
      await document?.dispose();
    }
  }

  static Uint8List createWord(List<String> pages) {
    final body = StringBuffer();
    for (final page in pages.indexed) {
      final paragraphs = page.$2
          .split(RegExp(r'\n+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      for (final paragraph in paragraphs) {
        body.write(
          '<w:p><w:r><w:t xml:space="preserve">${_xml(paragraph)}</w:t></w:r></w:p>',
        );
      }
      if (page.$1 < pages.length - 1) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }
    final archive = Archive()
      ..addFile(
        _file(
          '[Content_Types].xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
              '</Types>',
        ),
      )
      ..addFile(
        _file(
          '_rels/.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        _file(
          'word/document.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
              '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
              '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>'
              '</w:body></w:document>',
        ),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static Uint8List createExcel(List<String> pages) {
    final archive = Archive();
    final overrides = StringBuffer();
    final sheets = StringBuffer();
    final relationships = StringBuffer();
    for (var index = 0; index < pages.length; index++) {
      final number = index + 1;
      overrides.write(
        '<Override PartName="/xl/worksheets/sheet$number.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
      sheets.write(
        '<sheet name="Page $number" sheetId="$number" r:id="rId$number"/>',
      );
      relationships.write(
        '<Relationship Id="rId$number" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$number.xml"/>',
      );
      archive.addFile(
        _file('xl/worksheets/sheet$number.xml', _worksheet(pages[index])),
      );
    }
    archive
      ..addFile(
        _file(
          '[Content_Types].xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
              '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
              '$overrides</Types>',
        ),
      )
      ..addFile(
        _file(
          '_rels/.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        _file(
          'xl/workbook.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets>$sheets</sheets></workbook>',
        ),
      )
      ..addFile(
        _file(
          'xl/_rels/workbook.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '$relationships'
              '<Relationship Id="rId${pages.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        _file(
          'xl/styles.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
              '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
              '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
              '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
              '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
              '</styleSheet>',
        ),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _worksheet(String text) {
    final rows = text.split(RegExp(r'\n+'));
    final xml = StringBuffer();
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final line = rows[rowIndex].trim();
      if (line.isEmpty) continue;
      var cells = line.split(RegExp(r'\t| {2,}'));
      if (cells.length == 1) cells = [line];
      xml.write('<row r="${rowIndex + 1}">');
      for (var column = 0; column < cells.length; column++) {
        final reference = '${_columnName(column)}${rowIndex + 1}';
        xml.write(
          '<c r="$reference" t="inlineStr"><is><t xml:space="preserve">${_xml(cells[column].trim())}</t></is></c>',
        );
      }
      xml.write('</row>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>$xml</sheetData></worksheet>';
  }

  static String _columnName(int index) {
    var value = index + 1;
    var result = '';
    while (value > 0) {
      value--;
      result = String.fromCharCode(65 + value % 26) + result;
      value ~/= 26;
    }
    return result;
  }

  static ArchiveFile _file(String name, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(name, bytes.length, bytes);
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
