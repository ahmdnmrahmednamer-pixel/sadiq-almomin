# Adhan recording source review, 21 November 2026

## Scope and limits

This is a partial source repair, not certification of the whole library or completion of remote-voice alarm support. Public source catalogs attribute the names below. The reviewed downloads produced complete adhan text. This does not independently authenticate the speaker, establish a pristine listening-quality verdict or grant redistribution rights. No new audio binary is bundled or rehosted.

Abdulbasit candidates remain content-unverified. Their catalog labels alone are insufficient to substitute one into the app. Husary is a historical low-bitrate source, not an HD master. Naqshabandi and Minshawi have decoded peaks above full scale and must not be called pristine HD. Bitrate labels describe measured files, not subjective quality.

## Reviewed sources

| Catalog ID | Catalog attribution | Duration | MP3 audio bitrate | Channels | Bytes | Source page |
| --- | --- | --- | --- | --- | --- | --- |
| `adhan_naqshbandi` | Naqshabandi | 157.796s | 128 kbps | 2 | 2528903 | https://www.myhuda.com/ar/main-menue/audio/azkar/naqshabandy/الآذان-بصوت-الشيخ-النقشبندى/ |
| `adhan_menshawi` | Minshawi | 246.944s | 128 kbps | 2 | 3955074 | https://ar.assabile.com/adhan-call-prayer/egypt |
| `adhan_hussary` | Husary | 127.504s | 16 kbps | 1 | 256128 | https://audio.islamweb.net/audio/info/122667 |
| `adhan_alqatami` | Nasser al-Qatami | 135.792s | 128 kbps | 2 | 2241376 | https://audio.islamweb.net/audio/info/317311 |
| `adhan_wadih_alyamani` | Wadi Hamadi al-Yamani | 200.132s | 128 kbps | 2 | 3270708 | https://audio.islamweb.net/audio/info/425434 |
| `adhan_amr_sobhi` | Amr Sobhi | 206.924s | 128 kbps | 1 | 3379378 | https://audio.islamweb.net/audio/info/428132 |

### Download identity at review

- `adhan_naqshbandi` SHA-256: `62ffe3dcea5847d3dbf37b64403e3ad97fcc035b93267ca78349938de7297cfd`
- `adhan_menshawi` SHA-256: `c3f91aa3fb93b9e8ce7f9ec5c6f406be67a1fc459def8bd91a5093fb44c66580`
- `adhan_hussary` SHA-256: `3866a11de8d78f42c4e563ffb398b670f6483bb12768e21ec567b527ca15e8e3`
- `adhan_alqatami` SHA-256: `d4266d868755b3e29c8f48cdc97432c55d59860cb7d7d0c3c377ec24626a88f1`
- `adhan_wadih_alyamani` SHA-256: `217969915b9404700b9fc4f26ad2d1a707ae9df05a7c49db8dcf1dd814eab787`
- `adhan_amr_sobhi` SHA-256: `c75a4e796355cd4bbe07132d180e482ebf627db4de2d2e179c3132561d044105`

## Bundled Husary cross-check

The app asset and actual Android raw sound each decode to127.44s,56kbps mono. Both yield the complete adhan text. Their decoded waveform correlation is0.999977 over the full duration. Against the catalog-attributed Islamweb source above, the raw sound aligns within5ms; waveform correlation is0.8117 and20ms RMS-envelope correlation0.999448 over127.435s. This is strong same-recording evidence after transcoding, not independent speaker authentication or an HD-master claim. Native device playback remains unverified. An explicit supported channel key alone never establishes that its raw recording has been source-checked.

## Storage and safety behavior

Corrected existing recordings use revisioned download names. Old files stay on disk and count in storage totals, but cannot masquerade as corrected downloads. Explicit deletion still removes the track's retained and current files. Download IDs and saved prayer selections are preserved.

The old Hazza al-Balushi entry linked a Quran surah as its primary recording and an archive recording catalogued as Oman as its alternate. Its ID remains in the catalog and storage remains intact, but its sources, preview, download and new assignment are unavailable pending source review. Existing stored prayer selections are not rewritten.

Quran-surah fallbacks have been removed from adhan entries. Other unreviewed source-name relationships remain pending; their old labels are not evidence of verification. The archive collection used by the old catalog is https://archive.org/details/Athan_Mawsoa_mp3 .

## Scheduled Android voices

The current native resolver has explicit bundled sound mappings only for its existing supported keys. Other saved keys still retain the old runtime behavior; this change does not silently silence, replace or cancel an existing reminder. Changing an existing unsupported selection's audible behavior is a separate decision.

New assignments are limited to explicit supported keys. Unsupported remote choices show an Arabic preview/download-only explanation and cannot be newly assigned. Listening and downloading remain available for recordings that are not held. This is a temporary truthful limitation, not the intended final alarm feature. Remote selected-voice support still needs a durable Android-readable sound source, revision-safe notification channels, failure behavior that preserves times, and real-device validation.

## Validation

108 local tests across13 focused files pass; analyzer reports no issues in9 changed source/test files. Tests cover source identities, absence of Quran fallbacks, legacy-file retention/accounting, held playback/download boundaries, saved-choice preservation, unsupported new-assignment rejection, supported assignments and independent preview/download controls. Actual Cairo-font320px/2x renders were inspected for the held and preview-only options. Device TalkBack and native alarm playback have not been verified.
