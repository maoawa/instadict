# Watch dictionary lookup benchmark

Run: 20260914T170418Z. Host: Apple M5. Version 27.0 (Build 24R362).

**Environment: watchOS simulator on Mac hardware, not a physical Apple Watch.**
The physical Series 7 was unavailable; simulator use was explicitly requested. Absolute timings and memory figures do not predict Series 7 behavior.

All formats contain 768,739 entries. 3,366 comparisons confirmed identical entries, aliases and suggestions against the shipping reader.
Release `-O` / whole-module optimization, without a debugger. Three fresh processes per format, with rotated format order; three passes per workload in each process. The current per-entry format uses the unmodified production `DictionaryStore`.
Each measurement includes normalization, a fresh read-only SQLite connection, SQL, decompression if needed, decoding one JSON entry, presentation cleanup, and connection close. It excludes rendering, keyboard input, transfers and app startup. No application block cache is used. OS caches are uncontrolled and were warmed by validation; these are not cold-storage benchmarks.

| Format | Installed MiB | Random median / p95 (ms) | Repeated median / p95 (ms) |
| --- | ---: | ---: | ---: |
| Uncompressed JSON | 239.35 | 0.165 / 0.190 | 0.175 / 0.222 |
| Current: zlib per entry | 181.18 | 0.167 / 0.208 | 0.175 / 0.198 |
| zlib per 128-entry block | 51.82 | 0.188 / 0.210 | 0.195 / 0.234 |

Random and repeated figures each pool 4,608 lookups per format. Full samples and auxiliary workloads are in the JSON files.

## Memory observations

| Format | Observed process footprint range across trials (MiB) |
| --- | ---: |
| Uncompressed JSON | 13.05–13.28 |
| Current: zlib per entry | 13.06–13.25 |
| zlib per 128-entry block | 13.19–13.27 |

Footprint is sampled after each lookup, outside the timed interval. It includes framework/runtime memory and may miss short-lived allocations; it is not a guaranteed peak or a Watch RAM measurement.
The largest raw block is 45,468 bytes. Byte offsets select just the requested entry for JSON decoding. This adds about 3 MiB of indexing compared with the earlier 49 MiB array-position prototype.

Thermal state codes across runs: [0] (0 = nominal).

## Scope

Benchmark code and fixtures are isolated from the shipping app. The production dictionaries and reader have not been switched to block compression. Measure on a physical Watch before making a final latency, memory or battery claim.
