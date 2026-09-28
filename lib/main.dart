import 'dart:convert';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'ai_document.dart';
import 'office_renderer.dart';
import 'pdf_office_exporter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const DocReaderApp());
}

class DocReaderApp extends StatelessWidget {
  const DocReaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'DocReader',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B5FEF)),
      scaffoldBackgroundColor: const Color(0xFFF7F7FC),
      cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B5FEF),
        brightness: Brightness.dark,
      ),
    ),
    home: const HomeScreen(),
  );
}

enum DocType { pdf, docx, xlsx, pptx, image, text }

class DocumentItem {
  const DocumentItem(
    this.name,
    this.type,
    this.size,
    this.pages,
    this.modified, {
    this.favorite = false,
    this.path,
    this.ocrText = '',
  });
  final String name;
  final DocType type;
  final String size;
  final int pages;
  final DateTime modified;
  final bool favorite;
  final String? path;
  final String ocrText;
  DocumentItem star(bool value) => DocumentItem(
    name,
    type,
    size,
    pages,
    modified,
    favorite: value,
    path: path,
    ocrText: ocrText,
  );

  DocumentItem renamed(String newName, String? newPath) => DocumentItem(
    newName,
    type,
    size,
    pages,
    modified,
    favorite: favorite,
    path: newPath ?? path,
    ocrText: ocrText,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.name,
    'size': size,
    'pages': pages,
    'modified': modified.toIso8601String(),
    'favorite': favorite,
    'path': path,
    'ocrText': ocrText,
  };

  factory DocumentItem.fromJson(Map<String, dynamic> json) => DocumentItem(
    json['name'] as String,
    DocType.values.byName(json['type'] as String),
    json['size'] as String,
    json['pages'] as int,
    DateTime.parse(json['modified'] as String),
    favorite: json['favorite'] as bool? ?? false,
    path: json['path'] as String?,
    ocrText: json['ocrText'] as String? ?? '',
  );
}

