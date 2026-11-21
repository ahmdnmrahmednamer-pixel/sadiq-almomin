# Unavailable adhan source containment, 2026-11-21

This is a catalog safety repair, not a high-quality recording expansion or a native alarm implementation.

## Findings

The collection at https://archive.org/details/Athan_Mawsoa_mp3 supplies metadata that contradicts five existing catalog identities:

| Catalog ID | Source file | Finding |
|---|---|---|
| `adhan_alzamil` | `048-1.mp3` | Publisher credits Ahmad Nawaf Al-Mijlad, not Majid Al-Zamil. |
| `adhan_fares_abbad` | `076-3.mp3` | Publisher credits Nasser Al-Qatami, not Fares Abbad. |
| `adhan_sudais` | `032.mp3` | Publisher credits Sayyid Mutawalli Al-Al, not Abdul Rahman Al-Sudais. |
| `adhan_shuraim` | `033.mp3` | Publisher credits Abdul Razzaq Saleh, not Saud Al-Shuraim. |
| `adhan_bosnia` | `007.mp3` | Publisher identifies Turkey, not Bosnia/Sarajevo. |

This establishes conflicting attribution, not independent speaker authentication. No replacement is inferred from it.

Five additional original downloads returned HTTP 404 on 2026-11-21 and have no matching file in the collection metadata:

- `adhan_azhar`: https://archive.org/download/Athan_Mawsoa_mp3/039.mp3
- `adhan_morocco_qarawiyyin`: https://archive.org/download/Athan_Mawsoa_mp3/040.mp3
- `adhan_tunis_zaytouna`: https://archive.org/download/Athan_Mawsoa_mp3/041.mp3
- `adhan_khalil_aqsa`: https://archive.org/download/Athan_Mawsoa_mp3/042.mp3
- `adhan_fatih_istanbul`: https://archive.org/download/Athan_Mawsoa_mp3/043.mp3

## Scope and preservation

These ten IDs remain in the catalog but cannot be previewed, downloaded, played through the generic audio player, or newly assigned. Their remote candidates and unsupported quality claims are removed. Separate Arabic reasons distinguish unavailable links from conflicting attribution. A prior download stays on disk and is included in storage accounting, but is not treated as a verified playable recording. Explicit deletion remains available through existing download management.

No native resolver, schedule, reminder time, saved selection, sound resource, Android manifest, permission, signing setting, workflow, or release artifact is changed. Already stored unsupported choices continue to load unchanged. Their old native fallback behavior is NOT fixed by this patch and remains a separate decision and implementation task. The message about preserved reminder times does not certify their selected audible voice.

The older Hazza containment remains in force. This review does not certify the rest of the catalog. Other country-only or Fajr-variant sources need their own identity/content review, especially entries whose names assert a particular sheikh or mosque. Existing supported native keys are deliberately not added to this containment set because that could affect audible reminder behavior under a separate pending decision.

## Validation

- New source/cache regressions fail on the pre-patch service, then pass on the patch.
- 112 local tests across 14 files passed, including all ten stored-ID preservation and new-setter rejection checks.
- Analyzer clean for four changed source/test files.
- Actual Cairo-font 320px, 2x text screenshot inspected: full conflicting-source warning and preserved-reminder-times message readable; all three affected actions disabled.
- Actual device notification playback, screen-reader traversal, backup/restore, and perceptual audio quality remain unverified.
