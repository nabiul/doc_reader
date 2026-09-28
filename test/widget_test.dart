import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:doc_reader/main.dart';
import 'package:doc_reader/ai_document.dart';
import 'package:doc_reader/office_renderer.dart';
import 'package:doc_reader/pdf_office_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('document metadata survives serialization', () {
    final document = DocumentItem(
      'sample.pdf',
      DocType.pdf,
      '1 MB',
      4,
      DateTime(2026, 9, 28),
      favorite: true,
      path: '/tmp/sample.pdf',
    );
    final restored = DocumentItem.fromJson(document.toJson());
    expect(restored.name, document.name);
    expect(restored.favorite, isTrue);
    expect(restored.path, document.path);
  });

  test('Bengali searchable PDF font is bundled', () async {
    final font = await rootBundle.load('assets/fonts/NotoSansBengali.ttf');
    expect(font.lengthInBytes, greaterThan(100000));
  });

  test('ink annotation survives serialization', () {
    final stroke = InkStroke(
      page: 2,
      points: const [Offset(.1, .2), Offset(.4, .8)],
      color: 0xFFE53935,
      width: 4,
    );
    final restored = InkStroke.fromJson(stroke.toJson());
    expect(restored.page, 2);
    expect(restored.points, stroke.points);
    expect(restored.color, stroke.color);
  });

  test('native Office parser reads DOCX, XLSX and PPTX packages', () async {
    final directory = await Directory.systemTemp.createTemp('office-parser-');
    addTearDown(() => directory.delete(recursive: true));

    Future<String> package(String name, Map<String, String> files) async {
      final archive = Archive();
      for (final entry in files.entries) {
        final bytes = utf8.encode(entry.value);
        archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
      }
      final path = '${directory.path}/$name';
      await File(path).writeAsBytes(ZipEncoder().encode(archive));
      return path;
    }

    final docx = await package('sample.docx', {
      'word/document.xml':
          '<w:document xmlns:w="w"><w:body><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Hello Word</w:t></w:r></w:p></w:body></w:document>',
    });
    final word = await OfficeParser.parse(docx, 'docx') as WordFile;
    expect((word.blocks.first as WordParagraph).runs.first.text, 'Hello Word');
    expect((word.blocks.first as WordParagraph).runs.first.bold, isTrue);

    final xlsx = await package('sample.xlsx', {
      'xl/workbook.xml':
          '<workbook><sheets><sheet name="Budget"/></sheets></workbook>',
      'xl/sharedStrings.xml': '<sst><si><t>Total</t></si></sst>',
      'xl/worksheets/sheet1.xml':
          '<worksheet><sheetData><row><c r="A1" t="s"><v>0</v></c></row></sheetData></worksheet>',
    });
    final workbook = await OfficeParser.parse(xlsx, 'xlsx') as WorkbookFile;
    expect(workbook.sheets.first.name, 'Budget');
    expect(workbook.sheets.first.rows.first.first.value, 'Total');

    final pptx = await package('sample.pptx', {
      'ppt/presentation.xml':
          '<p:presentation xmlns:p="p"><p:sldSz cx="1000" cy="500"/></p:presentation>',
      'ppt/slides/slide1.xml':
          '<p:sld xmlns:p="p" xmlns:a="a"><p:sp><a:xfrm><a:off x="10" y="20"/><a:ext cx="400" cy="100"/></a:xfrm><a:t>Slide title</a:t></p:sp></p:sld>',
    });
    final presentation =
        await OfficeParser.parse(pptx, 'pptx') as PresentationFile;
    expect(presentation.slides.first.shapes.first.text, 'Slide title');
  });

  testWidgets('home shows document library', (tester) async {
    await tester.pumpWidget(const DocReaderApp());
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('No documents found'), findsOneWidget);
  });

  testWidgets('reader preview works without demo library data', (tester) async {
    final document = DocumentItem(
      'Preview.pdf',
      DocType.pdf,
      '1 MB',
      3,
      DateTime(2026, 9, 28),
    );
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(document: document)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('Compress PDF tool is wired to its action', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolsView(
            onImagesToPdf: () async {},
            onMergePdfs: () async {},
            onSplitPdf: () async {},
            onCompressPdf: () async => called = true,
            onScanDocument: () async {},
            onAiAssistant: () async {},
            onPdfToWord: () async {},
            onPdfToExcel: () async {},
          ),
        ),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress PDF'));
    await tester.pump();
    expect(called, isTrue);
  });

  test('offline document intelligence extracts facts and answers questions', () {
    const text =
        'The payment amount is USD 12,500. Payment must be completed by 12/10/2026. '
        'The supplier shall deliver all products before the deadline. '
        'Late delivery may result in a penalty.';
    final insights = OfflineDocumentIntelligence.analyze(text);
    expect(insights.amounts, contains('USD 12,500'));
    expect(insights.dates, contains('12/10/2026'));
    expect(insights.actionItems, isNotEmpty);
    expect(
      OfflineDocumentIntelligence.answer(insights, 'payment amount'),
      contains('USD 12,500'),
    );
  });

  test('PDF text exports create readable Word and Excel files', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-office-');
    addTearDown(() => directory.delete(recursive: true));
    const pages = [
      'Invoice Number  1001\nCustomer  Example Ltd\nTotal  USD 500',
      'Second page notes',
    ];

    final wordPath = '${directory.path}/converted.docx';
    await File(wordPath).writeAsBytes(PdfOfficeExporter.createWord(pages));
    final word = await OfficeParser.parse(wordPath, 'docx') as WordFile;
    expect(word.plainText, contains('Invoice Number'));
    expect(word.plainText, contains('Second page notes'));

    final excelPath = '${directory.path}/converted.xlsx';
    await File(excelPath).writeAsBytes(PdfOfficeExporter.createExcel(pages));
    final workbook =
        await OfficeParser.parse(excelPath, 'xlsx') as WorkbookFile;
    expect(workbook.sheets, hasLength(2));
    expect(workbook.sheets.first.rows.first.first.value, 'Invoice Number');
    expect(workbook.sheets.first.rows.first[1].value, '1001');
  });
}
