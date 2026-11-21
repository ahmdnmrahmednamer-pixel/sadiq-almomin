# Journal golden references

This test compares exact pixels. It does not use a pixel tolerance or skip unsupported hosts.

- Windows uses the original `part_a_compact.png` and `part_b_compact.png` in this folder. They remain unchanged from commit `2ca79502d1ee4a14126544f141afae748b2aaa9d`.
- Linux uses the separate files in `linux/`. These were inspected beside the original Windows references before being proposed. Their layout, full Arabic error messages, preserved input, error placement above Save, and visible Save button were checked in both failure states.
- Other host operating systems fail with an explicit unsupported-reference error. Add another host only after reviewing its actual pixels. Do not copy a baseline automatically or silently fall back to another host.

The selector uses `Platform.operatingSystem`, which identifies the test host. It does not use Flutter's emulated target platform.

## Evidence for separate references

The unchanged journal test passed against both original goldens on Windows 10 Pro build 19045, Flutter 3.47.7, engine `deb287481e3ce9468f3434937ced4240a70539ca`, Dart 3.13.5. This was a single-test renderer control on the older local application tree, not a full current-app Windows audit. The relevant journal screen, test and theme matched the current content after normalizing line endings. Fonts and golden PNGs matched byte for byte. The original dependency lock remained in place.

Linux Flutter 3.47.7 and 3.50.0 produced identical actual PNG bytes for the two states. Against the Windows references, state A differed at 31,487 pixels (3.28%) and state B at 28,030 pixels (2.92%). The observed difference is concentrated at text edges. These controls support host-renderer sensitivity; they do not identify a specific rasterizer implementation as the cause.

Linux references:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `linux/part_a_compact.png` | 129797 | `1ff24e37b8febf486703f1d842cd1caf1459b3ec9166a83d89e23db941d4f8a4` |
| `linux/part_b_compact.png` | 115938 | `29f5796343d76b6083cbd43d65390cabfb81a64a5c2076367b829c0b973b6e74` |

The existing fixtures load Cairo and Amiri, with Cairo also loaded under the Roboto name. They do not load MaterialIcons. Both original and Linux references therefore contain missing-icon boxes. These fixtures check the save-failure layout and text, not production icon fidelity or native accessibility. No production icon change is implied or approved by these references.

The widget test's existing behavioral assertions remain in force: unreadable data refuses saving, failed persistence keeps the sheet open and typed input intact, each exact Arabic error is inside the sheet, and confirmed persistence closes the sheet. Native screen-reader announcements and physical-device interaction remain separate checks.

## November 21, 2026: approved decorative leaf removal

PR62 removed the decorative leaf from the add-sheet title. Only30pixels per Linux image changed: the old fixture rendered that leaf as a missing-glyph mark. Both complete images were inspected, with input, full error text, layout and Save unchanged. The two Linux references above now match the approved title. No production code, test assertion, pixel tolerance or host selector changed.

Causal controls: restoring the leaf against the old references passed; restoring it against these updated references failed the strict comparison at exactly30pixels in each state. Returning to the approved leaf-free title passed all4journal tests. Windows originals remain byte-identical and were not re-rendered for this title change. The historical Windows pass above does not establish a current-revision Windows pass; that host still needs its own reviewed reference alignment.
