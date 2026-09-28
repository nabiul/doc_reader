import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:xml/xml.dart';

class NativeOfficeDocumentView extends StatefulWidget {
  const NativeOfficeDocumentView({
    super.key,
    required this.path,
    required this.name,
    required this.extension,
    required this.night,
  });

  final String path;
  final String name;
  final String extension;
  final bool night;

  @override
  State<NativeOfficeDocumentView> createState() =>
      _NativeOfficeDocumentViewState();
}

class _NativeOfficeDocumentViewState extends State<NativeOfficeDocumentView> {
  late Future<OfficeFile> document;

  @override
  void initState() {
    super.initState();
    document = OfficeParser.parse(widget.path, widget.extension);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OfficeFile>(
    future: document,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error(snapshot.error!);
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return switch (snapshot.data!) {
        WordFile value => WordDocumentView(file: value, night: widget.night),
        WorkbookFile value => SpreadsheetView(file: value, night: widget.night),
        PresentationFile value => PresentationView(
          file: value,
          night: widget.night,
        ),
        TextOfficeFile value => _text(value.text),
      };
    },
  );

  Widget _text(String value) => SingleChildScrollView(
    padding: const EdgeInsets.all(18),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      color: widget.night ? const Color(0xff292a31) : Colors.white,
      child: SelectableText(value),
    ),
  );

  Widget _error(Object error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 52),
          const SizedBox(height: 14),
          const Text(
            'This document cannot be rendered locally.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => OpenFilex.open(widget.path),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open with another app'),
          ),
        ],
      ),
    ),
  );
}

sealed class OfficeFile {}

extension OfficeFilePlainText on OfficeFile {
  String get plainText => switch (this) {
    TextOfficeFile file => file.text,
    WordFile file =>
      file.blocks
          .map((block) {
            return switch (block) {
              WordParagraph paragraph =>
                paragraph.runs.map((run) => run.text).join(),
              WordTable table =>
                table.rows
                    .map(
                      (row) => row
                          .map(
                            (cell) => cell
                                .map((p) => p.runs.map((r) => r.text).join())
                                .join(' '),
                          )
                          .join('\t'),
                    )
                    .join('\n'),
            };
          })
          .join('\n'),
    WorkbookFile file =>
      file.sheets
          .map(
            (sheet) =>
                '${sheet.name}\n${sheet.rows.map((row) => row.map((cell) => cell.value).join('\t')).join('\n')}',
          )
          .join('\n\n'),
    PresentationFile file =>
      file.slides.indexed
          .map(
            (slide) =>
                'Slide ${slide.$1 + 1}\n${slide.$2.shapes.map((shape) => shape.text).where((text) => text.isNotEmpty).join('\n')}',
          )
          .join('\n\n'),
  };
}

class TextOfficeFile extends OfficeFile {
  TextOfficeFile(this.text);
  final String text;
}

sealed class WordBlock {}

class WordFile extends OfficeFile {
  WordFile(this.blocks);
  final List<WordBlock> blocks;
}

class WordParagraph extends WordBlock {
  WordParagraph(this.runs, {this.alignment, this.headingLevel});
  final List<WordRun> runs;
  final TextAlign? alignment;
  final int? headingLevel;
}

class WordTable extends WordBlock {
  WordTable(this.rows);
  final List<List<List<WordParagraph>>> rows;
}

class WordRun {
  WordRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSize,
    this.color,
    this.highlight,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final double? fontSize;
  final Color? color;
  final Color? highlight;
}

class WorkbookFile extends OfficeFile {
  WorkbookFile(this.sheets);
  final List<OfficeSheet> sheets;
}

class OfficeSheet {
  OfficeSheet(this.name, this.rows, this.columnWidths);
  final String name;
  final List<List<OfficeCell>> rows;
  final Map<int, double> columnWidths;
}

class OfficeCell {
  OfficeCell(this.value, {this.style = const CellStyle()});
  final String value;
  final CellStyle style;
}

