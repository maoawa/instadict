#!/usr/bin/env python3
"""Summarize raw simulator measurements without treating them as hardware results."""
import argparse
import json
import math
from pathlib import Path
import statistics


def summarize(root):
    environment=json.loads((root/'environment.json').read_text())
    reports=[json.loads(p.read_text()) for p in sorted(root.glob('trial-*.json'))]
    assert len(reports)==9
    assert len({p['sourceSHA256'] for p in reports})==1
    assert len({p['checksum'] for p in reports})==1
    validation=json.loads((root/'validation.json').read_text())
    grouped={}
    for report in reports:
        for result in report['results']:
            grouped.setdefault((report['format'],result['workload']),[]).extend(result['samplesMS'])
    def percentile(values,q):
        values=sorted(values)
        return values[max(0,math.ceil(len(values)*q)-1)]
    summary={}
    for (format,workload),values in grouped.items():
        summary.setdefault(format,{})[workload]={'samples':len(values),'medianMS':statistics.median(values),'p95MS':percentile(values,.95),'p99MS':percentile(values,.99),'maxMS':max(values)}
    lines=['# Watch dictionary lookup benchmark','',
           f"Run: {environment['timestampUTC']}. Host: {environment['cpu']}. {reports[0]['os']}.",'',
           '**Environment: watchOS simulator on Mac hardware, not a physical Apple Watch.**',
           'The physical Series 7 was unavailable; simulator use was explicitly requested. Absolute timings and memory figures do not predict Series 7 behavior.','',
           f"All formats contain {reports[0]['entries']:,} entries. {validation['validatedLookups']:,} comparisons confirmed identical entries, aliases and suggestions against the shipping reader.",
           'Release `-O` / whole-module optimization, without a debugger. Three fresh processes per format, with rotated format order; three passes per workload in each process. The current per-entry format uses the unmodified production `DictionaryStore`.',
           'Each measurement includes normalization, a fresh read-only SQLite connection, SQL, decompression if needed, decoding one JSON entry, presentation cleanup, and connection close. It excludes rendering, keyboard input, transfers and app startup. No application block cache is used. OS caches are uncontrolled and were warmed by validation; these are not cold-storage benchmarks.','',
           '| Format | Installed MiB | Random median / p95 (ms) | Repeated median / p95 (ms) |',
           '| --- | ---: | ---: | ---: |']
    names={'uncompressed':'Uncompressed JSON','per-entry':'Current: zlib per entry','blocks-128':'zlib per 128-entry block'}
    for format in ['uncompressed','per-entry','blocks-128']:
        report=next(p for p in reports if p['format']==format)
        r=summary[format]['random'];w=summary[format]['repeated']
        lines.append(f"| {names[format]} | {report['fileBytes']/1024**2:.2f} | {r['medianMS']:.3f} / {r['p95MS']:.3f} | {w['medianMS']:.3f} / {w['p95MS']:.3f} |")
    lines+=['',f"Random and repeated figures each pool {summary['per-entry']['random']['samples']:,} lookups per format. Full samples and auxiliary workloads are in the JSON files.",'',
            '## Memory observations','',
            '| Format | Observed process footprint range across trials (MiB) |',
            '| --- | ---: |']
    for format in ['uncompressed','per-entry','blocks-128']:
        memory=[p['footprintObservedMaxBytes']/1024**2 for p in reports if p['format']==format]
        lines.append(f"| {names[format]} | {min(memory):.2f}–{max(memory):.2f} |")
    lines+=['','Footprint is sampled after each lookup, outside the timed interval. It includes framework/runtime memory and may miss short-lived allocations; it is not a guaranteed peak or a Watch RAM measurement.',
            f"The largest raw block is {reports[0]['largestBlockBytes']:,} bytes. Byte offsets select just the requested entry for JSON decoding. This adds about 3 MiB of indexing compared with the earlier 49 MiB array-position prototype.",'',
            f"Thermal state codes across runs: {sorted({p[k] for p in reports for k in ['thermalStart','thermalEnd']})} (0 = nominal).",'',
            '## Scope','',
            'Benchmark code and fixtures are isolated from the shipping app. The production dictionaries and reader have not been switched to block compression. Measure on a physical Watch before making a final latency, memory or battery claim.','']
    (root/'Report.md').write_text('\n'.join(lines))
    (root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('\n'.join(lines))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    summarize(parser.parse_args().directory)
