import 'package:flutter/material.dart';

import '../../core/services/settings_service.dart';
import '../../core/services/shamela_epub_service.dart';
import '../../core/text/arabic_normalizer.dart';
import 'shamela_library_screen.dart';
import 'shamela_offline_reader_screen.dart';

/// A local-only entry to complete Shamela books already saved by the app.
class DownloadedBooksScreen extends StatefulWidget {
  final ShamelaEpubService? epubService;
  const DownloadedBooksScreen({super.key, this.epubService});

  @override
  State<DownloadedBooksScreen> createState() => _DownloadedBooksScreenState();
}

class _DownloadedBooksScreenState extends State<DownloadedBooksScreen> {
  late final ShamelaEpubService _service;
  List<OfflineShamelaBook> _books = const [];
  bool _loading = true;
  bool _failed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _service = widget.epubService ?? ShamelaEpubService();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final books = await _service.listSavedBooks();
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _browse() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShamelaLibraryScreen(epubService: _service),
    ));
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final query = ArabicNormalizer.normalize(_query);
    final visible = _books
        .where((book) => ArabicNormalizer.normalize(
              '${book.title} ${book.author}',
            ).contains(query))
        .toList();
    return Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قارئ الكتب'),
          actions: [
            IconButton(
              tooltip: 'تحديث الكتب المحمّلة',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            )
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    semanticsLabel: 'تحميل قائمة الكتب'))
            : _failed
                ? Center(
                    child: SingleChildScrollView(
                        child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('تعذر فتح قائمة الكتب المحمّلة',
                          textAlign: TextAlign.center),
                      TextButton(
                          onPressed: _reload,
                          child: const Text('إعادة المحاولة')),
                    ]),
                  )))
                : _books.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                            child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('لا توجد كتب محمّلة',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          const Text(
                              'نزّل كتابًا من الشاملة، ثم افتحه هنا دون إنترنت.',
                              textAlign: TextAlign.center),
                          TextButton(
                              onPressed: _browse,
                              child: const Text('المكتبة الشاملة')),
                        ]),
                      )))
                    : Column(children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'بحث في الكتب المحمّلة',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                        ),
                        Expanded(
                            child: visible.isEmpty
                                ? const Center(child: Text('لا توجد نتائج'))
                                : RefreshIndicator(
                                    onRefresh: _reload,
                                    child: ListView.separated(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 24),
                                      itemCount: visible.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final book = visible[index];
                                        return Card(
                                            child: ListTile(
                                          title: Text(book.title),
                                          subtitle: Text(
                                              '${book.author}\n${book.pageCount} صفحة'),
                                          isThreeLine: true,
                                          trailing:
                                              const Icon(Icons.chevron_left),
                                          onTap: () => Navigator.of(context)
                                              .push(MaterialPageRoute<void>(
                                            builder: (_) =>
                                                ShamelaOfflineReaderScreen(
                                                    book: book,
                                                    epubService: _service),
                                          )),
                                        ));
                                      },
                                    ),
                                  )),
                      ]),
      ),
    );
  }
}
