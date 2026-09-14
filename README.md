# InstaDict

An offline dictionary for Apple Watch and iPhone. Open the app and start typing.
**Neither app bundles a dictionary database.** Download directly on either device,
or download on iPhone and send to Watch, then look up words offline.

Open `InstaDict.xcodeproj` and run the shared **InstaDict** scheme on iPhone.
It builds and embeds the Watch app. Use **InstaDict**, with an iOS device destination,
when archiving for App Store distribution. The Watch scheme is for Watch development.

Bundle IDs remain `com.candyrect.instadict` (iPhone) and
`com.candyrect.instadict.watch` (Watch). The Watch declares its iPhone companion but
can run independently, including initial dictionary downloads.

## Publish the downloads

The upload-ready files are in `Distribution/Dictionaries`, outside both Xcode app
targets. Follow `Distribution/Dictionaries/UPLOAD.md` and publish them under:

```
https://fastcdn.candyrect.com/instadict/
```

The default source uses the CDN above. Cloudflare R2 (`instadict-dictionaries`)
remains an optional mirror at `instadict.marsinside.com`; see `Cloudflare/README.md`.
Manifest pack URLs are relative filenames, so the same seven files work in any HTTPS folder.

| Dictionary | Headwords | Approximate size |
| --- | ---: | ---: |
| English–English | 235,717 | 23.5 MiB |
| English–Chinese | 768,739 | 51.8 MiB |
| Chinese–English | 121,293 | 9.9 MiB |

The English packs select nonempty definitions independently by language, so
Chinese-only source entries are included in English–Chinese.
Chinese–English uses CC-CEDICT, rather than reversed translation fragments, and
supports traditional spelling aliases and pinyin displayed in lowercase with tone
marks, including pronunciations in definition references. Counts exclude aliases.
Missing pronunciations are omitted. Dictionary sources and full license notices
are shown on iPhone before/during download; the Watch has no sources button.
Licenses also travel inside every SQLite pack's metadata.

Upload `manifest.json` last, after the three versioned `.sqlite` files. The small
initial catalog is bundled in the apps; the iPhone refresh button reads the remote
manifest to discover updates. Dictionaries are data files with an InstaDict schema,
not arbitrary third-party SQLite files. New packs use schema version 3, with
lossless zlib compression in groups of up to 128 entries. These are the installed
sizes too: installation copies the compressed SQLite file directly. A lookup
inflates one group and uses byte offsets to decode only the requested entry.
The reader still supports older schema-2 packs. Normal blocks target at most
128 KiB uncompressed; a larger individual entry may occupy its own block, with
an absolute 2,000,000-byte limit checked before allocation.

Build the packs with Python's standard library:

```sh
python3 Tools/build_dictionary.py --version 2026.09.14
```

Raw inputs are cached in ignored `.dictionary-sources`. The ECDICT, WordNet and
American IPA revisions are pinned in `Tools/dictionary_sources.py`. CC-CEDICT's
cached dated snapshot and SHA-256 are recorded in the Chinese pack's provenance.
For a future CC-CEDICT refresh, replace its cached source deliberately, then use a
new pack version. The builder emits relative filenames by default; `--base-url` can
optionally produce absolute URLs. **Settings → Download source** on iPhone (under
**Manage dictionaries** on Watch) accepts a bare website/folder such as
`example.com/dictionaries`, or an HTTPS catalog URL. HTTPS and `manifest.json` are
added automatically for folder input. It checks the catalog before saving, persists the source and catalog
together, and keeps the previous source if validation fails. Relative SQLite URLs
are resolved against the fetched manifest URL. All packs still require compatible
schemas, sizes, SHA-256 checksums and valid databases. Source changes wait for active
downloads to finish. **Use default source** checks and restores the default CDN catalog. Its endpoint is displayed only as
**Default source** in the interface. Previous built-in R2 selections migrate to the
new default; explicitly saved custom selections retain their source.
The original CC-CEDICT archive stays in the build cache and is not part of the
upload set; the packs retain source links, attribution, licenses and provenance.

