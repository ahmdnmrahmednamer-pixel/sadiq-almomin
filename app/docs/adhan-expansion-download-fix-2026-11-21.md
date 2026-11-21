# Adhan catalog expansion and safe download publication

## Additional source-linked voices,09:24 review

Two new catalog IDs are available for streaming preview and explicit offline download only. Existing native-assignment guard explains that these voices cannot yet be assigned to scheduled adhan. No recording binary is bundled, mirrored or modified in the app. Existing prayer IDs, choices, notification channels and reminder times are untouched.

| New catalog ID | Source catalog attribution | Source page | Duration | MP3 format | Bytes | SHA-256 |
| --- | --- | --- | --- | --- | --- | --- |
| `adhan_jamal_aljaafari` | جمال عبد الحميد الجعفرى أذان | https://audio.islamweb.net/audio/info/416974 | 163.268000s | 128000bits/s,16000Hz,1channel(s) | 2680899 | `ba5f7c400cbfeb9f4b94a1cb184191437cd5cda3fe90fa3f0299c1bac6c83522` |
| `adhan_ihsan_aldulaimi` | إحسان حميد الدليمي أذان | https://audio.islamweb.net/audio/info/421877 | 213.271687s | 128000bits/s,44100Hz,2channel(s) | 3481306 | `5b5debea2f3d6e2a000bcb34fd1740b307794d80a477b0181fbf776b55bea8c3` |

Both original files initially produced no recognized speech. One temporary analysis copy per candidate, with leading-silence trim and1.3x tempo, produced all adhan phrases including the opening four takbirs and closing declaration. Analysis copies are not app downloads. Complete words plus catalog attribution are not independent speaker authentication or permission to redistribute. Format metadata is not a subjective listening-quality or HD guarantee. A third candidate attributed to Issa al-Hajlawi was not added: its analysis transcript did not establish all opening takbirs, and its measured decoded signal exceeded full scale. No repeated recognition loops were used to force acceptance.

### Download correctness regression repair

Unknown catalog IDs previously fell back to the first recording and wrote it under the requested, wrong ID. They now fail before any network request. Completed files of1000bytes or less previously returned success and could replace an existing valid copy, despite immediately failing the service's own downloaded-file rule. They are now rejected before publication, retaining old bytes and clearing attempt state. This is a minimum size/eligibility check, not MP3 decoding, checksum verification or protection from every non-audio response.

Three new regression cases failed against the old implementation and pass after the repair. Existing cancel/retry coverage now uses actual catalog ID `adhan_cairo_refaat`; its old `adhan_cairo` test input had only passed via the wrong-recording fallback. The native `adhan_cairo` alias and persisted choices were not changed.

Targeted validation:82 tests across10 audio/source/control files pass; analyzer clean for4 changed Dart files. Actual Cairo320px/2x screenshots of both new long names were inspected: warnings wrap, disabled assignment is clear, listen/download remain independently usable. Native scheduled playback and device TalkBack remain unverified. An initial compiler disk-capacity failure occurred before image-test assertions; only disposable generated build/compiler caches were removed and the test was rerun successfully.