class CellStyle {
  const CellStyle({
    this.bold = false,
    this.italic = false,
    this.fontSize,
    this.textColor,
    this.fillColor,
    this.alignment,
  });
  final bool bold;
  final bool italic;
  final double? fontSize;
  final Color? textColor;
  final Color? fillColor;
  final TextAlign? alignment;
}

class PresentationFile extends OfficeFile {
  PresentationFile(this.slides, this.width, this.height);
  final List<OfficeSlide> slides;
  final double width;
  final double height;
}

class OfficeSlide {
  OfficeSlide(this.shapes, {this.background});
  final List<SlideShape> shapes;
  final Color? background;
}

class SlideShape {
  SlideShape({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.text = '',
    this.fontSize,
    this.bold = false,
    this.color,
    this.fill,
    this.image,
    this.alignment,
  });
  final double left;
  final double top;
  final double width;
  final double height;
  final String text;
  final double? fontSize;
  final bool bold;
  final Color? color;
  final Color? fill;
  final Uint8List? image;
  final TextAlign? alignment;
}

class OfficeParser {
  static Future<OfficeFile> parse(String path, String extension) async {
    if (extension == 'rtf') {
      return TextOfficeFile(_rtf(await File(path).readAsString()));
    }
    if (!const {'docx', 'xlsx', 'pptx'}.contains(extension)) {
      throw const FormatException(
        'Legacy DOC, XLS and PPT are binary formats; save as DOCX, XLSX or PPTX first.',
      );
    }
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return switch (extension) {
      'docx' => _word(archive),
      'xlsx' => _workbook(archive),
      'pptx' => _presentation(archive),
      _ => throw const FormatException('Unsupported Office format'),
    };
  }