Version `2026.09.14` corrects `personalise` phonetics, replaces the malformed
`hentai` commentary with a dictionary definition, and supplies the missing English
`multimeter` entry. Reviewed corrections and their reasons live in
`Tools/dictionary_corrections.json` and are recorded in pack provenance. Unknown
corrupt phonetics are omitted. Literal source line-break escapes are cleaned and
empty senses discarded. The expanded English–Chinese pack includes translations
previously excluded by the English-content selection rule.
The internal TestFlight build number is now 8 (app version 0.5). Install this
updated iPhone/Watch app before testing the new packs. Filenames retain
`2026.09.14` as requested; replace the CDN files and manifest together, clear stale
CDN copies, then refresh the iPhone catalog and download/send the packs again.
For the default source, an app upgrade prefers the bundled schema-3 catalog over a
cached schema-2 catalog. Custom catalogs are kept separate from the bundled catalog.

## iPhone behavior

- Opens to word entry with the keyboard focused. English and Chinese lookup,
  language switching, pronunciation, examples, suggestions and word-form links
  share the Watch's dictionary engine and definition view.
- Settings contains dictionary management and custom download-source selection.
- Three independent dictionary cards, with size, entry count and source notices.
- Downloads install locally without automatically sending to Watch. A downloaded
  pack can be sent when missing on Watch. Once installed there, **Send to Watch
  again** lives in the card's upper-right menu, alongside removal options.
- Cancel/retry, catalog refresh and update downloads.
- Background URLSession downloads; task restoration and recovery of completed
  downloads awaiting verification after process interruption.
- Verification of file length, SHA-256, SQLite integrity, schema, pack identity,
  version, entry count and a decoded entry before installation.
- Downloaded and installed-on-Watch states are separate. Queued transfer completion
  is not presented as a successful Watch installation until the Watch acknowledges it.
- Manage menu removes the iPhone copy, Watch copy, or both. Removing the phone copy
  preserves the Watch copy and uses an independent snapshot for transfers in flight.
- No server upload, analytics, accounts or dictionary search API.

Both devices use native bottom toolbars for the new-word button and optional Watch
settings button. iPhone circular controls use the theme tint. iPhone definition text
is larger, and British/American pronunciations share a row when they fit, falling
back to separate rows when needed. Word forms and base forms have green section dividers.
**Settings → Pronunciation order** saves British-first or American-first independently
on each device. **Show tutorial again** at the bottom of Settings replays the guide
without resetting onboarding, dictionary installations or the current lookup.

## Interface language

On both devices, **Settings → App language** selects English or Simplified Chinese.
The first launch uses the primary device language's language code: all `en` variants
use English; all `zh` variants (including `zh-TW`, `zh-HK` and `zh-Hant`) use Simplified
Chinese. Any other primary language falls back to English, even when Chinese appears
farther down the device's language list. Traditional Chinese UI is not included.

The initial choice and later changes are saved independently on each device. Changes
apply immediately, including inside Settings. **Use device language** reapplies the
current device-language default. UI language does not select a different dictionary
or translate its definitions, example sentences, word forms, phonetic text or licenses.
Pronunciation region labels, grammatical labels and word-form labels are localized
at display time (for example, US/UK → 美/英 and past tense → 过去式).

Translations are shared in `Shared/Resources/Localizations/{en,zh-Hans}.lproj`.
SwiftUI receives the selected locale, while dynamic messages use `L10n`. Persisted
and transferred statuses remain canonical, allowing iPhone and Watch to display the
same status in different languages. Localization tests cover regional variants,
fallback, persistence, grammatical labels, status messages and placeholder parity.

## Watch behavior

Before the first pack arrives, a short guide explains direct or iPhone setup. Afterwards,
opening the app presents native word entry. English input defaults to English–English;
**中 / EN** switches the same query between installed English packs. Chinese input
selects Chinese–English automatically. A missing pack offers Settings/download guidance.

Swipe left on a definition to open Settings. **Open settings** can instead select a
lower-left button; the choice persists on the Watch. Settings is also available
from setup and non-definition screens. **Manage dictionaries** supports direct
HTTPS background downloads, progress, cancellation, verified installation, removal,
catalog refresh and a custom source. The Watch handles URLSession background wakeups.
Direct downloads and removals use the same ordered commands as iPhone transfers,
so a late file cannot undo a newer action on either device.

