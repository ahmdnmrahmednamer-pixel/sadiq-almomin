/// Temporary switches. A feature set to false is hidden from every entry point
/// (home, drawer, directory, router) but its code stays in the project, so it can
/// be turned back on by changing one value.
///
/// The Quran radio (MP3Quran stations) is off until the owner decides its source
/// and approach. Egyptian heritage content is a separate feature and is not affected.
const bool kIslamicRadioEnabled = false;

/// تلاوات متميزة: 145-station list adapted from the owner's supplied tool.
/// Enabled for the owner-requested replacement.
const bool kCuratedRadioEnabled = true;
