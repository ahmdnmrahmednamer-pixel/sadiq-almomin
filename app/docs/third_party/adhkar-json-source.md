# Adhkar-json text source

This stage adds the text corpus from https://github.com/rn0x/Adhkar-json as a separate searchable library. It does not replace the existing quick categories, progress counters, reviewed bundled audio or scheduled reminders.

- Source commit: `93dc3fc489e4291da8816265920b3cb7e2c3b569`
- Original file: `adhkar.json`
- Bundled asset: `assets/data/rn0x_adhkar.json`
- Original bytes: 148,985
- Git blob SHA-1: `2a29dd13be4dae44d5f7ebe3e11650d9e849bc3b`
- Original upstream SHA-256: `ee0df147cc9fdcbc8bed542703ba2d43f70329baa4d8ee7a99adf7929112a65f`
- Packaged bytes: 148,986
- Packaged SHA-256: `338c931c8cea5bf34936acb0ecedf1ebfbd8868171236427ae8873d74655a7cf`
- Packaging change: exactly one LF byte after the original JSON document, for the repository editor. No decoded content changes. The bundled file is not byte-identical to upstream.
- Categories: 132
- Entries: 267

The loader checks the exact packaged file's SHA-256 before parsing, without trimming or normalization. Removing its final LF reconstructs the original pinned upstream bytes and hash; the packaging regression test verifies both hashes. Extra or missing whitespace is rejected by the loader. Category titles, item text, source IDs and repetition counts are preserved. The source's combined morning/evening category remains combined. Import does not add hadith grading, references or virtues that are absent from this source.

Raw item IDs repeat across categories. Stable item keys include the source namespace, category ID and item ID. They are not written into the app's existing numeric counter map. This text reader shows source repetition counts; it does not add a new interactive counter or migrate saved progress.

The upstream README attributes the material to Hisn al-Muslim by Sa'id ibn Ali ibn Wahf al-Qahtani. It makes its own free-use claim, without a standard license file. This note records that source statement; it is not a certification that the uploader holds every right in every recording.

No recordings from this repository are bundled or played in this stage. Their relative paths remain metadata only. The source's audio references and reciter attribution do not establish recording identity, content review, rights clearance or device playback acceptance.

The existing audio section and prayer settings remain separate. Native/OEM/reboot/audible and real-device screen-reader acceptance are not established by these text import and widget tests.
