# Shamela integration review

Scope: source-filtered religious book search, in-app online text reading, optional complete-book EPUB saving to private application support storage, offline contents/navigation and position restore. Existing independent library sections remain. No BRF conversion, public Downloads storage, general document reader, or audio/adhkar changes are included.

Pre-upload main was 08f1eb47f11c9ab942bc9dd74deeb196e355500f. The three shared files pubspec.yaml, pubspec.lock and islamic_library_screen.dart were read again before changes and matched the implementation baseline. Updates were applied to main as requested. No release or APK is provided.

## Checks

27 focused Flutter tests passed locally, including a mocked search/download/read UI flow, real official EPUB structure verification, source identity, ZIP safety, DOM text order, offline reload, library entry navigation, 2x text-scale layout, semantics labels and keyboard navigation between the tabs. The real sample contains 5,118 spine items and 2,245 contents entries. It is not bundled.

Synthetic security-test EPUBs are embedded as base64 in test/shamela_synthetic_fixtures.dart. The fixture loader also supports optional on-disk files. Tests passed with those disk files absent. No real copyrighted book is embedded.

Run from app:

```
flutter pub get
flutter test --no-test-assets test/shamela_library_service_test.dart test/shamela_epub_service_test.dart test/shamela_online_reader_test.dart test/shamela_ui_flow_test.dart test/shamela_entry_test.dart
```

Real-book validation is optional and gated by SHAMELA_REAL_EPUB. Live testing is gated by SHAMELA_LIVE=1. Visual test environment inputs SHAMELA_TEST_ARABIC_FONT, SHAMELA_TEST_ICON_FONT and SHAMELA_OFFLINE_ROOT are required for shamela_library_widget_test.dart; otherwise those checks skip. Test images used explicitly loaded Arabic-capable fonts, not the application's original bundled fonts.

## Remaining validation

The local working snapshot was incomplete. Full application build and the complete existing test suite were not verified. Android SDK 36, build tools 36 and a compatible JDK were prepared, but no APK was built. Device download/cancel/delete behavior and actual Android TalkBack traversal remain to be tested using the complete source and original assets. Widget semantics checks are not a substitute for TalkBack testing.

Source references:
- https://shamela.ws/book/1446
- https://shamela.ws/book/1446/1
- https://old.shamela.ws/index.php/book/1446
- https://old.shamela.ws/epubs/014/1446.epub
- https://shamela.ws/robots.txt
