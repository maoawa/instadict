# Live download smoke tests

These are separate simulator apps that compile the production downloader, library
and sync code. They do not change the shipping targets. They use the public R2
catalog and download the 9.9 MiB Chinese–English dictionary into their own sandbox.
No test dictionary is uploaded.

Generate/build the Watch harness:

```sh
python3 Tools/AppSmoke/make_project.py watch
xcodebuild -project build-smoke/watch/DictionarySmoke.xcodeproj \
  -scheme DictionarySmoke -configuration Release \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build-smoke/watch/DerivedData build
```

For iPhone use `phone`, `platform=iOS Simulator` and `build-smoke/phone` instead.
Install the generated `DictionarySmoke.app` from `DerivedData/Build/Products` with
`xcrun simctl install DEVICE_ID APP_PATH`, then launch
`com.candyrect.instadict.smoke.watch` (or `.phone`) using `xcrun simctl launch`.

The harness checks the default catalog, switches to the managed R2 source, checks
that an HTTP 404 preserves the working source/catalog, then downloads, validates,
installs and looks up 中文. It verifies that direct Watch installation records a
completed command, and that iPhone installation does not automatically send a file.

Read `Documents/smoke.json` in the container returned by
`xcrun simctl get_app_container DEVICE_ID BUNDLE_ID data`. Once `passed` is true,
save that report and launch again with `--terminate-running-process` and the
`--relaunch` app argument. The second run checks source persistence and lookup of
the installed dictionary without fetching it again. It replaces `smoke.json`.

Both platforms passed the live download and relaunch checks on 2026-09-15. Reports
from this run are in ignored `build-smoke/{watch,phone}/{download,relaunch}-result.json`.
These tests do not establish physical-device background scheduling or gesture/keyboard
behavior; those need testing in the shipping app.