  static WordFile _word(Archive archive) {
    final xml = _xml(archive, 'word/document.xml');
    if (xml == null) throw const FormatException('Invalid DOCX document');
    final body = xml.descendants.whereType<XmlElement>().firstWhere(
      (node) => node.name.local == 'body',
    );
    final blocks = <WordBlock>[];
    for (final child in body.children.whereType<XmlElement>()) {
      if (child.name.local == 'p') blocks.add(_wordParagraph(child));
      if (child.name.local == 'tbl') {
        final rows = child.children
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'tr')
            .map(
              (row) => row.children
                  .whereType<XmlElement>()
                  .where((node) => node.name.local == 'tc')
                  .map(
                    (cell) => cell.children
                        .whereType<XmlElement>()
                        .where((node) => node.name.local == 'p')
                        .map(_wordParagraph)
                        .toList(),
                  )
                  .toList(),
            )
            .toList();
        blocks.add(WordTable(rows));
      }
    }
    return WordFile(blocks);
  }

  static WordParagraph _wordParagraph(XmlElement paragraph) {
    final properties = paragraph.children
        .whereType<XmlElement>()
        .firstWhereOrNull((node) => node.name.local == 'pPr');
    final alignmentValue = properties?._descendant('jc')?._attribute('val');
    final style = properties?._descendant('pStyle')?._attribute('val') ?? '';
    final heading = RegExp(r'(\d+)').firstMatch(style)?.group(1);
    final runs = paragraph.children
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'r')
        .map((run) {
          final props = run.children.whereType<XmlElement>().firstWhereOrNull(
            (node) => node.name.local == 'rPr',
          );
          final text = run.descendants.whereType<XmlElement>().map((node) {
            return switch (node.name.local) {
              't' => node.innerText,
              'tab' => '\t',
              'br' => '\n',
              _ => '',
            };
          }).join();
          final size = double.tryParse(
            props?._descendant('sz')?._attribute('val') ?? '',
          );
          return WordRun(
            text,
            bold: props?._descendant('b') != null,
            italic: props?._descendant('i') != null,
            underline: props?._descendant('u') != null,
            strike: props?._descendant('strike') != null,
            fontSize: size == null ? null : size / 2,
            color: _color(props?._descendant('color')?._attribute('val')),
            highlight: _namedColor(
              props?._descendant('highlight')?._attribute('val'),
            ),
          );
        })
        .where((run) => run.text.isNotEmpty)
        .toList();
    return WordParagraph(
      runs,
      alignment: _alignment(alignmentValue),
      headingLevel: heading == null ? null : int.tryParse(heading),
    );
  }

  static WorkbookFile _workbook(Archive archive) {
    final sharedXml = _xml(archive, 'xl/sharedStrings.xml');
    final shared = sharedXml == null
        ? <String>[]
        : sharedXml.descendants
              .whereType<XmlElement>()
              .where((node) => node.name.local == 'si')
              .map((node) => node._texts())
              .toList();
    final styles = _cellStyles(archive);
    final workbook = _xml(archive, 'xl/workbook.xml');
    final names = workbook?.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'sheet')
        .map((node) => node._attribute('name') ?? 'Sheet')
        .toList();
    final sheetFiles = archive.files.where((file) {
      return RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name);
    }).toList()..sort((a, b) => _number(a.name).compareTo(_number(b.name)));
    final sheets = <OfficeSheet>[];
    for (final indexed in sheetFiles.indexed) {
      final xml = XmlDocument.parse(
        utf8.decode(indexed.$2.content as List<int>),
      );
      final widths = <int, double>{};
      for (final column in xml.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'col',
      )) {
        final min = int.tryParse(column._attribute('min') ?? '') ?? 1;
        final max = int.tryParse(column._attribute('max') ?? '') ?? min;
        final width = double.tryParse(column._attribute('width') ?? '') ?? 12;
        for (var index = min - 1; index < max; index++) {
          widths[index] = (width * 8).clamp(64, 260);
        }
      }
      final parsedRows = <List<OfficeCell>>[];
      var maxColumn = 0;
      final sparseRows = <Map<int, OfficeCell>>[];
      for (final row in xml.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'row',
      )) {
        final cells = <int, OfficeCell>{};
        for (final cell in row.children.whereType<XmlElement>().where(
          (node) => node.name.local == 'c',
        )) {
          final reference = cell._attribute('r') ?? 'A1';
          final column = _columnIndex(reference);
          maxColumn = column > maxColumn ? column : maxColumn;
          final type = cell._attribute('t');
          final raw = cell._descendant('v')?.innerText ?? cell._texts();
          var value = raw;
          if (type == 's') {
            final index = int.tryParse(raw);
            if (index != null && index < shared.length) value = shared[index];
          } else if (type == 'b') {
            value = raw == '1' ? 'TRUE' : 'FALSE';
          }
          final styleIndex = int.tryParse(cell._attribute('s') ?? '') ?? 0;
          cells[column] = OfficeCell(
            value,
            style: styleIndex < styles.length
                ? styles[styleIndex]
                : const CellStyle(),
          );
        }
        sparseRows.add(cells);
      }
      for (final row in sparseRows) {
        parsedRows.add(
          List.generate(
            maxColumn + 1,
            (column) => row[column] ?? OfficeCell(''),
          ),
        );
      }
      sheets.add(
        OfficeSheet(
          names != null && indexed.$1 < names.length
              ? names[indexed.$1]
              : 'Sheet ${indexed.$1 + 1}',
          parsedRows,
          widths,
        ),
      );
    }
    return WorkbookFile(sheets);
  }

  static List<CellStyle> _cellStyles(Archive archive) {
    final xml = _xml(archive, 'xl/styles.xml');
    if (xml == null) return const [CellStyle()];
    final fontsParent = xml.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((node) => node.name.local == 'fonts');
    final fillsParent = xml.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((node) => node.name.local == 'fills');
    final fonts = fontsParent?.children.whereType<XmlElement>().toList() ?? [];
    final fills = fillsParent?.children.whereType<XmlElement>().toList() ?? [];
    final xfsParent = xml.descendants.whereType<XmlElement>().firstWhereOrNull(
      (node) => node.name.local == 'cellXfs',
    );
    return xfsParent?.children.whereType<XmlElement>().map((xf) {
          final fontId = int.tryParse(xf._attribute('fontId') ?? '') ?? 0;
          final fillId = int.tryParse(xf._attribute('fillId') ?? '') ?? 0;
          final font = fontId < fonts.length ? fonts[fontId] : null;
          final fill = fillId < fills.length ? fills[fillId] : null;
          final alignment = xf
              ._descendant('alignment')
              ?._attribute('horizontal');
          return CellStyle(
            bold: font?._descendant('b') != null,
            italic: font?._descendant('i') != null,
            fontSize: double.tryParse(
              font?._descendant('sz')?._attribute('val') ?? '',
            ),
            textColor: _color(font?._descendant('color')?._attribute('rgb')),
            fillColor: _color(fill?._descendant('fgColor')?._attribute('rgb')),
            alignment: _alignment(alignment),
          );
        }).toList() ??
        const [CellStyle()];
  }

  static PresentationFile _presentation(Archive archive) {
    final presentation = _xml(archive, 'ppt/presentation.xml');
    final size = presentation?.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((node) => node.name.local == 'sldSz');
    final pageWidth = double.tryParse(size?._attribute('cx') ?? '') ?? 9144000;
    final pageHeight = double.tryParse(size?._attribute('cy') ?? '') ?? 6858000;
    final files = archive.files.where((file) {
      return RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name);
    }).toList()..sort((a, b) => _number(a.name).compareTo(_number(b.name)));
    final slides = <OfficeSlide>[];
    for (final slideFile in files) {
      final slideNumber = _number(slideFile.name);
      final xml = XmlDocument.parse(
        utf8.decode(slideFile.content as List<int>),
      );
      final relationships = _relationships(
        archive,
        'ppt/slides/_rels/slide$slideNumber.xml.rels',
      );
      final shapes = <SlideShape>[];
      for (final shape in xml.descendants.whereType<XmlElement>().where(
        (node) => const {'sp', 'pic', 'graphicFrame'}.contains(node.name.local),
      )) {
        final transform = shape._descendant('xfrm');
        final offset = transform?._descendant('off');
        final extent = transform?._descendant('ext');
        if (offset == null || extent == null) continue;
        final left = double.tryParse(offset._attribute('x') ?? '') ?? 0;
        final top = double.tryParse(offset._attribute('y') ?? '') ?? 0;
        final width = double.tryParse(extent._attribute('cx') ?? '') ?? 1;
        final height = double.tryParse(extent._attribute('cy') ?? '') ?? 1;
        final runProperties =
            shape._descendant('rPr') ?? shape._descendant('defRPr');
        final fontSize = double.tryParse(runProperties?._attribute('sz') ?? '');
        final imageId = shape._descendant('blip')?._attribute('embed');
        Uint8List? image;
        if (imageId != null && relationships[imageId] != null) {
          final target = relationships[imageId]!.replaceFirst('../', 'ppt/');
          final media = archive.findFile(target);
          if (media != null) {
            image = Uint8List.fromList(media.content as List<int>);
          }
        }
        shapes.add(
          SlideShape(
            left: left / pageWidth,
            top: top / pageHeight,
            width: width / pageWidth,
            height: height / pageHeight,
            text: shape._texts(separator: '\n'),
            fontSize: fontSize == null ? null : fontSize / 100,
            bold: runProperties?._attribute('b') == '1',
            color: _color(
              runProperties?._descendant('srgbClr')?._attribute('val'),
            ),
            fill: _color(
              shape
                  ._descendant('solidFill')
                  ?._descendant('srgbClr')
                  ?._attribute('val'),
            ),
            image: image,
            alignment: _alignment(shape._descendant('pPr')?._attribute('algn')),
          ),
        );
      }
      slides.add(OfficeSlide(shapes));
    }
    return PresentationFile(slides, pageWidth, pageHeight);
  }

  static Map<String, String> _relationships(Archive archive, String path) {
    final xml = _xml(archive, path);
    if (xml == null) return {};
    return {
      for (final node in xml.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'Relationship',
      ))
        if (node._attribute('Id') != null && node._attribute('Target') != null)
          node._attribute('Id')!: node._attribute('Target')!,
    };
  }

  static XmlDocument? _xml(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) return null;
    return XmlDocument.parse(utf8.decode(file.content as List<int>));
  }

  static int _number(String value) =>
      int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '') ?? 0;

  static int _columnIndex(String reference) {
    final letters = RegExp(r'^[A-Z]+').firstMatch(reference)?.group(0) ?? 'A';
    var result = 0;
    for (final value in letters.codeUnits) {
      result = result * 26 + value - 64;
    }
    return result - 1;
  }

  static String _rtf(String value) => value
      .replaceAll(RegExp(r'\\par[d]?'), '\n')
      .replaceAllMapped(
        RegExp(r"\\'([0-9a-fA-F]{2})"),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      )
      .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
      .replaceAll(RegExp(r'[{}]'), '')
      .trim();
}

