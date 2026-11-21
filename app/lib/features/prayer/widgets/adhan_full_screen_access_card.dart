import 'package:flutter/material.dart';
import '../../../core/services/adhan_full_screen_access_service.dart';

/// Permission controls never request access on entry or lifecycle refresh.
class AdhanFullScreenAccessCard extends StatefulWidget {
  const AdhanFullScreenAccessCard({super.key});
  @override
  State<AdhanFullScreenAccessCard> createState() =>
      _AdhanFullScreenAccessCardState();
}

class _AdhanFullScreenAccessCardState extends State<AdhanFullScreenAccessCard>
    with WidgetsBindingObserver {
  final _service = AdhanFullScreenAccessService();
  bool? _allowed;
  bool _busy = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh({bool request = false}) async {
    final generation = ++_generation;
    if (mounted) setState(() => _busy = true);
    final result = request ? await _service.request() : await _service.check();
    if (!mounted || generation != _generation) return;
    setState(() {
      _allowed = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('شاشة الأذان الكاملة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'في أندرويد ١٤ والأحدث يوجد إذن مستقل لتنبيهات الشاشة الكاملة. ليس هو إذن الظهور فوق التطبيقات. يختار النظام شاشة كاملة عند القفل أو إشعاراً علوياً أثناء الاستخدام حسب الإعدادات.'),
            const SizedBox(height: 8),
            Semantics(
                liveRegion: true,
                child: Text(_busy
                    ? 'جار فحص الإذن'
                    : _allowed == true
                        ? 'إذن الشاشة الكاملة مسموح'
                        : _allowed == false
                            ? 'إذن الشاشة الكاملة غير مسموح'
                            : 'تعذر التحقق من إذن الشاشة الكاملة')),
            const Text(
                'إذا لم تسمح به، يبقى تنبيه الصلاة عبر الإشعار العادي حسب أذونات الإشعارات والصوت. السماح بالشاشة الكاملة لا يصلح وحده موعداً غير مجدول ولا يضمن وصول الأذان.'),
            if (_allowed != true)
              TextButton(
                  key: const ValueKey('adhan_full_screen_request'),
                  onPressed: _busy ? null : () => _refresh(request: true),
                  child: const Text('مراجعة إذن الشاشة الكاملة في النظام')),
            TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('إعادة فحص إذن الشاشة الكاملة')),
          ]),
        ),
      );
}
