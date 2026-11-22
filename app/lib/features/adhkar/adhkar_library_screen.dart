import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/adhkar_library.dart';
import '../../core/services/adhkar_library_loader.dart';
import '../../core/services/settings_service.dart';
import '../../core/text/arabic_normalizer.dart';

/// The imported text corpus is separate from quick counters and reviewed audio.
class AdhkarLibraryScreen extends StatefulWidget {
  const AdhkarLibraryScreen({super.key, this.assetBundle});
  final AssetBundle? assetBundle;

  @override
  State<AdhkarLibraryScreen> createState() => _AdhkarLibraryScreenState();
}

class _AdhkarLibraryScreenState extends State<AdhkarLibraryScreen> {
  late Future<ImportedAdhkarLibrary?> _library;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _library = _loadLibrary();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<ImportedAdhkarLibrary?> _loadLibrary() async {
    try {
      return await AdhkarLibraryLoader.load(bundle: widget.assetBundle);
    } catch (_) {
      // A retry can fail before the next frame subscribes to its future.
      // Keep that failure explicit without an unhandled asynchronous error.
      return null;
    }
  }

  void _retry() => setState(() {
        _library = _loadLibrary();
      });

  bool _matches(ImportedAdhkarCategory category) {
    final query = ArabicNormalizer.normalize(_query);
    return query.isEmpty ||
        ArabicNormalizer.normalize(category.title).contains(query) ||
        category.items.any(
            (item) => ArabicNormalizer.normalize(item.text).contains(query));
  }

  Future<void> _sourceInfo() => showDialog<void>(
        context: context,
        builder: (context) => Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            contentPadding: const EdgeInsets.all(16),
            titlePadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            scrollable: true,
            title: const Text('مصدر المكتبة'),
            content: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'النصوص وأعداد التكرار من مكتبة Adhkar-json. ينسبها المصدر إلى كتاب حصن المسلم لسعيد بن علي بن وهف القحطاني.'),
                SizedBox(height: 12),
                Text(
                    'هذه مرحلة النصوص. التسجيلات الصوتية من هذا المصدر غير مضافة هنا، والعدادات السابقة لم تتغير.'),
                SizedBox(height: 12),
                SelectableText(ImportedAdhkarLibrary.sourceRepository),
                SizedBox(height: 12),
                Text('نسخة المصدر المثبتة:'),
                SelectableText(ImportedAdhkarLibrary.sourceCommit),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Scaffold(
          appBar: _libraryAppBar(context, 'مكتبة حصن المسلم', actions: [
            IconButton(
              tooltip: 'مصدر المكتبة',
              onPressed: _sourceInfo,
              icon: const Icon(Icons.info_outline),
            ),
          ]),
          body: FutureBuilder<ImportedAdhkarLibrary?>(
            future: _library,
            builder: (context, snapshot) {
              if (snapshot.hasError ||
                  (snapshot.connectionState == ConnectionState.done &&
                      !snapshot.hasData)) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('تعذر تحميل مكتبة الأذكار.'),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _retry,
                            child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(
                        semanticsLabel: 'جارٍ تحميل المكتبة'));
              }
              final categories = snapshot.data!.categories
                  .where(_matches)
                  .toList(growable: false);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'بحث في المكتبة',
                        border: const OutlineInputBorder(),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _query = '';
                                }),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Semantics(
                        liveRegion: true,
                        child: Text('عدد الفئات: ${categories.length}')),
                  ),
                  Expanded(
                    child: categories.isEmpty
                        ? const Center(
                            child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('لا توجد نتائج.')))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              void open() {
                                FocusScope.of(context).unfocus();
                                Navigator.of(context)
                                    .push(MaterialPageRoute<void>(
                                  builder: (_) => AdhkarLibraryCategoryScreen(
                                      category: category),
                                ));
                              }

                              return Semantics(
                                key: ValueKey(
                                    'source-category-${category.sourceCategoryId}'),
                                label:
                                    '${category.title}، عدد النصوص: ${category.items.length}',
                                button: true,
                                onTap: open,
                                excludeSemantics: true,
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    onTap: open,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(category.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          const SizedBox(height: 8),
                                          Text(
                                              'عدد النصوص: ${category.items.length}'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class AdhkarLibraryCategoryScreen extends StatelessWidget {
  const AdhkarLibraryCategoryScreen({super.key, required this.category});
  final ImportedAdhkarCategory category;

  Future<void> _copy(BuildContext context, ImportedDhikrItem item) async {
    try {
      await Clipboard.setData(ClipboardData(text: item.text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم نسخ الذكر.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر نسخ الذكر.')));
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Scaffold(
          appBar: _libraryAppBar(context, 'أذكار وأدعية'),
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: category.items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                      header: true,
                      child: Text(category.title,
                          style: Theme.of(context).textTheme.headlineSmall)),
                );
              }
              final item = category.items[index - 1];
              return Card(
                key: ValueKey(item.progressKey),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                              header: true, child: Text('الذكر رقم $index')),
                          Text('عدد التكرار: ${item.repeatCount}'),
                          IconButton(
                            tooltip: 'نسخ الذكر رقم $index',
                            onPressed: () => _copy(context, item),
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(item.text,
                          style: const TextStyle(
                              fontFamily: 'Amiri', fontSize: 22, height: 1.8)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}

PreferredSizeWidget _libraryAppBar(BuildContext context, String title,
    {List<Widget> actions = const []}) {
  final theme = Theme.of(context);
  final style = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
  final scaler = MediaQuery.textScalerOf(context);
  final available =
      (MediaQuery.sizeOf(context).width - 56 - actions.length * 48 - 32)
          .clamp(1.0, double.infinity);
  final painter = TextPainter(
    text: TextSpan(text: title, style: style),
    textDirection: SettingsService.instance.textDirection,
    textScaler: scaler,
  )..layout(maxWidth: available);
  final height = (painter.height + 24).clamp(kToolbarHeight, double.infinity);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return AppBar(
    toolbarHeight: height,
    title: Text(title,
        style: style,
        textScaler: scaler,
        maxLines: lines,
        softWrap: true,
        overflow: TextOverflow.visible),
    actions: actions,
  );
}