The lower-right pencil opens fresh input. Cancel or submit blank input to retain
the definition. Lookup normalizes Watch-added trailing spaces, leading/Unicode
whitespace, capitalization, curly apostrophes and repeated spaces inside phrases.
Pronunciations, examples and word forms are shown when present; “Also” synonym lines
are italic. Missing IPA rows
are hidden. WordNet examples are shared by synonyms; the Watch shows only examples
containing the headword, query, base form or a listed inflection, and bolds those
whole-word matches. Pinyin and escape cleanup also apply to older installed packs;
corrected dictionary content requires downloading and sending the new packs.
Wrist-down/inactive transitions do not reopen the keyboard.

WatchConnectivity stages incoming files before its temporary URL expires, validates
them on a dedicated actor, and atomically activates immutable versioned files in
Application Support. Persistent per-pack command revisions make removals and newer
transfers win over stale deliveries. Failed updates preserve the previous pack.
Downloaded files are excluded from iCloud backup. The Watch app handles background
WatchConnectivity tasks and sends installed-pack receipts back to iPhone.
Connectivity starts from both app delegates for background launches. When the
Watch app is reachable, iPhone also requests a fresh inventory directly; use
**Check Watch status** on a pending dictionary to retry that check. A received
command is not treated as an installed dictionary, and Watch setup displays
installation errors. Reachability describes live messaging; a sleeping/unreachable
Watch can still receive background file transfers. The iPhone message therefore
does not claim that transfers have stopped when reachability changes.
Transfer revisions use explicit 64-bit integers because epoch milliseconds do
not fit the 32-bit `Int` used by arm64_32 Watch hardware.

watchOS controls keyboard/Scribble/dictation availability. Typed lookups remain
offline after installation; dictation's availability is controlled by watchOS.

## Validation

Generated dictionary databases and source archives are excluded from Git. On a
fresh clone, run `python3 Tools/build_dictionary.py --version 2026.09.14` before
running the pack tests below. Building and launching the apps does not require
local dictionary databases.

```sh
python3 Tools/test_dictionary_sources.py
python3 Tools/test_dictionary_blocks.py
python3 Tools/verify_dictionary_blocks.py
swift test
xcodebuild -project InstaDict.xcodeproj -scheme InstaDict \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-companion CODE_SIGNING_ALLOWED=NO build
xcodebuild -project InstaDict.xcodeproj -scheme InstaDict \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build-companion/InstaDict.xcarchive \
  -derivedDataPath build-companion-device CODE_SIGNING_ALLOWED=NO archive
```

Core tests check every upload against its manifest, all three lookup directions,
traditional aliases, trailing spaces, typo suggestions, SQL binding, catalog
validation, receipt persistence, failed updates, stale transfers after removal,
missing language packs, English reset and latest-request-wins behavior. Formatting
regressions cover numbered pinyin, embedded references, literal carriage returns,
whole-word example matching, and the reported corrected entries.
Block tests also check UTF-8 byte offsets, legacy compatibility, invalid block
references, corruption, 64-bit offset overflow, and installation without expansion.
For a lossless rebuild comparison, pass a folder containing prior packs and the
same filenames to `Tools/verify_dictionary_blocks.py --baseline FOLDER`; it checks
every entry, rank and alias. The simulator compression benchmark and repeatable
runner are in `Benchmarks`, outside the shipping app targets.
`Tools/AppSmoke` builds separate simulator apps named **Dict Smoke** around the production downloader to
exercise live catalog changes, failure preservation, direct downloads, installation
and lookup after relaunch. These test apps are not included in InstaDict or TestFlight.

The seven distribution files are published and verified at the R2 custom domain.
The compressed packs were also tested by the user on a physical Watch, with results
appearing almost instantly and no noticeable delay. For the new settings/download
flows, test a paired physical iPhone/Watch before release:
background download, send while disconnected, installation acknowledgment, cancel,
removal, interrupted update, reconnect, and offline lookup in all three directions.
Simulator UI previews and disk-install tests do not establish real-device
WatchConnectivity delivery. Downloaded content still occupies device storage, but
it is outside the App Store's submitted Watch app bundle.

## License

Copyright © 2026 Mars (maao.cc).

Original project code and assets are licensed under
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International](LICENSE)
(CC BY-NC-SA 4.0).

Third-party dictionary data and associated notices retain their respective
licenses; the project license does not replace them. In particular, the
CC-CEDICT-derived Chinese–English pack remains under CC BY-SA 4.0. See the
source notices in `InstaDict iOS App/Resources` and `Distribution/Dictionaries`.
