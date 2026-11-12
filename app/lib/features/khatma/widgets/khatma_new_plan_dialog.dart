import '../../../core/text/arabic_normalizer.dart';
import 'package:flutter/material.dart';
import '../../../core/services/khatma_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import 'khatma_helpers.dart';

/// Dialog to configure and launch a new Quran Khatma plan, with options to plan
/// either by daily wird (pages per day) or by total duration (target days).
void showKhatmaNewPlanDialog(BuildContext context) {
  // Mode: 'by_wird' (تحديد الورد اليومي) OR 'by_days' (تحديد مدة الختمة بالأيام)
  String planMode = 'by_wird';

  // Wird-based parameters
  int selectedWirdPages = 20; // Default: 1 Juz (20 pages)
  bool isCustomWird = false;
  final customWirdController = TextEditingController(text: '10');

  // Days-based parameters
  int selectedDays = 30;
  bool isCustomDays = false;
  final customDaysController = TextEditingController(text: '45');

  bool splitByPrayer = true;
  bool startFromCurrent = false;
  bool reminderEnabled = true;
  TimeOfDay reminderTime = const TimeOfDay(hour: 8, minute: 0);

  final titleController = TextEditingController(text: 'ختمة القرآن الكريم (جزء يومياً)');
  final currentReadPage = SettingsService.instance.lastReadPageNumber;

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final totalPages = 604 - (startFromCurrent ? currentReadPage : 1) + 1;
          final int activeWirdPages = isCustomWird
              ? (ArabicNormalizer.tryParseInt(customWirdController.text) ?? 10).clamp(1, 604)
              : selectedWirdPages;

          final int activeDays = isCustomDays
              ? (ArabicNormalizer.tryParseInt(customDaysController.text) ?? 30).clamp(1, 730)
              : selectedDays;

          final int computedDays = planMode == 'by_wird'
              ? (totalPages / activeWirdPages).ceil().clamp(1, 730)
              : activeDays;

          final int computedWirdPages = planMode == 'by_wird'
              ? activeWirdPages
              : (totalPages / activeDays).ceil().clamp(1, 604);

          final int perPrayerPages = (computedWirdPages / 5).ceil();

          return Directionality(
            textDirection: SettingsService.instance.textDirection,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.auto_stories_rounded, color: AppColors.primaryGreen),
                  SizedBox(width: 8),
                  Text('بدء ختمة قرآنية جديدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'عنوان الختمة',
                        filled: true,
                        fillColor: AppColors.primaryGreen.withOpacity(0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Mode Toggle: By Daily Wird vs By Duration
                    const Text('طريقة تخطيط الختمة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setDialogState(() {
                                  planMode = 'by_wird';
                                  titleController.text = 'ختمة القرآن (ورد $activeWirdPages صفحة يومياً)';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: planMode == 'by_wird' ? AppColors.primaryGreen : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '📖 تحديد الورد اليومي',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: planMode == 'by_wird' ? Colors.white : AppColors.primaryGreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setDialogState(() {
                                  planMode = 'by_days';
                                  titleController.text = 'ختمة القرآن ($activeDays يوماً)';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: planMode == 'by_days' ? AppColors.primaryGreen : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '⏳ تحديد مدة الختمة',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: planMode == 'by_days' ? Colors.white : AppColors.primaryGreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Option A: Planning by Daily Wird (Pages per day)
                    if (planMode == 'by_wird') ...[
                      const Text('اختر مقدار وردك اليومي:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('جزء كامل (٢٠ صفحة)'),
                            selected: !isCustomWird && selectedWirdPages == 20,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomWird = false;
                                  selectedWirdPages = 20;
                                  titleController.text = 'ختمة جزء يومياً (٣٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('نصف جزء (١٠ صفحات)'),
                            selected: !isCustomWird && selectedWirdPages == 10,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomWird = false;
                                  selectedWirdPages = 10;
                                  titleController.text = 'ختمة نصف جزء (٦٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('حزب / ربع جزء (٥ صفحات)'),
                            selected: !isCustomWird && selectedWirdPages == 5,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomWird = false;
                                  selectedWirdPages = 5;
                                  titleController.text = 'ختمة حزب يومياً (١٢٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('جزآن يومياً (٤٠ صفحة)'),
                            selected: !isCustomWird && selectedWirdPages == 40,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomWird = false;
                                  selectedWirdPages = 40;
                                  titleController.text = 'ختمة جزآن يومياً (١٥ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('صفحة بعد كل صلاة (٤ صفحات)'),
                            selected: !isCustomWird && selectedWirdPages == 4,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomWird = false;
                                  selectedWirdPages = 4;
                                  titleController.text = 'ختمة ٤ صفحات يومياً (١٥٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('مقدار مخصص...'),
                            selected: isCustomWird,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomWird = true;
                                  final p = ArabicNormalizer.tryParseInt(customWirdController.text) ?? 10;
                                  titleController.text = 'ختمة مخصصة ($p صفحات يومياً)';
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (isCustomWird) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('عدد الصفحات يومياً: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 85,
                              child: TextField(
                                controller: customWirdController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (val) {
                                  setDialogState(() {
                                    final p = ArabicNormalizer.tryParseInt(val) ?? 10;
                                    titleController.text = 'ختمة مخصصة ($p صفحات يومياً)';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('صفحة / يوم', style: TextStyle(color: AppColors.mutedText)),
                          ],
                        ),
                      ],
                    ] else ...[
                      // Option B: Planning by Target Days
                      const Text('اختر المدة المخططة للختمة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('٣٠ يوماً (شهر كامل)'),
                            selected: !isCustomDays && selectedDays == 30,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomDays = false;
                                  selectedDays = 30;
                                  titleController.text = 'ختمة الشهر (٣٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('٦٠ يوماً (شهران)'),
                            selected: !isCustomDays && selectedDays == 60,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomDays = false;
                                  selectedDays = 60;
                                  titleController.text = 'ختمة الشهرين (٦٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('٩٠ يوماً (٣ أشهر)'),
                            selected: !isCustomDays && selectedDays == 90,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomDays = false;
                                  selectedDays = 90;
                                  titleController.text = 'ختمة الثلاثة أشهر (٩٠ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('١٥ يوماً (نصف شهر)'),
                            selected: !isCustomDays && selectedDays == 15,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomDays = false;
                                  selectedDays = 15;
                                  titleController.text = 'ختمة النصف شهر (١٥ يوماً)';
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('مدة مخصصة بالأيام...'),
                            selected: isCustomDays,
                            selectedColor: AppColors.accentGold.withOpacity(0.3),
                            onSelected: (val) {
                              if (val) {
                                setDialogState(() {
                                  isCustomDays = true;
                                  titleController.text = 'ختمة مخصصة (${customDaysController.text} يوماً)';
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (isCustomDays) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('عدد الأيام: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 85,
                              child: TextField(
                                controller: customDaysController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (val) {
                                  setDialogState(() {
                                    final days = ArabicNormalizer.tryParseInt(val) ?? 30;
                                    titleController.text = 'ختمة مخصصة ($days يوماً)';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('يوماً', style: TextStyle(color: AppColors.mutedText)),
                          ],
                        ),
                      ],
                    ],

                    const SizedBox(height: 12),

                    // Interactive Calculation Summary Box
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
                              const Text('الورد اليومي المستهدف:', style: TextStyle(fontSize: 12.5)),
                              Text(
                                '${KhatmaFormatHelper.toArabicIndic(computedWirdPages)} صفحة يومياً',
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
                                '${KhatmaFormatHelper.toArabicIndic(perPrayerPages)} صفحات',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryGreen),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('مدة الختمة المتوقعة:', style: TextStyle(fontSize: 12.5)),
                              Text(
                                '${KhatmaFormatHelper.toArabicIndic(computedDays)} يوماً',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentGold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    const Divider(),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('البدء من موضع قراءتي الحالي بالمصحف', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('صفحة ${KhatmaFormatHelper.toArabicIndic(currentReadPage)} من ٦٠٤', style: const TextStyle(fontSize: 12, color: AppColors.mutedText)),
                      activeColor: AppColors.primaryGreen,
                      value: startFromCurrent,
                      onChanged: (val) {
                        setDialogState(() => startFromCurrent = val);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تقسيم الورد على الصلوات الخمس', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('توزيع حصة اليوم على أوقات الصلاة المكتوبة', style: TextStyle(fontSize: 12, color: AppColors.mutedText)),
                      activeColor: AppColors.primaryGreen,
                      value: splitByPrayer,
                      onChanged: (val) {
                        setDialogState(() => splitByPrayer = val);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تفعيل التذكير اليومي بالورد', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('موعد التنبيه: ${KhatmaFormatHelper.formatTimeOfDay(reminderTime.hour, reminderTime.minute)}', style: const TextStyle(fontSize: 12, color: AppColors.secondaryGreen)),
                      activeColor: AppColors.primaryGreen,
                      value: reminderEnabled,
                      onChanged: (val) {
                        setDialogState(() => reminderEnabled = val);
                      },
                    ),
                    if (reminderEnabled)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: const Text('تعديل وقت التنبيه'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: reminderTime,
                            );
                            if (picked != null && ctx.mounted) {
                              setDialogState(() => reminderTime = picked);
                            }
                          },
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await KhatmaService.instance.createPlan(
                      title: titleController.text.trim().isNotEmpty
                          ? titleController.text.trim()
                          : 'ختمة القرآن الكريم',
                      targetDays: computedDays,
                      customDailyPace: planMode == 'by_wird' ? computedWirdPages : null,
                      splitByPrayer: splitByPrayer,
                      startingPage: startFromCurrent ? currentReadPage : 1,
                      reminderEnabled: reminderEnabled,
                      reminderHour: reminderTime.hour,
                      reminderMinute: reminderTime.minute,
                    );
                    if (context.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('بدء الختمة المباركة', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      );
    },
  ).whenComplete(() {
    Future.delayed(const Duration(milliseconds: 350), () {
      titleController.dispose();
      customWirdController.dispose();
      customDaysController.dispose();
    });
  });
}