class WordDocumentView extends StatelessWidget {
  const WordDocumentView({super.key, required this.file, required this.night});
  final WordFile file;
  final bool night;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
    children: [
      Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 794, minHeight: 900),
          padding: const EdgeInsets.fromLTRB(66, 72, 66, 72),
          decoration: BoxDecoration(
            color: night ? const Color(0xff292a31) : Colors.white,
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: file.blocks.map(_block).toList(),
          ),
        ),
      ),
    ],
  );

  Widget _block(WordBlock block) => switch (block) {
    WordParagraph paragraph => _paragraph(paragraph),
    WordTable table => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade500, width: .7),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: table.rows
            .map(
              (row) => TableRow(
                children: row
                    .map(
                      (cell) => Padding(
                        padding: const EdgeInsets.all(7),
                        child: Column(children: cell.map(_paragraph).toList()),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    ),
  };

  Widget _paragraph(WordParagraph paragraph) {
    final heading = paragraph.headingLevel;
    final defaultSize = heading == null
        ? 14.0
        : (28 - heading * 2).clamp(17, 26).toDouble();
    return Padding(
      padding: EdgeInsets.only(bottom: heading == null ? 8 : 13),
      child: SelectableText.rich(
        TextSpan(
          children: paragraph.runs.map((run) {
            return TextSpan(
              text: run.text,
              style: TextStyle(
                color: run.color ?? (night ? Colors.white70 : Colors.black87),
                backgroundColor: run.highlight,
                fontSize: run.fontSize ?? defaultSize,
                fontWeight: run.bold || heading != null
                    ? FontWeight.bold
                    : null,
                fontStyle: run.italic ? FontStyle.italic : null,
                decoration: TextDecoration.combine([
                  if (run.underline) TextDecoration.underline,
                  if (run.strike) TextDecoration.lineThrough,
                ]),
                height: 1.35,
              ),
            );
          }).toList(),
        ),
        textAlign: paragraph.alignment ?? TextAlign.left,
      ),
    );
  }
}

class SpreadsheetView extends StatefulWidget {
  const SpreadsheetView({super.key, required this.file, required this.night});
  final WorkbookFile file;
  final bool night;

  @override
  State<SpreadsheetView> createState() => _SpreadsheetViewState();
}

class _SpreadsheetViewState extends State<SpreadsheetView> {
  var sheetIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.file.sheets.isEmpty) {
      return const Center(child: Text('Empty workbook'));
    }
    final sheet = widget.file.sheets[sheetIndex];
    final columns = sheet.rows.fold<int>(
      0,
      (value, row) => row.length > value ? row.length : value,
    );
    return Column(
      children: [
        Material(
          color: widget.night ? const Color(0xff202127) : Colors.white,
          child: SizedBox(
            height: 46,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.file.sheets.length,
              itemBuilder: (context, index) => TextButton(
                onPressed: () => setState(() => sheetIndex = index),
                child: Text(
                  widget.file.sheets[index].name,
                  style: TextStyle(
                    fontWeight: index == sheetIndex ? FontWeight.bold : null,
                    decoration: index == sheetIndex
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            minScale: .6,
            maxScale: 3,
            alignment: Alignment.topLeft,
            child: Container(
              color: widget.night ? const Color(0xff292a31) : Colors.white,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(110),
                columnWidths: {
                  for (var i = 0; i < columns; i++)
                    i: FixedColumnWidth(sheet.columnWidths[i] ?? 110),
                },
                border: TableBorder.all(color: Colors.grey.shade400, width: .5),
                children: sheet.rows.map((row) {
                  return TableRow(
                    children: List.generate(columns, (index) {
                      final cell = index < row.length
                          ? row[index]
                          : OfficeCell('');
                      return Container(
                        constraints: const BoxConstraints(minHeight: 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 6,
                        ),
                        color: cell.style.fillColor,
                        alignment: switch (cell.style.alignment) {
                          TextAlign.center => Alignment.center,
                          TextAlign.right => Alignment.centerRight,
                          _ => Alignment.centerLeft,
                        },
                        child: Text(
                          cell.value,
                          textAlign: cell.style.alignment,
                          style: TextStyle(
                            color:
                                cell.style.textColor ??
                                (widget.night
                                    ? Colors.white70
                                    : Colors.black87),
                            fontSize: cell.style.fontSize ?? 13,
                            fontWeight: cell.style.bold
                                ? FontWeight.bold
                                : null,
                            fontStyle: cell.style.italic
                                ? FontStyle.italic
                                : null,
                          ),
                        ),
                      );
                    }),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PresentationView extends StatelessWidget {
  const PresentationView({super.key, required this.file, required this.night});
  final PresentationFile file;
  final bool night;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(18),
    itemCount: file.slides.length,
    separatorBuilder: (_, _) => const SizedBox(height: 18),
    itemBuilder: (context, index) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slide ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        AspectRatio(
          aspectRatio: file.width / file.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slide = file.slides[index];
              return Container(
                color: slide.background ?? Colors.white,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: slide.shapes.map((shape) {
                    return Positioned(
                      left: shape.left * constraints.maxWidth,
                      top: shape.top * constraints.maxHeight,
                      width: shape.width * constraints.maxWidth,
                      height: shape.height * constraints.maxHeight,
                      child: Container(
                        color: shape.fill,
                        padding: const EdgeInsets.all(3),
                        child: shape.image != null
                            ? Image.memory(shape.image!, fit: BoxFit.contain)
                            : Text(
                                shape.text,
                                textAlign: shape.alignment,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: shape.color ?? Colors.black87,
                                  fontSize:
                                      ((shape.fontSize ?? 18) *
                                              constraints.maxWidth /
                                              960)
                                          .clamp(7, 42),
                                  fontWeight: shape.bold
                                      ? FontWeight.bold
                                      : null,
                                ),
                              ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

extension _XmlHelpers on XmlElement {
  XmlElement? _descendant(String localName) => descendants
      .whereType<XmlElement>()
      .firstWhereOrNull((node) => node.name.local == localName);

  String? _attribute(String localName) {
    for (final attribute in attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  String _texts({String separator = ''}) => descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 't')
      .map((node) => node.innerText)
      .where((text) => text.isNotEmpty)
      .join(separator);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}

TextAlign? _alignment(String? value) => switch (value) {
  'center' || 'ctr' => TextAlign.center,
  'right' || 'r' || 'end' => TextAlign.right,
  'both' || 'justify' || 'just' => TextAlign.justify,
  'left' || 'l' || 'start' => TextAlign.left,
  _ => null,
};

Color? _color(String? value) {
  if (value == null || value == 'auto') return null;
  final cleaned = value.replaceAll('#', '');
  final rgb = cleaned.length == 8 ? cleaned.substring(2) : cleaned;
  final parsed = int.tryParse(rgb, radix: 16);
  return parsed == null ? null : Color(0xff000000 | parsed);
}

Color? _namedColor(String? value) => switch (value) {
  'yellow' => Colors.yellow,
  'green' => Colors.greenAccent,
  'cyan' => Colors.cyanAccent,
  'magenta' => Colors.pinkAccent,
  'blue' => Colors.lightBlueAccent,
  'red' => Colors.redAccent,
  'darkYellow' => Colors.amber,
  'darkGreen' => Colors.green,
  'darkBlue' => Colors.blue,
  _ => null,
};