const brand = Color(0xFF5B5FEF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const incomingDocuments = MethodChannel(
    'doc_reader/incoming_document',
  );
  int tab = 0;
  bool grid = false;
  String query = '';
  String sort = 'Recent';
  DocType? filter;
  late List<DocumentItem> docs;

  @override
  void initState() {
    super.initState();
    docs = [];
    incomingDocuments.setMethodCallHandler((call) async {
      if (call.method == 'incomingDocument') {
        await importIncomingDocument(call.arguments);
      }
    });
    initializeLibrary();
  }

  @override
  void dispose() {
    incomingDocuments.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> initializeLibrary() async {
    await loadLibrary();
    try {
      final initial = await incomingDocuments.invokeMethod<Object?>(
        'getInitialDocument',
      );
      if (initial != null) await importIncomingDocument(initial);
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not provide the Android bridge.
    }
  }

  List<DocumentItem> get visible {
    final result = docs
        .where(
          (d) =>
              (d.name.toLowerCase().contains(query.toLowerCase()) ||
                  d.ocrText.toLowerCase().contains(query.toLowerCase())) &&
              (filter == null || d.type == filter) &&
              (tab != 2 || d.favorite),
        )
        .toList();
    if (sort == 'Name') {
      result.sort((a, b) => a.name.compareTo(b.name));
    }
    if (sort == 'Type') {
      result.sort((a, b) => a.type.name.compareTo(b.type.name));
    }
    if (sort == 'Recent') {
      result.sort((a, b) => b.modified.compareTo(a.modified));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: tab == 3
          ? ToolsView(
              onImagesToPdf: createPdfFromImages,
              onMergePdfs: mergePdfs,
              onSplitPdf: splitPdf,
              onCompressPdf: compressPdf,
              onScanDocument: scanDocument,
              onAiAssistant: openAiAssistant,
              onPdfToWord: () => convertPdfToOffice('docx'),
              onPdfToExcel: () => convertPdfToOffice('xlsx'),
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  sliver: SliverToBoxAdapter(child: header()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  sliver: SliverToBoxAdapter(child: searchBox()),
                ),
                if (tab == 0) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    sliver: SliverToBoxAdapter(child: quickActions()),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 2),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Recent documents',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => tab = 1),
                            child: const Text('See all'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                    sliver: SliverToBoxAdapter(child: filters()),
                  ),
                documentList(),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
    ),
    floatingActionButton: tab == 3
        ? null
        : FloatingActionButton.extended(
            onPressed: pickDocuments,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add document'),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() {
        tab = value;
        filter = null;
        query = '';
      }),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'Files',
        ),
        NavigationDestination(
          icon: Icon(Icons.star_outline_rounded),
          selectedIcon: Icon(Icons.star_rounded),
          label: 'Starred',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: 'Tools',
        ),
      ],
    ),
  );

  Widget header() {
    final title = ['Home', 'All documents', 'Favorites'][tab];
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
          child: Image.asset(
            'assets/branding/doc_reader_logo.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (tab == 0)
                Text(
                  'Your documents, all in one place',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => toast('No new notifications'),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }

  Widget searchBox() => TextField(
    onChanged: (value) => setState(() => query = value),
    decoration: InputDecoration(
      hintText: 'Search documents',
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: const Icon(Icons.tune_rounded),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget quickActions() {
    final items = [
      ('Scan', Icons.document_scanner_outlined, const Color(0xFFEFF0FF), brand),
      (
        'Image to PDF',
        Icons.image_outlined,
        const Color(0xFFFFF1E8),
        const Color(0xFFF07A32),
      ),
      (
        'Browse files',
        Icons.folder_open_outlined,
        const Color(0xFFE8F8F1),
        const Color(0xFF189B69),
      ),
      (
        'AI assistant',
        Icons.auto_awesome_outlined,
        const Color(0xFFF7EBFF),
        const Color(0xFF9A48C7),
      ),
    ];
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: InkWell(
                onTap: switch (item.$1) {
                  'Browse files' => pickDocuments,
                  'Scan' => scanDocument,
                  'Image to PDF' => createPdfFromImages,
                  'AI assistant' => openAiAssistant,
                  _ => () => toast('${item.$1} is not available yet'),
                },
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: item.$3,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(item.$2, color: item.$4, size: 27),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.$1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget filters() => Column(
    children: [
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            chip('All', null),
            chip('PDF', DocType.pdf),
            chip('Word', DocType.docx),
            chip('Sheets', DocType.xlsx),
            chip('Slides', DocType.pptx),
            chip('Images', DocType.image),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Text(
            '${visible.length} files',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: sort,
            onSelected: (v) => setState(() => sort = v),
            itemBuilder: (_) => [
              'Recent',
              'Name',
              'Type',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
            child: Row(
              children: [
                const Icon(Icons.swap_vert_rounded, size: 19),
                Text(sort),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => grid = !grid),
            icon: Icon(
              grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
          ),
        ],
      ),
    ],
  );

  Widget chip(String label, DocType? type) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: filter == type,
      onSelected: (_) => setState(() => filter = type),
    ),
  );

  Widget documentList() {
    final items = tab == 0 ? visible.take(4).toList() : visible;
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('No documents found')),
      );
    }
    if (grid && tab != 0) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: .88,
          ),
          itemBuilder: (_, i) => gridCard(items[i]),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => tile(items[i]),
      ),
    );
  }

  Widget tile(DocumentItem doc) => Card(
    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => open(doc),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            fileIcon(doc.type, 52),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    doc.pages == 0
                        ? '${doc.size}  •  PDF document'
                        : '${doc.size}  •  ${doc.pages} ${doc.pages == 1 ? 'page' : 'pages'}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => toggle(doc),
              icon: Icon(
                doc.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: doc.favorite ? Colors.amber.shade700 : null,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => handleAction(v, doc),
              itemBuilder: (_) => [
                'Rename',
                'Move',
                'Copy',
                'Share',
                'Delete',
              ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget gridCard(DocumentItem doc) => Card(
    margin: const EdgeInsets.all(6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => open(doc),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                fileIcon(doc.type, 50),
                IconButton(
                  onPressed: () => toggle(doc),
                  icon: Icon(
                    doc.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: doc.favorite ? Colors.amber.shade700 : null,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              doc.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              doc.pages == 0
                  ? '${doc.size} • PDF document'
                  : '${doc.size} • ${doc.pages} pages',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget fileIcon(DocType type, double size) {
    final value = switch (type) {
      DocType.pdf => (Icons.picture_as_pdf_rounded, const Color(0xFFE94F64)),
      DocType.docx => (Icons.description_rounded, const Color(0xFF3975D7)),
      DocType.xlsx => (Icons.table_chart_rounded, const Color(0xFF27A46B)),
      DocType.pptx => (Icons.slideshow_rounded, const Color(0xFFF07A32)),
      DocType.image => (Icons.image_rounded, const Color(0xFF9259D6)),
      DocType.text => (Icons.article_rounded, const Color(0xFF64748B)),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value.$2.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(value.$1, color: value.$2, size: size * .5),
    );
  }

  void toggle(DocumentItem doc) {
    final i = docs.indexWhere((d) => d.name == doc.name);
    setState(() => docs[i] = doc.star(!doc.favorite));
    saveLibrary();
  }

  void open(DocumentItem doc) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ReaderScreen(
        document: doc,
        onDocumentCreated: (created) {
          setState(() => docs.insert(0, created));
          saveLibrary();
        },
      ),
    ),
  );
  void toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );

  Future<void> pickDocuments() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Choose documents',
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'rtf',
          'jpg',
          'jpeg',
          'png',
          'webp',
        ],
      );
      final storage = await getApplicationDocumentsDirectory();
      final libraryFolder = Directory('${storage.path}/document_library');
      await libraryFolder.create(recursive: true);
      final imported = <DocumentItem>[];
      for (final file in files.where((file) => file.path != null)) {
        final extension = file.extension?.toLowerCase() ?? '';
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
        final storedPath =
            '${libraryFolder.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName';
        final storedFile = await File(file.path!).copy(storedPath);
        imported.add(
          DocumentItem(
            file.name,
            typeForExtension(extension),
            formatBytes(await storedFile.length()),
            extension == 'pdf' ? 0 : 1,
            DateTime.now(),
            path: storedPath,
          ),
        );
      }
      if (!mounted || imported.isEmpty) return;
      setState(() {
        docs.removeWhere(
          (doc) => imported.any((item) => item.path == doc.path),
        );
        docs.insertAll(0, imported);
        tab = 1;
      });
      await saveLibrary();
      toast(
        '${imported.length} document${imported.length == 1 ? '' : 's'} imported',
      );
    } catch (error) {
      if (mounted) toast('Could not import documents: $error');
    }
  }

  Future<void> importIncomingDocument(Object? arguments) async {
    if (arguments is! Map) return;
    final sourcePath = arguments['path']?.toString();
    var name = arguments['name']?.toString() ?? 'Opened document';
    final mimeType = arguments['mimeType']?.toString() ?? '';
    if (sourcePath == null || !await File(sourcePath).exists()) return;
    var extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (extension.isEmpty) {
      extension = switch (mimeType) {
        'application/pdf' => 'pdf',
        'application/msword' => 'doc',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
          'docx',
        'application/vnd.ms-excel' => 'xls',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
          'xlsx',
        'application/vnd.ms-powerpoint' => 'ppt',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
          'pptx',
        'text/csv' => 'csv',
        'application/rtf' || 'text/rtf' => 'rtf',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'txt',
      };
      name = '$name.$extension';
    }
    const supported = {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'csv',
      'rtf',
      'jpg',
      'jpeg',
      'png',
      'webp',
    };
    if (!supported.contains(extension)) {
      if (mounted) toast('Unsupported document type: .$extension');
      return;
    }
    try {
      final storage = await getApplicationDocumentsDirectory();
      final libraryFolder = Directory('${storage.path}/document_library');
      await libraryFolder.create(recursive: true);
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
      final path =
          '${libraryFolder.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName';
      final source = File(sourcePath);
      final stored = await source.copy(path);
      try {
        await source.delete();
      } on FileSystemException {
        // The source can be owned by another app or provider cache.
      }
      final document = DocumentItem(
        name,
        typeForExtension(extension),
        formatBytes(await stored.length()),
        extension == 'pdf' ? 0 : 1,
        DateTime.now(),
        path: stored.path,
      );
      if (!mounted) return;
      setState(() {
        docs.insert(0, document);
        tab = 1;
      });
      await saveLibrary();
      if (mounted) open(document);
    } catch (error) {
      if (mounted) toast('Could not open this document: $error');
    }
  }

  DocType typeForExtension(String extension) => switch (extension) {
    'pdf' => DocType.pdf,
    'doc' || 'docx' || 'rtf' => DocType.docx,
    'xls' || 'xlsx' || 'csv' => DocType.xlsx,
    'ppt' || 'pptx' => DocType.pptx,
    'jpg' || 'jpeg' || 'png' || 'webp' => DocType.image,
    _ => DocType.text,
  };

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> loadLibrary() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('document_library');
    if (raw == null) return;
    try {
      final entries = (jsonDecode(raw) as List)
          .map((item) => DocumentItem.fromJson(item as Map<String, dynamic>))
          .where((item) => item.path != null && File(item.path!).existsSync())
          .toList();
      if (!mounted) return;
      setState(() {
        docs.removeWhere((doc) => doc.path != null);
        docs.insertAll(0, entries);
      });
    } on FormatException {
      await preferences.remove('document_library');
    }
  }

  Future<void> saveLibrary() async {
    final preferences = await SharedPreferences.getInstance();
    final imported = docs
        .where((doc) => doc.path != null)
        .map((doc) => doc.toJson())
        .toList();
    await preferences.setString('document_library', jsonEncode(imported));
  }

  Future<void> handleAction(String action, DocumentItem document) async {
    if (document.path == null) {
      toast('$action: ${document.name}');
      return;
    }
    if (action == 'Share') {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(document.path!)], title: document.name),
      );
      return;
    }
    if (action == 'Rename') {
      await renameDocument(document);
      return;
    }
    if (action != 'Delete') {
      toast('$action: ${document.name}');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('${document.name} will be removed from this app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final file = File(document.path!);
    if (await file.exists()) await file.delete();
    if (!mounted) return;
    setState(() => docs.remove(document));
    await saveLibrary();
    if (mounted) toast('${document.name} deleted');
  }

  Future<void> renameDocument(DocumentItem document) async {
    final extension = document.name.contains('.')
        ? '.${document.name.split('.').last}'
        : '';
    final baseName = extension.isEmpty
        ? document.name
        : document.name.substring(0, document.name.length - extension.length);
    final controller = TextEditingController(text: baseName);
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(suffixText: extension),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || entered.isEmpty) return;
    final safeBase = entered.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
    final oldFile = File(document.path!);
    final separator = Platform.pathSeparator;
    final directory = document.path!.substring(
      0,
      document.path!.lastIndexOf(separator),
    );
    final newName = '$safeBase$extension';
    final newPath =
        '$directory/${DateTime.now().microsecondsSinceEpoch}_$newName';
    final renamedFile = await oldFile.rename(newPath);
    if (!mounted) return;
    final index = docs.indexOf(document);
    setState(() => docs[index] = document.renamed(newName, renamedFile.path));
    await saveLibrary();
    if (mounted) toast('Renamed to $newName');
  }

  Future<void> createPdfFromImages() async {
    try {
      final images = await FilePicker.pickFiles(
        dialogTitle: 'Select images in page order',
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      final selected = images.where((image) => image.path != null).toList();
      if (selected.isEmpty) return;
      await generatePdfFromImagePaths(
        selected.map((image) => image.path!).toList(),
        'Images',
      );
    } catch (error) {
      if (mounted) toast('Could not create PDF: $error');
    }
  }

  Future<void> scanDocument() async {
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: 50,
        scannerSource: ScannerSource.cameraAndGallery,
        androidScannerMode: AndroidScannerMode.full,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: .92,
          showFilterBar: true,
        ),
      );
      if (paths == null || paths.isEmpty || !mounted) return;
      final review = await Navigator.push<ScanReviewResult>(
        context,
        MaterialPageRoute(builder: (_) => ScanReviewScreen(paths: paths)),
      );
      if (review != null) await generateScannedPdf(review);
    } on CunningDocumentScannerException catch (error) {
      if (!mounted) return;
      final useFallback = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Smart scanner unavailable'),
          content: Text(
            '${error.message}\n\nUse the basic camera scanner instead?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use camera'),
            ),
          ],
        ),
      );
      if (useFallback == true) await scanDocumentBasic();
    } finally {
      try {
        await CunningDocumentScanner.cleanCache();
      } on CunningDocumentScannerException {
        // Cache cleanup failure should not discard an otherwise valid scan.
      }
    }
  }

  Future<void> scanDocumentBasic() async {
    final paths = <String>[];
    final picker = ImagePicker();
    try {
      while (true) {
        final capture = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
          preferredCameraDevice: CameraDevice.rear,
        );
        if (capture == null) break;
        paths.add(capture.path);
        if (!mounted) return;
        final next = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              '${paths.length} page${paths.length == 1 ? '' : 's'} captured',
            ),
            content: const Text(
              'Capture another page or create the scanned PDF now.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Discard'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'more'),
                child: const Text('Add page'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'finish'),
                child: const Text('Create PDF'),
              ),
            ],
          ),
        );
        if (next == 'cancel') return;
        if (next == 'finish') break;
      }
      if (paths.isEmpty) return;
      if (!mounted) return;
      final review = await Navigator.push<ScanReviewResult>(
        context,
        MaterialPageRoute(builder: (_) => ScanReviewScreen(paths: paths)),
      );
      if (review == null) return;
      await generateScannedPdf(review);
    } catch (error) {
      if (mounted) toast('Could not scan document: $error');
    } finally {
      for (final path in paths) {
        final temporary = File(path);
        if (await temporary.exists()) {
          try {
            await temporary.delete();
          } on FileSystemException {
            // The platform may own the captured file lifecycle.
          }
        }
      }
    }
  }

  Future<void> generatePdfFromImagePaths(
    List<String> paths,
    String prefix,
  ) async {
    if (mounted) toast('Creating PDF from ${paths.length} pages…');
    final output = pw.Document();
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      final memoryImage = pw.MemoryImage(bytes);
      output.addPage(
        pw.Page(
          build: (_) =>
              pw.Center(child: pw.Image(memoryImage, fit: pw.BoxFit.contain)),
        ),
      );
    }
    await saveGeneratedPdf(await output.save(), prefix, paths.length);
  }

  Future<void> generateScannedPdf(ScanReviewResult review) async {
    if (mounted) toast('Processing ${review.pages.length} scanned pages…');
    final output = pw.Document();
    final ocr = TextRecognizer(script: TextRecognitionScript.latin);
    final extractedText = <String>[];
    final bengaliFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansBengali.ttf'),
    );
    try {
      for (final page in review.pages) {
        final recognized = await ocr.processImage(
          InputImage.fromFilePath(page.path),
        );
        var pageText = recognized.text.trim();
        try {
          final bilingualText = await FlutterTesseractOcr.extractText(
            page.path,
            language: 'ben+eng',
            args: const {'psm': '3', 'preserve_interword_spaces': '1'},
          );
          if (bilingualText.trim().isNotEmpty) {
            pageText = bilingualText.trim();
          }
        } catch (_) {
          // Keep the faster ML Kit result if Tesseract is unavailable.
        }
        if (pageText.isNotEmpty) {
          extractedText.add(pageText);
        }
        final sourceBytes = await File(page.path).readAsBytes();
        var processed = img.decodeImage(sourceBytes);
        if (processed == null) continue;
        processed = img.bakeOrientation(processed);
        if (page.rotation != 0) {
          processed = img.copyRotate(processed, angle: page.rotation * 90);
        }
        if (review.filter == ScanFilter.grayscale) {
          processed = img.grayscale(processed);
        } else if (review.filter == ScanFilter.blackAndWhite) {
          processed = img.luminanceThreshold(
            img.grayscale(processed),
            threshold: .58,
          );
        }
        final memoryImage = pw.MemoryImage(
          img.encodeJpg(processed, quality: 90),
        );
        output.addPage(
          pw.Page(
            build: (_) => pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Image(memoryImage, fit: pw.BoxFit.contain),
                  ),
                ),
                if (pageText.isNotEmpty)
                  pw.Positioned.fill(
                    child: pw.Opacity(
                      opacity: 0,
                      child: pw.Text(
                        pageText,
                        style: pw.TextStyle(font: bengaliFont, fontSize: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    } finally {
      await ocr.close();
    }
    await saveGeneratedPdf(
      await output.save(),
      'Scan',
      review.pages.length,
      ocrText: extractedText.join('\n\n'),
    );
  }

  Future<void> mergePdfs() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select PDFs in merge order',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final paths = picked
        .where((file) => file.path != null)
        .map((file) => file.path!)
        .toList();
    if (paths.length < 2) {
      if (paths.isNotEmpty) toast('Select at least two PDF files');
      return;
    }
    final sources = <PdfDocument>[];
    PdfDocument? output;
    try {
      toast('Merging ${paths.length} PDFs…');
      final pages = <PdfPage>[];
      for (final path in paths) {
        final source = await PdfDocument.openFile(path);
        sources.add(source);
        pages.addAll(source.pages);
      }
      output = await PdfDocument.createNew(sourceName: 'merged.pdf');
      output.pages = pages;
      final bytes = await output.encodePdf();
      await saveGeneratedPdf(bytes, 'Merged document', pages.length);
    } catch (error) {
      if (mounted) toast('Could not merge PDFs: $error');
    } finally {
      await output?.dispose();
      for (final source in sources) {
        await source.dispose();
      }
    }
  }

  Future<void> splitPdf() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Select a PDF to extract pages',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked?.path == null) return;
    PdfDocument? source;
    PdfDocument? output;
    try {
      source = await PdfDocument.openFile(picked!.path!);
      final range = await askPageRange(source.pages.length);
      if (range == null) return;
      output = await PdfDocument.createNew(sourceName: 'extracted.pdf');
      output.pages = source.pages.sublist(range.$1 - 1, range.$2).toList();
      final bytes = await output.encodePdf();
      await saveGeneratedPdf(
        bytes,
        'Extracted pages ${range.$1}-${range.$2}',
        range.$2 - range.$1 + 1,
      );
    } catch (error) {
      if (mounted) toast('Could not extract pages: $error');
    } finally {
      await output?.dispose();
      await source?.dispose();
    }
  }

  Future<void> compressPdf() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Select a PDF to compress',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked?.path == null || !mounted) return;
    final profile =
        await showDialog<({double scale, int quality, String name})>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Compression quality'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (
                  scale: 1.5,
                  quality: 82,
                  name: 'High quality',
                )),
                child: const ListTile(
                  leading: Icon(Icons.high_quality_rounded),
                  title: Text('High quality'),
                  subtitle: Text('Larger file • clearer pages'),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (
                  scale: 1.15,
                  quality: 68,
                  name: 'Balanced',
                )),
                child: const ListTile(
                  leading: Icon(Icons.balance_rounded),
                  title: Text('Balanced'),
                  subtitle: Text('Recommended for most documents'),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (
                  scale: .85,
                  quality: 48,
                  name: 'Smallest file',
                )),
                child: const ListTile(
                  leading: Icon(Icons.compress_rounded),
                  title: Text('Smallest file'),
                  subtitle: Text('Lower resolution • maximum reduction'),
                ),
              ),
            ],
          ),
        );
    if (profile == null) return;

    PdfDocument? source;
    try {
      final sourceFile = File(picked!.path!);
      final originalBytes = await sourceFile.length();
      toast('Compressing PDF with ${profile.name.toLowerCase()}…');
      source = await PdfDocument.openFile(sourceFile.path);
      final output = pw.Document(compress: true);
      var renderedPages = 0;
      for (final page in source.pages) {
        final rendered = await page.render(
          fullWidth: page.width * profile.scale,
          fullHeight: page.height * profile.scale,
        );
        if (rendered == null) continue;
        try {
          final raster = img.Image.fromBytes(
            width: rendered.width,
            height: rendered.height,
            bytes: rendered.pixels.buffer,
            bytesOffset: rendered.pixels.offsetInBytes,
            numChannels: 4,
            order: img.ChannelOrder.bgra,
          );
          final compressedImage = pw.MemoryImage(
            img.encodeJpg(raster, quality: profile.quality),
          );
          output.addPage(
            pw.Page(
              pageFormat: pdf.PdfPageFormat(page.width, page.height),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Image(compressedImage, fit: pw.BoxFit.fill),
            ),
          );
          renderedPages++;
        } finally {
          rendered.dispose();
        }
      }
      if (renderedPages == 0) {
        throw const FormatException('No pages could be rendered.');
      }
      final bytes = await output.save();
      if (bytes.length >= originalBytes) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('PDF is already optimized'),
            content: Text(
              'The compressed result (${formatBytes(bytes.length)}) was not smaller than the original (${formatBytes(originalBytes)}), so no duplicate was saved. Try “Smallest file” for stronger compression.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      final reduction = ((1 - bytes.length / originalBytes) * 100).round();
      toast(
        'Reduced ${formatBytes(originalBytes)} to ${formatBytes(bytes.length)} ($reduction% smaller)',
      );
      final baseName = picked.name.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      await saveGeneratedPdf(bytes, '$baseName compressed', renderedPages);
    } catch (error) {
      if (mounted) toast('Could not compress PDF: $error');
    } finally {
      await source?.dispose();
    }
  }

  Future<(int, int)?> askPageRange(int pageCount) async {
    final startController = TextEditingController(text: '1');
    final endController = TextEditingController(text: '$pageCount');
    final range = await showDialog<(int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extract page range'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: startController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'From'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: endController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'To',
                  helperText: 'Max $pageCount',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final start = int.tryParse(startController.text);
              final end = int.tryParse(endController.text);
              if (start != null &&
                  end != null &&
                  start >= 1 &&
                  end >= start &&
                  end <= pageCount) {
                Navigator.pop(context, (start, end));
              }
            },
            child: const Text('Extract'),
          ),
        ],
      ),
    );
    startController.dispose();
    endController.dispose();
    return range;
  }

  Future<void> saveGeneratedPdf(
    List<int> bytes,
    String prefix,
    int pageCount, {
    String ocrText = '',
  }) async {
    final storage = await getApplicationDocumentsDirectory();
    final libraryFolder = Directory('${storage.path}/document_library');
    await libraryFolder.create(recursive: true);
    final timestamp = DateTime.now();
    final name = '$prefix ${timestamp.millisecondsSinceEpoch}.pdf';
    final path =
        '${libraryFolder.path}/${timestamp.microsecondsSinceEpoch}_$name';
    final file = await File(path).writeAsBytes(bytes, flush: true);
    final document = DocumentItem(
      name,
      DocType.pdf,
      formatBytes(await file.length()),
      pageCount,
      timestamp,
      path: path,
      ocrText: ocrText,
    );
    if (!mounted) return;
    setState(() {
      docs.insert(0, document);
      tab = 1;
    });
    await saveLibrary();
    if (mounted) open(document);
  }

  Future<void> openAiAssistant() async {
    final supported = docs
        .where((document) => document.path != null)
        .map((document) {
          final extension = document.name.split('.').last.toLowerCase();
          return AiDocumentSource(
            name: document.name,
            path: document.path!,
            extension: extension,
            ocrText: document.ocrText,
          );
        })
        .where(
          (document) => const {
            'pdf',
            'docx',
            'xlsx',
            'pptx',
            'rtf',
            'txt',
            'csv',
            'jpg',
            'jpeg',
            'png',
            'webp',
          }.contains(document.extension),
        )
        .toList();
    if (supported.isEmpty) {
      toast('Import a readable document first');
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AiDocumentAssistantScreen(documents: supported),
      ),
    );
  }

  Future<void> convertPdfToOffice(String extension) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Select a PDF to convert',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked?.path == null) return;
    try {
      toast('Converting PDF to ${extension == 'docx' ? 'Word' : 'Excel'}…');
      final pages = await PdfOfficeExporter.extractPages(picked!.path!);
      final bytes = extension == 'docx'
          ? PdfOfficeExporter.createWord(pages)
          : PdfOfficeExporter.createExcel(pages);
      final baseName = picked.name.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      await saveGeneratedDocument(
        bytes,
        '$baseName converted.$extension',
        extension == 'docx' ? DocType.docx : DocType.xlsx,
        pages.length,
      );
    } catch (error) {
      if (mounted) toast('Could not convert PDF: $error');
    }
  }

  Future<void> saveGeneratedDocument(
    List<int> bytes,
    String name,
    DocType type,
    int pages,
  ) async {
    final storage = await getApplicationDocumentsDirectory();
    final folder = Directory('${storage.path}/document_library');
    await folder.create(recursive: true);
    final timestamp = DateTime.now();
    final path = '${folder.path}/${timestamp.microsecondsSinceEpoch}_$name';
    final file = await File(path).writeAsBytes(bytes, flush: true);
    final document = DocumentItem(
      name,
      type,
      formatBytes(await file.length()),
      pages,
      timestamp,
      path: path,
    );
    if (!mounted) return;
    setState(() {
      docs.insert(0, document);
      tab = 1;
    });
    await saveLibrary();
    if (mounted) open(document);
  }
}

