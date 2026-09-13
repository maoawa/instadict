# InstaDict

An offline Apple Watch dictionary with an iPhone companion for downloading and
managing dictionary packs. **Neither app bundles a dictionary database.** Download
on iPhone, send to Watch, and look up words offline after installation.

Open `InstaDict.xcodeproj` and run the shared **InstaDict** scheme on iPhone.
It builds and embeds the Watch app. Use **InstaDict**, with an iOS device destination,
when archiving for App Store distribution. The Watch scheme is for Watch development.

Bundle IDs remain `com.candyrect.instadict` (iPhone) and
`com.candyrect.instadict.watch` (Watch). The Watch declares its iPhone companion and
requires it for initial dictionary setup; after setup, lookups work without the phone.

## Publish the downloads

The upload-ready files are in `Distribution/Dictionaries`, outside both Xcode app
targets. Follow `Distribution/Dictionaries/UPLOAD.md` and publish them under:

```
https://fastcdn.candyrect.com/instadict/
```

| Dictionary | Headwords | Approximate size |
| --- | ---: | ---: |
| English–English | 235,716 | 66 MiB |
| English–Chinese | 231,752 | 58 MiB |
| Chinese–English | 121,293 | 30 MiB |

The English packs separate the existing dictionary's definitions by language.
Chinese–English uses CC-CEDICT, rather than reversed translation fragments, and
supports traditional spelling aliases and numbered pinyin. Counts exclude aliases.
Missing pronunciations are omitted. Dictionary sources and full license notices
are shown on iPhone before/during download; the Watch has no sources button.
Licenses also travel inside every SQLite pack's metadata.

Upload `manifest.json` last, after the three versioned `.sqlite` files. The small
initial catalog is bundled in the apps; the iPhone refresh button reads the remote
manifest to discover updates. Dictionaries are data files with an InstaDict schema,
not arbitrary third-party SQLite files. The current schema is version 2.

Build the packs with Python's standard library:

```sh
python3 Tools/build_dictionary.py --version 2026.09.14
```

Raw inputs are cached in ignored `.dictionary-sources`. The ECDICT, WordNet and
American IPA revisions are pinned in `Tools/dictionary_sources.py`. CC-CEDICT's
cached dated snapshot and SHA-256 are recorded in the Chinese pack's provenance.
For a future CC-CEDICT refresh, replace its cached source deliberately, then use a
new pack version. `--base-url` changes generated URLs, but changing the CDN host also
requires updating the app's catalog URL and URL validation policy.

## iPhone behavior

- Three independent dictionary cards, with size, entry count and source notices.
- Download & send, cancel/retry, catalog refresh and update downloads.
- Background URLSession downloads; task restoration and recovery of completed
  downloads awaiting verification after process interruption.
- Verification of file length, SHA-256, SQLite integrity, schema, pack identity,
  version, entry count and a decoded entry before installation.
- Downloaded and installed-on-Watch states are separate. Queued transfer completion
  is not presented as a successful Watch installation until the Watch acknowledges it.
- Manage menu removes the iPhone copy, Watch copy, or both. Removing the phone copy
  preserves the Watch copy and uses an independent snapshot for transfers in flight.
- No server upload, analytics, accounts or dictionary search API.

## Watch behavior

Before the first pack arrives, a short guide explains iPhone setup. Afterwards,
opening the app presents native word entry. English input defaults to English–English;
**中 / EN** switches the same query between installed English packs. Chinese input
selects Chinese–English automatically. A missing pack offers iPhone setup guidance.

The lower-right pencil opens fresh input. Cancel or submit blank input to retain
the definition. Lookup normalizes Watch-added trailing spaces, leading/Unicode
whitespace, capitalization, curly apostrophes and repeated spaces inside phrases.
Pronunciations, examples and word forms are shown when present; missing IPA rows
are hidden. Wrist-down/inactive transitions do not reopen the keyboard.

WatchConnectivity stages incoming files before its temporary URL expires, validates
them on a dedicated actor, and atomically activates immutable versioned files in
Application Support. Persistent per-pack command revisions make removals and newer
transfers win over stale deliveries. Failed updates preserve the previous pack.
Downloaded files are excluded from iCloud backup. The Watch app handles background
WatchConnectivity tasks and sends installed-pack receipts back to iPhone.

watchOS controls keyboard/Scribble/dictation availability. Typed lookups remain
offline after installation; dictation's availability is controlled by watchOS.

## Validation

Generated dictionary databases and source archives are excluded from Git. On a
fresh clone, run `python3 Tools/build_dictionary.py --version 2026.09.14` before
running the pack tests below. Building and launching the apps does not require
local dictionary databases.

```sh
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
missing language packs, English reset and latest-request-wins behavior.

Before release, publish the files and test a paired physical iPhone/Watch:
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
