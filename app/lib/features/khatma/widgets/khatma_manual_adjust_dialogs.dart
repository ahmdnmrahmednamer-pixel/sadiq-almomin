import '../../../core/text/arabic_normalizer.dart';
import '../../../core/services/settings_service.dart';
import 'package:flutter/material.dart';
import '../../../core/services/khatma_service.dart';
import '../../../core/theme/app_theme.dart';
import 'khatma_helpers.dart';

/// Dialog to manually adjust current page in the active Khatma.
void showKhatmaManualPageAdjustDialog(BuildContext context, KhatmaPlan plan) {
  final pageController = TextEditingController(text: plan.currentPage.toString());

  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppColors.primaryGreen),
            SizedBox(width: 8),
            Text('تعديل موضع الصفحة يدوياً', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إذا قرأت من المصحف الورقي أو تطبيق خارجي، يمكنك مزامنة الصفحة التي وصلت إليها مباشرة:',
              style: TextStyle(fontSize: 13, color: AppColors.mutedText, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pageController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'رقم الصفحة (من ١ إلى ٦٠٤)',
                filled: true,
                fillColor: AppColors.primaryGreen.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.bookmark_border_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final page = ArabicNormalizer.tryParseInt(pageController.text);
              if (page != null && page >= 1 && page <= 604) {
                await KhatmaService.instance.setManualPage(page);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم تحديث موضع القراءة إلى صفحة ${KhatmaFormatHelper.toArabicIndic(page)} بنجاح.'),
                      backgroundColor: AppColors.primaryGreen,
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ التعديل', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    Future.delayed(const Duration(milliseconds: 350), pageController.dispose);
  });
}

/// Dialog to adjust daily Khatma reminder notification settings.
void showKhatmaReminderSettingsDialog(BuildContext context, KhatmaPlan plan) {
  bool enabled = plan.reminderEnabled;
  TimeOfDay time = TimeOfDay(hour: plan.reminderHour, minute: plan.reminderMinute);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setLocalState) {
        return Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: AppColors.primaryGreen),
                SizedBox(width: 8),
                Text('إعدادات التذكير اليومي بالورد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل التنبيه اليومي', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('تنبيه يومي لطيف بمستهدف ورد اليوم', style: TextStyle(fontSize: 12, color: AppColors.mutedText)),
                  value: enabled,
                  activeColor: AppColors.primaryGreen,
                  onChanged: (val) {
                    setLocalState(() => enabled = val);
                  },
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.primaryGreen.withOpacity(0.3)),
                    ),
                    leading: const Icon(Icons.access_time_rounded, color: AppColors.primaryGreen),
                    title: const Text('وقت التنبيه المفضل', style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: Text(
                      KhatmaFormatHelper.formatTimeOfDay(time.hour, time.minute),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryGreen),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: time);
                      if (picked != null) {
                        setLocalState(() => time = picked);
                      }
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await KhatmaService.instance.updateReminderSettings(
                    enabled: enabled,
                    hour: time.hour,
                    minute: time.minute,
                  );
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ إعدادات التذكير بالورد بنجاح'),
                        backgroundColor: AppColors.primaryGreen,
                      ),
                    );
                  }
                },
                child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Dialog to adjust daily Quran wird pace (pages per day) for the active Khatma.
void showKhatmaDailyWirdAdjustDialog(BuildContext context, KhatmaPlan plan) {
  int currentPace = plan.pagesPerDay;
  int selectedPace = currentPace;
  bool isCustom = ![5, 10, 20, 40, 4].contains(selectedPace);
  final customController = TextEditingController(text: selectedPace.toString());

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final remainingPages = plan.remainingPages;
        final estimatedDays = selectedPace > 0 ? (remainingPages / selectedPace).ceil() : 0;
        final perPrayer = (selectedPace / 5).ceil();

        return Directionality(
          textDirection: SettingsService.instance.textDirection,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.primaryGreen),
                SizedBox(width: 8),
                Text('تحديد وتعديل الورد اليومي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'حدد المقدار القرآني الذي ترغب بتلاوته يومياً، وسيتم تحديث جدول الختمة والمدة المتبقية تلقائياً:',
                    style: TextStyle(fontSize: 13, color: AppColors.mutedText, height: 1.4),
                  ),
                  const SizedBox(height: 14),

                  // Presets Wrap
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('جزء كامل (٢٠ صفحة)'),
                        selected: !isCustom && selectedPace == 20,
                        selectedColor: AppColors.accentGold.withOpacity(0.3),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              isCustom = false;
                              selectedPace = 20;
                            });
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('نصف جزء (١٠ صفحات)'),
                        selected: !isCustom && selectedPace == 10,
                        selectedColor: AppColors.accentGold.withOpacity(0.3),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              isCustom = false;
                              selectedPace = 10;
                            });
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('حزب / ربع جزء (٥ صفحات)'),
                        selected: !isCustom && selectedPace == 5,
                        selectedColor: AppColors.accentGold.withOpacity(0.3),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              isCustom = false;
                              selectedPace = 5;
                            });
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('جزآن يومياً (٤٠ صفحة)'),
                        selected: !isCustom && selectedPace == 40,
                        selectedColor: AppColors.accentGold.withOpacity(0.3),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              isCustom = false;
                              selectedPace = 40;
                            });
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('صفحة بعد كل صلاة (٤ صفحات)'),
                        selected: !isCustom && selectedPace == 4,
                        selectedColor: AppColors.accentGold.withOpacity(0.3),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              isCustom = false;
                              selectedPace = 4;
                            });
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('مقدار مخصص...'),
                        selected: isCustom,
                        selectedColor: AppColors.accentGold.withOpacity(0.3),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              isCustom = true;
                              selectedPace = ArabicNormalizer.tryParseInt(customController.text) ?? 10;
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  if (isCustom) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('عدد الصفحات يومياً: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: customController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (val) {
                              final p = ArabicNormalizer.tryParseInt(val) ?? 10;
                              setDialogState(() => selectedPace = p.clamp(1, 604));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('صفحة / يوم', style: TextStyle(color: AppColors.mutedText)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Real-time Calculation Summary Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('الورد اليومي المعتمد:', style: TextStyle(fontSize: 12.5)),
                            Text(
                              '${KhatmaFormatHelper.toArabicIndic(selectedPace)} صفحة يومياً',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('حصة كل صلاة (٥ صلوات):', style: TextStyle(fontSize: 12.5)),
                            Text(
                              '${KhatmaFormatHelper.toArabicIndic(perPrayer)} صفحات',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryGreen),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('المدة المتبقية لإتمام الختمة:', style: TextStyle(fontSize: 12.5)),
                            Text(
                              '${KhatmaFormatHelper.toArabicIndic(estimatedDays)} يوماً',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentGold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await KhatmaService.instance.updateDailyWirdPace(selectedPace);
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تحديث الورد اليومي إلى ${KhatmaFormatHelper.toArabicIndic(selectedPace)} صفحة بنجاح.'),
                        backgroundColor: AppColors.primaryGreen,
                      ),
                    );
                  }
                },
                child: const Text('حفظ الورد الجديد', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    ),
  ).whenComplete(() {
    Future.delayed(const Duration(milliseconds: 350), customController.dispose);
  });
}

/// Dialog to confirm cancelling the active Khatma plan.
void confirmCancelKhatmaPlan(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: SettingsService.instance.textDirection,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('إلغاء الختمة الحالية', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من رغبتك في إلغاء الختمة الحالية والبدء من جديد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await KhatmaService.instance.cancelPlan();
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    ),
  );
}