class ToolsView extends StatelessWidget {
  const ToolsView({
    super.key,
    required this.onImagesToPdf,
    required this.onMergePdfs,
    required this.onSplitPdf,
    required this.onCompressPdf,
    required this.onScanDocument,
    required this.onAiAssistant,
    required this.onPdfToWord,
    required this.onPdfToExcel,
  });
  final Future<void> Function() onImagesToPdf;
  final Future<void> Function() onMergePdfs;
  final Future<void> Function() onSplitPdf;
  final Future<void> Function() onCompressPdf;
  final Future<void> Function() onScanDocument;
  final Future<void> Function() onAiAssistant;
  final Future<void> Function() onPdfToWord;
  final Future<void> Function() onPdfToExcel;
  @override
  Widget build(BuildContext context) {
    final tools = [
      (
        'Images to PDF',
        Icons.collections_rounded,
        'Create one PDF from photos',
      ),
      ('Merge PDFs', Icons.call_merge_rounded, 'Combine multiple PDF files'),
      ('Split PDF', Icons.call_split_rounded, 'Extract a page range'),
      ('Compress PDF', Icons.compress_rounded, 'Reduce document size'),
      ('PDF to Word', Icons.description_outlined, 'Create an editable DOCX'),
      ('PDF to Excel', Icons.table_chart_outlined, 'Extract rows into XLSX'),
      (
        'Scan document',
        Icons.document_scanner_rounded,
        'Camera scan with auto crop',
      ),
      (
        'AI assistant',
        Icons.auto_awesome_rounded,
        'Summarize and ask questions',
      ),
    ];
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          title: Text('Document tools'),
          backgroundColor: Colors.transparent,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverGrid.builder(
            itemCount: tools.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: .92,
            ),
            itemBuilder: (context, i) {
              final item = tools[i];
              return Card(
                margin: const EdgeInsets.all(6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: switch (item.$1) {
                    'Images to PDF' => onImagesToPdf,
                    'Merge PDFs' => onMergePdfs,
                    'Split PDF' => onSplitPdf,
                    'Compress PDF' => onCompressPdf,
                    'PDF to Word' => onPdfToWord,
                    'PDF to Excel' => onPdfToExcel,
                    'Scan document' => onScanDocument,
                    'AI assistant' => onAiAssistant,
                    _ => () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${item.$1} is coming in Phase 2'),
                      ),
                    ),
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: brand.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(item.$2, color: brand),
                        ),
                        const Spacer(),
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.$3,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum ScanFilter { color, grayscale, blackAndWhite }

class ScanPage {
  const ScanPage({required this.path, this.rotation = 0});
  final String path;
  final int rotation;

  ScanPage rotate() => ScanPage(path: path, rotation: (rotation + 1) % 4);
}

class ScanReviewResult {
  const ScanReviewResult({required this.pages, required this.filter});
  final List<ScanPage> pages;
  final ScanFilter filter;
}

class InkStroke {
  const InkStroke({
    required this.page,
    required this.points,
    required this.color,
    required this.width,
  });

  final int page;
  final List<Offset> points;
  final int color;
  final double width;

  Map<String, Object> toJson() => {
    'page': page,
    'color': color,
    'width': width,
    'points': points.map((point) => [point.dx, point.dy]).toList(),
  };

  factory InkStroke.fromJson(Map<String, dynamic> json) => InkStroke(
    page: json['page'] as int,
    color: json['color'] as int,
    width: (json['width'] as num).toDouble(),
    points: (json['points'] as List)
        .map(
          (point) => Offset(
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
        )
        .toList(),
  );
}

class InkPainter extends CustomPainter {
  const InkPainter(this.strokes);
  final List<InkStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(
        stroke.points.first.dx * size.width,
        stroke.points.first.dy * size.height,
      );
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(
            stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height,
          ),
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) => true;
}

class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.paths});
  final List<String> paths;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late List<ScanPage> pages;
  ScanFilter filter = ScanFilter.color;

