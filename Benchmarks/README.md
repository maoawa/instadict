# Dictionary lookup benchmark

A separate Watch app compares the full English–Chinese vocabulary in three formats:
raw JSON in SQLite, the legacy zlib-per-entry format, and zlib blocks of
128 adjacent entries. The block index includes byte offsets and lengths so only
one entry is JSON-decoded. Fixtures live in ignored `build-benchmark/Fixtures`;
none are included in the shipping app or its CDN catalog.
The shipping reader now supports schema 3 block compression as well as schema 2.
Fixture generation accepts either source format and reconstructs the per-entry
baseline. Reports already saved under `Results` describe the code at that run's date.

Prepare and run against a **booted watchOS simulator**:

```sh
python3 Benchmarks/build_fixtures.py
python3 Benchmarks/make_project.py
xcodebuild -project Benchmarks/WatchBenchmark.xcodeproj -scheme WatchBenchmark \
  -configuration Release -destination 'platform=watchOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath build-benchmark/DerivedData CODE_SIGNING_ALLOWED=NO build
python3 Benchmarks/run_simulator.py --device SIMULATOR_UDID
python3 Benchmarks/summarize.py Benchmarks/Results/RESULT_TIMESTAMP
```

Use `xcrun simctl list devices` for the simulator UDID. The runner first compares
all fixture queries against the production reader, including entire decoded entries
and suggestions. It then starts each format in a fresh process three times, rotating
format order. Each trial performs three passes of seeded random, repeated, alias,
missing-word and typo workloads. Reports include raw timings and source checksums.

The measured interval includes query normalization, opening SQLite, SQL, decoding,
presentation formatting and closing SQLite. There is no app-level cache; each lookup
gets the same 256 KiB SQLite cache limit used by production. OS page caches cannot
be reliably purged on Watch and are warmed by correctness validation. These are
warm-file-cache comparisons, not disk-cold measurements. Simulator measurements
run on the Mac CPU and must never be reported as physical Watch measurements.

`BenchmarkStore.swift` is derived from the production reader, with only its record
retrieval adapted for the experimental formats. The timed current-format baseline
uses `Shared/DictionaryStore.swift` directly. If production lookup behavior changes,
update the experimental reader and rerun the correctness comparison.

The benchmark app has its own bundle ID, `com.candyrect.instadict.benchmark`.
It uses `Documents/Fixtures` and writes `Documents/Results`; it does not access the
installed InstaDict dictionaries. After experimenting, the benchmark app can be
uninstalled to reclaim the fixture space.

For a physical Watch, build the same Release target with development signing,
install it, copy `Fixtures` into its Documents directory, and launch with either
`--validate-only` or `--format blocks-128 --run-id trial-1` (also `uncompressed` and
`per-entry`). Retrieve the JSON results from Documents/Results. Keep foreground and
thermal conditions consistent, rotate format order, and do not attach a debugger.
Physical execution has not been established by a simulator run.
