import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _sourceFontLicenseRegistered=false;

/// Bundled fallback covers original-source honorific codepoints that Amiri lacks.
/// This changes glyph rendering only, never source strings or copied text.
void registerSourceFontLicense(){
 if(_sourceFontLicenseRegistered)return;
 _sourceFontLicenseRegistered=true;
 LicenseRegistry.addLicense(()async*{
  yield LicenseEntryWithLineBreaks(const ['Kitab'],await rootBundle.loadString('assets/fonts/Kitab-OFL.txt'));
 });
}
