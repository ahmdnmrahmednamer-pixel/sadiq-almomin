# Code organization and bounded dead-code cleanup,21 November2026

## Ground rules

Refactoring preserves current behavior, accessible actions, route names, saved settings, historical assets and native alarm choices. A source file being outside the main entrypoint dependency graph is a lead, not permission to remove a feature. Test evidence is not native-device verification. No whole-app readiness or release claim is made here.

## Source organization

- `lib/main.dart`: current executable Dart entrypoint.
- `lib/app`: app shell, routing and app-level presentation.
- `lib/core/services`: shared service state and domain operations.
- `lib/core/notifications`: notification and prayer-alarm integration.
- `lib/core/audio`: shared audio playback coordination.
- `lib/features`: feature screens, widgets and feature-specific interaction.
- `test`: unit, widget, accessibility-action and contract checks.

This first pass removes obsolete wrappers only. It does not move public files, rename services, change dependency wiring or introduce a new architecture for its own sake.

## Removed wrappers

| Source under `lib/features/home/widgets/` | Definition | Lines | Reference evidence |
| --- | --- | --- | --- |
| `home_adaptive_dashboard.dart` | `HomeAdaptiveDashboardBanner` |138| No import/export/part, route, constructor use or test reference outside its own file |
| `home_adhkar_time_banner.dart` | `HomeAdhkarTimeBanner` |77| Same |
| `home_khatma_card.dart` | `HomeKhatmaCard` |114| Same |
| `home_prayer_tracker_card.dart` | `HomePrayerTrackerCard` |119| Same |

Total448lines removed. Their destination screens and services remain. Current Home uses the daily-progress card, adhkar/tasbih row and quick-sections grid. The real router still exposes adhkar, khatma, prayer tracker, daily wird, fiqh, Quran sciences, names/shamail, history, unified search and card studio independently. No memorial widget, dedication or media asset was removed.

## Dependency evidence

Before cleanup:236Dart sources, one detected executable entrypoint,211reachable production files,25outside the entrypoint graph. After cleanup:232sources, the exact same211reachable file paths and exact same SHA-256 for every one. No missing relative/package import, export or part target was found. Full-text checks of source, tests and available native/build configuration found no use of these four filenames/classes outside their definitions. The files contain widgets, not a separate executable or registration hook.

The graph resolves local/package imports,exports and parts. It is static evidence, not proof about external consumers or every possible string-generated integration. Direct symbol/path searches and unchanged reachable source hashes are independent checks for this limited deletion. No code generation or native registration referring to these widgets was found.

## Retained candidates,not certified dead

The following21files are outside the current entrypoint graph but remain untouched. Several have direct tests; others may represent intended detached feature/UI work. Reconnecting or retiring them needs separate evidence about the intended product surface,not a blanket cleanup.

- `lib/app/theme/app_assets.dart`: 1direct test import(s).
- `lib/core/services/qiraat_service.dart`: 1direct test import(s).
- `lib/features/audio/scholars_audio_library_screen.dart`: 1direct test import(s).
- `lib/features/hadith/hadith_detail_screen.dart`: 1direct test import(s).
- `lib/features/hadith/hadith_library_screen.dart`: 1direct test import(s).
- `lib/features/home/widgets/home_momen_memorial_banner.dart`: 0direct test import(s).
- `lib/features/home/widgets/home_shortcuts_list.dart`: 2direct test import(s).
- `lib/features/library/screens/islamic_mutoon_screen.dart`: 0direct test import(s).
- `lib/features/library/screens/riyad_alsalihin_screen.dart`: 1direct test import(s).
- `lib/features/library/widgets/comprehensive_libraries_portal.dart`: 1direct test import(s).
- `lib/features/onboarding/onboarding_screen.dart`: 3direct test import(s).
- `lib/features/prayer/widgets/prayer_nav_cards.dart`: 0direct test import(s).
- `lib/features/settings/widgets/sections/settings_adhan_and_sensors_section.dart`: 0direct test import(s).
- `lib/features/settings/widgets/sections/settings_language_and_appearance_section.dart`: 0direct test import(s).
- `lib/features/settings/widgets/sections/settings_prayer_and_fiqh_section.dart`: 1direct test import(s).
- `lib/features/settings/widgets/sections/settings_quran_and_audio_section.dart`: 0direct test import(s).
- `lib/features/settings/widgets/settings_calculation_method_modal.dart`: 0direct test import(s).
- `lib/features/settings/widgets/settings_font_size_modal.dart`: 0direct test import(s).
- `lib/features/settings/widgets/settings_language_modal.dart`: 1direct test import(s).
- `lib/features/settings/widgets/settings_prayer_reminders_modal.dart`: 0direct test import(s).
- `lib/features/settings/widgets/settings_theme_modal.dart`: 0direct test import(s).

## Verification after removal

-28tests across6focused Home/router, drawer, focus-isolation, khatma and prayer-tracker files pass.
- Full `lib` analyzer:0errors,0warnings,49existing style infos. This pass does not disguise existing infos as a clean analyzer.
- Actual Home was additionally rendered with bundled fonts at360x800/412x915 and1x/2x. Visible date/GPS/daily-progress/Quran/adhkar surfaces were inspected. The temporary capture hook was restored and is not a repository change.
- Existing tests exercise touch and explicit semantic actions,settings navigation/return,progress updates and persistence. They do not certify actual TalkBack swipe traversal or phone notification delivery.

## Remaining validation boundaries

Native scheduled-adhan fidelity still needs a real device/emulator and the pending decision about an old unavailable recording's audible behavior. Recording rights/subjective quality are not resolved by catalog metadata. Four original offline/live-book fixture cases and current Windows-specific reference alignment remain unverified. No APK,signing,permission,storage-layout or release change is part of this cleanup.

## Next passes

Review each remaining candidate against current routes and product intent before deletion. For larger service refactors,extract one responsibility with existing behavior contracts first,then compare focused persistence/cancellation/ownership tests. Keep feature verification as a per-feature evidence ledger: source/unit/widget evidence separately from real-device,network,offline and accessibility evidence. Never turn one green suite into a claim that all features and services work in production.
