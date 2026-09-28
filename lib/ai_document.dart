import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'office_renderer.dart';

class AiDocumentSource {
  const AiDocumentSource({
    required this.name,
    required this.path,
    required this.extension,
    this.ocrText = '',
  });
  final String name;
  final String path;
  final String extension;
  final String ocrText;
}

class DocumentInsights {
  const DocumentInsights({
    required this.text,
    required this.summary,
    required this.keyPoints,
    required this.dates,
    required this.amounts,
    required this.actionItems,
  });
  final String text;
  final String summary;
  final List<String> keyPoints;
  final List<String> dates;
  final List<String> amounts;
  final List<String> actionItems;
}

class DocumentTextExtractor {
  static Future<String> extract(AiDocumentSource source) async {
    if (source.extension == 'pdf') {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(source.path);
        final pages = <String>[];
        for (final page in document.pages) {
          final text = await page.loadText();
          if (text != null && text.fullText.trim().isNotEmpty) {
            pages.add(text.fullText.trim());
          }
        }
        final extracted = pages.join('\n\n');
        return extracted.isNotEmpty ? extracted : source.ocrText;
      } finally {
        await document?.dispose();
      }
    }
    if (const {'docx', 'xlsx', 'pptx', 'rtf'}.contains(source.extension)) {
      return (await OfficeParser.parse(
        source.path,
        source.extension,
      )).plainText;
    }
    if (const {'txt', 'csv'}.contains(source.extension)) {
      return File(source.path).readAsString();
    }
    return source.ocrText;
  }
}

class OfflineDocumentIntelligence {
  static const _stopWords = {
    'the',
    'a',
    'an',
    'and',
    'or',
    'of',
    'to',
    'in',
    'on',
    'for',
    'with',
    'is',
    'are',
    'was',
    'were',
    'be',
    'by',
    'this',
    'that',
    'from',
    'as',
    'at',
    'it',
    'will',
    'shall',
    'have',
    'has',
    'ও',
    'এর',
    'এই',
    'যে',
    'একটি',
    'হবে',
    'করে',
    'থেকে',
    'জন্য',
    'সাথে',
    'করা',
    'হয়',
    'বা',
  };

  static DocumentInsights analyze(String rawText) {
    final text = rawText.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (text.isEmpty) {
      throw const FormatException('No readable text was found.');
    }
    final sentences = _sentences(text);
    final ranked = _rank(sentences);
    final summarySentences = ranked.take(5).map((entry) => entry.$1).toSet();
    final summary = sentences
        .where(summarySentences.contains)
        .take(5)
        .join(' ');
    final dates = _uniqueMatches(
      text,
      RegExp(
        r'\b(?:\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)[a-z]*\s+\d{2,4})\b',
        caseSensitive: false,
      ),
    );
    final amounts = _uniqueMatches(
      text,
      RegExp(
        r'(?:৳|\$|€|£|BDT|USD|EUR|GBP)\s?[\d,]+(?:\.\d{1,2})?|[\d,]+(?:\.\d{1,2})?\s?(?:টাকা|BDT|USD|EUR|GBP)',
        caseSensitive: false,
      ),
    );
    final actions = sentences
        .where(
          (sentence) => RegExp(
            r'\b(?:must|shall|need to|required|action|deadline|due)\b|করতে হবে|প্রয়োজন|দায়িত্ব|সময়সীমা',
            caseSensitive: false,
          ).hasMatch(sentence),
        )
        .take(10)
        .toList();
    return DocumentInsights(
      text: text,
      summary: summary.isEmpty ? sentences.take(3).join(' ') : summary,
      keyPoints: ranked.take(8).map((entry) => entry.$1).toList(),
      dates: dates,
      amounts: amounts,
      actionItems: actions,
    );
  }

  static String answer(DocumentInsights insights, String question) {
    final queryTerms = _terms(question).toSet();
    if (queryTerms.isEmpty) return 'Please ask a more specific question.';
    final ranked =
        _sentences(insights.text)
            .map((sentence) {
              final terms = _terms(sentence).toSet();
              final overlap = queryTerms.where(terms.contains).length;
              final exactBonus =
                  sentence.toLowerCase().contains(question.trim().toLowerCase())
                  ? 4
                  : 0;
              return (sentence, overlap + exactBonus);
            })
            .where((entry) => entry.$2 > 0)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    if (ranked.isEmpty) {
      return 'I could not find that information in this document.';
    }
    return ranked.take(3).map((entry) => entry.$1).join('\n\n');
  }

