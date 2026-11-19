import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/budur_source.dart';
import '../../../core/services/budur_reference_resolver.dart';
import '../../../core/services/quran_repository.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/ayah.dart';
import '../../../core/services/settings_service.dart';
import '../../../app/router.dart';

class QiraatMushafScreen extends StatefulWidget {
  final BudurSource? source;
  final int initialSurah, initialAyah;
  const QiraatMushafScreen(
      {super.key, this.source, this.initialSurah = 1, this.initialAyah = 0});
  @override
  State<QiraatMushafScreen> createState() => _QiraatMushafScreenState();
}

class _QiraatMushafScreenState extends State<QiraatMushafScreen> {
  late final BudurSource _source;
  List<Surah> _surahs = [];
  List<BudurPassage> _passages = [];
  int _surah = 1, _ayah = 0, _count = 7, _version = 0;
  bool _busy = true;
  bool _referenceBusy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _surah = widget.initialSurah;
    _ayah = widget.initialAyah;
    _count = _ayah > 7 ? _ayah : 7;
    _source = widget.source ?? BudurSource();
    _load();
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _busy = true;
      _error = null;
      _passages = [];
    });
    try {
      final surahs = await QuranRepository.loadSurahs();
      if (surahs.isEmpty)
        throw const FormatException('Surah catalogue unavailable');
      final current = surahs.firstWhere((s) => s.id == _surah);
      final ayahs = await QuranRepository.getAyahsForSurah(_surah);
      if (ayahs.isEmpty)
        throw const FormatException('Verse reference unavailable');
      final text = await _source.load();
      final passages = BudurSource.passages(text, current, ayahs);
      if (!mounted || version != _version) return;
      setState(() {
        _surahs = surahs;
        _count = ayahs.length;
        _passages = passages;
        _busy = false;
      });
    } catch (_) {
      if (mounted && version == _version)
        setState(() {
          _busy = false;
          _error =
              'تعذر تحميل نص البدور الزاهرة. تحقق من الاتصال وأعد المحاولة.';
        });
    }
  }

  Future<void> _openReference(BudurReference reference) async {
    if (_referenceBusy) return;
    setState(() => _referenceBusy = true);
    try {
      final surah = _surahs.firstWhere((s) => s.id == reference.surah);
      final ayahs = await QuranRepository.getAyahsForSurah(reference.surah);
      final text = await _source.load();
      final passage = await compute(
          _resolveBudurReference, (text, reference, surah, ayahs));
      if (mounted) setState(() => _referenceBusy = false);
      if (!mounted) return;
      if (passage == null)
        throw const FormatException('Reference source entry is not unique');
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SafeArea(
              child: FractionallySizedBox(
                  heightFactor: 0.8,
                  child: Directionality(
                      textDirection: SettingsService.instance.textDirection,
                      child: Column(children: [
                        ListTile(
                            title: Text('موضع الإحالة · ${surah.nameAr}'),
                            subtitle: Text(passage.firstPage == passage.lastPage
                                ? 'ص ${passage.firstPage}'
                                : 'ص ${passage.firstPage} إلى ${passage.lastPage}'),
                            trailing: IconButton(
                                tooltip: 'إغلاق',
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context))),
                        Expanded(
                            child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: SelectableText(passage.text,
                                    style: const TextStyle(
                                        fontSize: 18, height: 1.8)))),
                        for (final next in BudurReferenceResolver.references(
                            reference.surah, passage.text))
                          TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _openReference(next);
                              },
                              child: const Text('متابعة إحالة المؤلف')),
                      ])))));
    } catch (_) {
      if (mounted) setState(() => _referenceBusy = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر فتح موضع الإحالة من المصدر. أعد المحاولة.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _ayah == 0
        ? _passages
        : _passages.where((p) => p.ayahs.contains(_ayah)).toList();
    return Directionality(
        textDirection: SettingsService.instance.textDirection,
        child: Scaffold(
            appBar: AppBar(
                leading: const IsolatedBackButton(),
                title: const Text('القراءات')),
            body: Column(children: [
              if (_referenceBusy)
                const LinearProgressIndicator(
                    semanticsLabel: 'تحميل موضع الإحالة'),
              const ListTile(
                  title: Text('البدور الزاهرة'),
                  subtitle: Text('عبد الفتاح القاضي · الشاطبية والدرة')),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                        child: DropdownButtonFormField<int>(
                            initialValue: _surah,
                            decoration:
                                const InputDecoration(labelText: 'السورة'),
                            isExpanded: true,
                            items: _surahs
                                .map((s) => DropdownMenuItem(
                                    value: s.id, child: Text(s.nameAr)))
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      _surah = v;
                                      _ayah = 0;
                                      _load();
                                    }
                                  })),
                    const SizedBox(width: 12),
                    Expanded(
                        child: DropdownButtonFormField<int>(
                            key: ValueKey('$_surah:$_count'),
                            initialValue: _ayah,
                            decoration:
                                const InputDecoration(labelText: 'الآية'),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                  value: 0, child: Text('السورة كاملة')),
                              for (var n = 1; n <= _count; n++)
                                DropdownMenuItem(value: n, child: Text('$n'))
                            ],
                            onChanged: _busy
                                ? null
                                : (v) {
                                    if (v != null) setState(() => _ayah = v);
                                  })),
                  ])),
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'ربط بالاقتباس وسياق الموضع. الأصول والإحالات العامة ليست خريطة مكتملة لكل أحكام الآية.')),
              Expanded(
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  Text(_error!),
                                  TextButton(
                                      onPressed: _load,
                                      child: const Text('إعادة المحاولة'))
                                ]))
                          : shown.isEmpty
                              ? const Center(
                                  child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                          'لم يكتمل ربط هذا الموضع بعد. لا يعني ذلك عدم وجوده في الكتاب. سياق السورة متاح إلى حين إكمال الربط.')))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: shown.length,
                                  itemBuilder: (c, i) {
                                    final p = shown[i];
                                    return Card(
                                        child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(
                                                      p.firstPage == p.lastPage
                                                          ? 'ص ${p.firstPage}'
                                                          : 'ص ${p.firstPage} إلى ${p.lastPage}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium),
                                                  if (p.ayahs.length > 1)
                                                    const Text(
                                                        'مقطع ذو مواضع متعددة؛ ليس كل ما فيه خاصًا بكل آية.'),
                                                  const SizedBox(height: 8),
                                                  SelectableText(p.text,
                                                      style: const TextStyle(
                                                          fontSize: 18,
                                                          height: 1.8)),
                                                  for (final reference
                                                      in BudurReferenceResolver
                                                          .references(
                                                              _surah, p.text))
                                                    TextButton(
                                                        onPressed: () =>
                                                            _openReference(
                                                                reference),
                                                        child: const Text(
                                                            'فتح موضع إحالة المؤلف')),
                                                ])));
                                  })),
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: SelectableText(BudurSource.bookUrl,
                      style: TextStyle(fontSize: 12))),
            ])));
  }
}

BudurPassage? _resolveBudurReference(
        (String, BudurReference, Surah, List<Ayah>) args) =>
    BudurReferenceResolver.resolve(args.$1, args.$2, args.$3, args.$4);