  @override
  void initState() {
    super.initState();
    pages = widget.paths.map((path) => ScanPage(path: path)).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Review scan (${pages.length})'),
      actions: [
        TextButton(
          onPressed: pages.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  ScanReviewResult(pages: pages, filter: filter),
                ),
          child: const Text('Create PDF'),
        ),
      ],
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<ScanFilter>(
            segments: const [
              ButtonSegment(
                value: ScanFilter.color,
                label: Text('Color'),
                icon: Icon(Icons.palette_outlined),
              ),
              ButtonSegment(
                value: ScanFilter.grayscale,
                label: Text('Gray'),
                icon: Icon(Icons.tonality_outlined),
              ),
              ButtonSegment(
                value: ScanFilter.blackAndWhite,
                label: Text('B&W'),
                icon: Icon(Icons.contrast_rounded),
              ),
            ],
            selected: {filter},
            onSelectionChanged: (value) => setState(() => filter = value.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.drag_indicator_rounded, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'Hold and drag to reorder pages',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: pages.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final page = pages.removeAt(oldIndex);
                pages.insert(newIndex, page);
              });
            },
            itemBuilder: (context, index) {
              final page = pages[index];
              return Card(
                key: ValueKey(page.path),
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 72,
                          height: 92,
                          child: RotatedBox(
                            quarterTurns: page.rotation,
                            child: Image.file(
                              File(page.path),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Page ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rotate',
                        onPressed: () =>
                            setState(() => pages[index] = page.rotate()),
                        icon: const Icon(Icons.rotate_right_rounded),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => setState(() => pages.removeAt(index)),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      const Icon(Icons.drag_handle_rounded),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.document,
    this.onDocumentCreated,
  });
  final DocumentItem document;
  final ValueChanged<DocumentItem>? onDocumentCreated;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final PdfViewerController pdfController = PdfViewerController();
  PdfTextSearcher? textSearcher;
  bool night = false;
  bool ready = false;
  bool bookmarked = false;
  bool drawMode = false;
  int inkColor = 0xFFE53935;
  double inkWidth = 3;
  final List<InkStroke> strokes = [];
  final List<InkStroke> redoStrokes = [];
  int page = 1;
  int? totalPages;

  String get documentKey => widget.document.path ?? widget.document.name;

  String get documentExtension =>
      widget.document.name.split('.').last.toLowerCase();

  bool get isOfficeDocument => const {
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'rtf',
  }.contains(documentExtension);

  @override
  void initState() {
    super.initState();
    loadReadingState();
  }

  @override
  void dispose() {
    textSearcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = night ? const Color(0xFF18191F) : const Color(0xFFE8E8EE);
    final paper = night ? const Color(0xFF292A31) : Colors.white;
    final ink = night ? Colors.white70 : const Color(0xFF34343D);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: night ? const Color(0xFF202127) : Colors.white,
        foregroundColor: night ? Colors.white : Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.document.pages == 0
                  ? 'Page $page${totalPages == null ? '' : ' of $totalPages'}'
                  : 'Page $page of ${totalPages ?? widget.document.pages}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (isOfficeDocument && widget.document.path != null)
            IconButton(
              onPressed: () => OpenFilex.open(widget.document.path!),
              tooltip: 'Open original Office layout',
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          IconButton(
            onPressed: () => setState(() => night = !night),
            icon: Icon(
              night ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            onPressed: openPdfSearch,
            tooltip: 'Search PDF',
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            onPressed: showRecognizedText,
            tooltip: 'Recognized text',
            icon: const Icon(Icons.text_snippet_outlined),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: ready
          ? readerBody(paper, ink)
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: BottomAppBar(
        color: night ? const Color(0xFF202127) : Colors.white,
        child: drawMode
            ? annotationControls()
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: showPageJump,
                    tooltip: 'Jump to page',
                    icon: const Icon(Icons.find_in_page_outlined),
                  ),
                  IconButton(
                    onPressed: toggleBookmark,
                    tooltip: 'Bookmark',
                    icon: Icon(
                      bookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: bookmarked ? Colors.amber.shade700 : null,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.document.type == DocType.pdf
                        ? () => setState(() => drawMode = true)
                        : null,
                    tooltip: 'Annotate',
                    icon: const Icon(Icons.draw_outlined),
                  ),
                  IconButton(
                    onPressed: () {},
                    tooltip: 'Fit page',
                    icon: const Icon(Icons.fit_screen_rounded),
                  ),
                ],
              ),
      ),
    );
  }

  Widget readerBody(Color paper, Color ink) {
    final document = widget.document;
    if (document.path != null && document.type == DocType.pdf) {
      return PdfViewer.file(
        document.path!,
        controller: pdfController,
        initialPageNumber: page,
        params: PdfViewerParams(
          onViewerReady: (pdf, controller) {
            Future.microtask(() {
              if (!mounted) return;
              textSearcher ??= PdfTextSearcher(pdfController);
              setState(() => totalPages = pdf.pages.length);
            });
          },
          pagePaintCallbacks: [
            (canvas, pageRect, page) => textSearcher
                ?.pageTextMatchPaintCallback(canvas, pageRect, page),
          ],
          pageOverlaysBuilder: (context, pageRect, pdfPage) => [
            buildInkOverlay(pdfPage.pageNumber),
          ],
          onPageChanged: (value) {
            if (value == null || value == page) return;
            setState(() => page = value);
            saveReadingState();
          },
        ),
      );
    }
    if (document.path != null && document.type == DocType.image) {
      return InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Center(child: Image.file(File(document.path!))),
      );
    }
    final extension = document.name.split('.').last.toLowerCase();
    if (document.path != null && (extension == 'txt' || extension == 'csv')) {
      return FutureBuilder<String>(
        future: File(document.path!).readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('This text file could not be read.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  snapshot.data!,
                  style: TextStyle(color: ink, height: 1.55, fontSize: 15),
                ),
              ),
            ),
          );
        },
      );
    }
    if (document.path != null &&
        const {
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'rtf',
        }.contains(extension)) {
      return NativeOfficeDocumentView(
        path: document.path!,
        name: document.name,
        extension: extension,
        night: night,
      );
    }
    return PageView.builder(
      controller: PageController(
        initialPage: page.clamp(1, document.pages) - 1,
      ),
      scrollDirection: Axis.vertical,
      itemCount: document.pages,
      onPageChanged: (value) {
        setState(() => page = value + 1);
        saveReadingState();
      },
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 18)],
          ),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 7,
                  decoration: BoxDecoration(
                    color: brand,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  i == 0
                      ? document.name.split('.').first
                      : 'Document page ${i + 1}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  document.path == null
                      ? 'Demo reader preview. Import a local PDF to use the native renderer.'
                      : 'The document was imported successfully. Native Office rendering is the next renderer milestone.',
                  style: TextStyle(color: ink, height: 1.6, fontSize: 15),
                ),
                const SizedBox(height: 24),
                ...List.generate(
                  7,
                  (line) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 9,
                    width: line == 6 ? 180 : double.infinity,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Spacer(),
                Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: ink.withValues(alpha: .5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> loadReadingState() async {
    final preferences = await SharedPreferences.getInstance();
    final savedPage = preferences.getInt('last_page:$documentKey') ?? 1;
    final savedBookmark =
        preferences.getBool('bookmark:$documentKey:$savedPage') ?? false;
    final savedInk = preferences.getString('ink:$documentKey');
    final loadedStrokes = <InkStroke>[];
    if (savedInk != null) {
      try {
        loadedStrokes.addAll(
          (jsonDecode(savedInk) as List).map(
            (item) => InkStroke.fromJson(item as Map<String, dynamic>),
          ),
        );
      } on FormatException {
        await preferences.remove('ink:$documentKey');
      }
    }
    if (!mounted) return;
    setState(() {
      page = savedPage;
      bookmarked = savedBookmark;
      strokes.addAll(loadedStrokes);
      ready = true;
    });
  }

  Future<void> saveReadingState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('last_page:$documentKey', page);
    if (!mounted) return;
    setState(() {
      bookmarked = preferences.getBool('bookmark:$documentKey:$page') ?? false;
    });
  }

  Future<void> toggleBookmark() async {
    final preferences = await SharedPreferences.getInstance();
    final next = !bookmarked;
    await preferences.setBool('bookmark:$documentKey:$page', next);
    if (!mounted) return;
    setState(() => bookmarked = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Page $page bookmarked' : 'Bookmark removed'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget buildInkOverlay(int pageNumber) {
    final pageStrokes = strokes
        .where((stroke) => stroke.page == pageNumber)
        .toList();
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) => IgnorePointer(
          ignoring: !drawMode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              final size = constraints.biggest;
              final point = Offset(
                (details.localPosition.dx / size.width).clamp(0, 1),
                (details.localPosition.dy / size.height).clamp(0, 1),
              );
              setState(() {
                redoStrokes.clear();
                strokes.add(
                  InkStroke(
                    page: pageNumber,
                    points: [point],
                    color: inkColor,
                    width: inkWidth,
                  ),
                );
              });
            },
            onPanUpdate: (details) {
              if (strokes.isEmpty || strokes.last.page != pageNumber) return;
              final size = constraints.biggest;
              setState(() {
                strokes.last.points.add(
                  Offset(
                    (details.localPosition.dx / size.width).clamp(0, 1),
                    (details.localPosition.dy / size.height).clamp(0, 1),
                  ),
                );
              });
            },
            onPanEnd: (_) => saveInk(),
            child: CustomPaint(
              painter: InkPainter(pageStrokes),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  Widget annotationControls() => Row(
    children: [
      for (final value in const [0xFFE53935, 0xFF1E88E5, 0xFF212121])
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: InkWell(
            onTap: () => setState(() => inkColor = value),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(value),
                shape: BoxShape.circle,
                border: Border.all(
                  color: inkColor == value ? Colors.amber : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
      PopupMenuButton<double>(
        tooltip: 'Pen width',
        initialValue: inkWidth,
        onSelected: (value) => setState(() => inkWidth = value),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 2, child: Text('Thin')),
          PopupMenuItem(value: 4, child: Text('Medium')),
          PopupMenuItem(value: 7, child: Text('Thick')),
        ],
        icon: const Icon(Icons.line_weight_rounded),
      ),
      const Spacer(),
      IconButton(
        tooltip: 'Undo',
        onPressed: strokes.isEmpty ? null : undoInk,
        icon: const Icon(Icons.undo_rounded),
      ),
      IconButton(
        tooltip: 'Redo',
        onPressed: redoStrokes.isEmpty ? null : redoInk,
        icon: const Icon(Icons.redo_rounded),
      ),
      IconButton(
        tooltip: 'Save annotated copy',
        onPressed: strokes.isEmpty ? null : exportAnnotatedCopy,
        icon: const Icon(Icons.save_as_outlined),
      ),
      FilledButton.tonal(
        onPressed: () {
          saveInk();
          setState(() => drawMode = false);
        },
        child: const Text('Done'),
      ),
    ],
  );

  Future<void> saveInk() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'ink:$documentKey',
      jsonEncode(strokes.map((stroke) => stroke.toJson()).toList()),
    );
  }

  void undoInk() {
    if (strokes.isEmpty) return;
    setState(() => redoStrokes.add(strokes.removeLast()));
    saveInk();
  }

  void redoInk() {
    if (redoStrokes.isEmpty) return;
    setState(() => strokes.add(redoStrokes.removeLast()));
    saveInk();
  }

  Future<void> exportAnnotatedCopy() async {
    final sourcePath = widget.document.path;
    if (sourcePath == null || strokes.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Creating annotated copy…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    PdfDocument? source;
    try {
      source = await PdfDocument.openFile(sourcePath);
      final output = pw.Document();
      for (final sourcePage in source.pages) {
        final rendered = await sourcePage.render(
          fullWidth: sourcePage.width * 2,
          fullHeight: sourcePage.height * 2,
        );
        if (rendered == null) continue;
        try {
          final raster = img.Image.fromBytes(
            width: rendered.width,
            height: rendered.height,
            bytes: rendered.pixels.buffer,
            bytesOffset: rendered.pixels.offsetInBytes,
            numChannels: 4,
            order: img.ChannelOrder.bgra,
          );
          for (final stroke in strokes.where(
            (stroke) => stroke.page == sourcePage.pageNumber,
          )) {
            final color = Color(stroke.color);
            final drawColor = img.ColorRgba8(
              (color.r * 255).round(),
              (color.g * 255).round(),
              (color.b * 255).round(),
              (color.a * 255).round(),
            );
            if (stroke.points.length == 1) {
              final point = stroke.points.first;
              img.fillCircle(
                raster,
                x: (point.dx * raster.width).round(),
                y: (point.dy * raster.height).round(),
                radius: stroke.width.round(),
                color: drawColor,
              );
            } else {
              for (var index = 1; index < stroke.points.length; index++) {
                final start = stroke.points[index - 1];
                final end = stroke.points[index];
                img.drawLine(
                  raster,
                  x1: (start.dx * raster.width).round(),
                  y1: (start.dy * raster.height).round(),
                  x2: (end.dx * raster.width).round(),
                  y2: (end.dy * raster.height).round(),
                  color: drawColor,
                  thickness: stroke.width * 2,
                  antialias: true,
                );
              }
            }
          }
          final pageImage = pw.MemoryImage(img.encodeJpg(raster, quality: 92));
          output.addPage(
            pw.Page(
              pageFormat: pdf.PdfPageFormat(
                sourcePage.width,
                sourcePage.height,
              ),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Image(pageImage, fit: pw.BoxFit.fill),
            ),
          );
        } finally {
          rendered.dispose();
        }
      }
      final storage = await getApplicationDocumentsDirectory();
      final folder = Directory('${storage.path}/document_library');
      await folder.create(recursive: true);
      final timestamp = DateTime.now();
      final baseName = widget.document.name.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final name = '$baseName annotated.pdf';
      final path = '${folder.path}/${timestamp.microsecondsSinceEpoch}_$name';
      final file = await File(
        path,
      ).writeAsBytes(await output.save(), flush: true);
      final created = DocumentItem(
        name,
        DocType.pdf,
        formatFileSize(await file.length()),
        source.pages.length,
        timestamp,
        path: path,
        ocrText: widget.document.ocrText,
      );
      widget.onDocumentCreated?.call(created);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save annotated copy: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      await source?.dispose();
    }
  }

  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> showPageJump() async {
    final maximum = totalPages ?? widget.document.pages;
    if (maximum < 1) return;
    final controller = TextEditingController(text: '$page');
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Page number',
            helperText: 'Enter a number from 1 to $maximum',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (target == null || target < 1 || target > maximum) return;
    if (pdfController.isReady) {
      await pdfController.goToPage(pageNumber: target);
    } else if (mounted) {
      setState(() => page = target);
    }
    await saveReadingState();
  }

  void showRecognizedText() {
    final text = widget.document.ocrText.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No OCR text is available for this document.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recognized text',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openPdfSearch() async {
    final searcher = textSearcher;
    if (searcher == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.document.type == DocType.pdf
                ? 'The PDF is still loading.'
                : 'Search is available for PDF documents.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final controller = TextEditingController(
      text: searcher.pattern is String ? searcher.pattern! as String : '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          PdfSearchPanel(searcher: searcher, controller: controller),
    );
    controller.dispose();
  }
}

class PdfSearchPanel extends StatelessWidget {
  const PdfSearchPanel({
    super.key,
    required this.searcher,
    required this.controller,
  });

  final PdfTextSearcher searcher;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: searcher,
    builder: (context, _) {
      final current = searcher.currentIndex == null
          ? 0
          : searcher.currentIndex! + 1;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search in PDF',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) => searcher.startTextSearch(value),
              onSubmitted: (value) =>
                  searcher.startTextSearch(value, searchImmediately: true),
              decoration: InputDecoration(
                hintText: 'Enter text to find',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: () {
                    controller.clear();
                    searcher.resetTextSearch();
                  },
                  icon: const Icon(Icons.clear_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (searcher.isSearching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (searcher.isSearching) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    searcher.isSearching
                        ? 'Searching page ${searcher.searchingPageNumber ?? 1} of ${searcher.totalPageCount ?? '…'}'
                        : searcher.matches.isEmpty
                        ? 'No matches'
                        : '$current of ${searcher.matches.length} matches',
                  ),
                ),
                IconButton(
                  tooltip: 'Previous match',
                  onPressed: searcher.hasMatches
                      ? searcher.goToPrevMatch
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                IconButton(
                  tooltip: 'Next match',
                  onPressed: searcher.hasMatches
                      ? searcher.goToNextMatch
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