  static List<(String, double)> _rank(List<String> sentences) {
    final frequency = <String, int>{};
    for (final sentence in sentences) {
      for (final term in _terms(sentence).toSet()) {
        frequency[term] = (frequency[term] ?? 0) + 1;
      }
    }
    final ranked = sentences.indexed.map((entry) {
      final terms = _terms(entry.$2);
      final score = terms.isEmpty
          ? 0.0
          : terms.fold<double>(0, (sum, term) => sum + (frequency[term] ?? 0)) /
                terms.length;
      return (entry.$2, score + (entry.$1 < 3 ? .25 : 0));
    }).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return ranked;
  }

  static List<String> _sentences(String text) => text
      .split(RegExp(r'(?<=[.!?।])\s+|\n+'))
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.length > 20)
      .toList();

  static List<String> _terms(String value) =>
      RegExp(r'[\p{L}\p{N}]+', unicode: true)
          .allMatches(value.toLowerCase())
          .map((match) => match.group(0)!)
          .where((term) => term.length > 2 && !_stopWords.contains(term))
          .toList();

  static List<String> _uniqueMatches(String value, RegExp pattern) => pattern
      .allMatches(value)
      .map((match) => match.group(0)!.trim())
      .toSet()
      .take(20)
      .toList();
}

class AiDocumentAssistantScreen extends StatefulWidget {
  const AiDocumentAssistantScreen({super.key, required this.documents});
  final List<AiDocumentSource> documents;

  @override
  State<AiDocumentAssistantScreen> createState() =>
      _AiDocumentAssistantScreenState();
}

class _AiDocumentAssistantScreenState extends State<AiDocumentAssistantScreen> {
  AiDocumentSource? selected;
  Future<DocumentInsights>? insights;
  final questionController = TextEditingController();
  final messages = <({bool user, String text})>[];

  @override
  void initState() {
    super.initState();
    if (widget.documents.isNotEmpty) select(widget.documents.first);
  }

  @override
  void dispose() {
    questionController.dispose();
    super.dispose();
  }

  void select(AiDocumentSource source) {
    selected = source;
    messages.clear();
    insights = DocumentTextExtractor.extract(
      source,
    ).then(OfflineDocumentIntelligence.analyze);
  }

  void ask(DocumentInsights value) {
    final question = questionController.text.trim();
    if (question.isEmpty) return;
    final answer = OfflineDocumentIntelligence.answer(value, question);
    setState(() {
      messages.add((user: true, text: question));
      messages.add((user: false, text: answer));
      questionController.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Document Assistant')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: DropdownButtonFormField<AiDocumentSource>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Document',
              border: OutlineInputBorder(),
            ),
            items: widget.documents
                .map(
                  (document) => DropdownMenuItem(
                    value: document,
                    child: Text(document.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => select(value));
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<DocumentInsights>(
            future: insights,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Could not analyze this document:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final value = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _section('Summary', value.summary),
                  _listSection('Key points', value.keyPoints),
                  if (value.dates.isNotEmpty)
                    _listSection('Important dates', value.dates),
                  if (value.amounts.isNotEmpty)
                    _listSection('Amounts', value.amounts),
                  if (value.actionItems.isNotEmpty)
                    _listSection('Action items', value.actionItems),
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      'Ask this document',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...messages.map(
                    (message) => Align(
                      alignment: message.user
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: message.user
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(message.text),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: questionController,
                          onSubmitted: (_) => ask(value),
                          decoration: const InputDecoration(
                            hintText: 'Payment condition কী?',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => ask(value),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _section(String title, String content) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 9),
          SelectableText(content, style: const TextStyle(height: 1.5)),
        ],
      ),
    ),
  );

  Widget _listSection(String title, List<String> values) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...values.map(
            (value) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text('• $value'),
            ),
          ),
        ],
      ),
    ),
  );
}
