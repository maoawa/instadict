#!/usr/bin/env python3
"""Run balanced Release benchmark trials in fresh Watch simulator processes."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
BUNDLE='com.candyrect.instadict.benchmark'


def command(*args):
    return subprocess.check_output(args,text=True).strip()


def run(device):
    app=ROOT/'build-benchmark/DerivedData/Build/Products/Release-watchsimulator/WatchBenchmark.app'
    fixtures=ROOT/'build-benchmark/Fixtures'
    manifest=json.loads((fixtures/'queries.json').read_text())
    for name,info in manifest['files'].items():
        with (fixtures/f'{name}.sqlite').open('rb') as f:
            assert hashlib.file_digest(f,'sha256').hexdigest()==info['sha256']
    command('xcrun','simctl','install',device,str(app))
    container=Path(command('xcrun','simctl','get_app_container',device,BUNDLE,'data'))
    destination=container/'Documents'/'Fixtures'
    shutil.copytree(fixtures,destination,dirs_exist_ok=True)
    results=container/'Documents'/'Results'
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output=ROOT/'Benchmarks'/'Results'/stamp
    output.mkdir(parents=True,exist_ok=True)
    host={'timestampUTC':stamp,'simulatorID':device,'hostSystem':platform.platform(),
          'cpu':command('sysctl','-n','machdep.cpu.brand_string'),
          'xcode':command('xcodebuild','-version'),'fixtureManifest':manifest}
    (output/'environment.json').write_text(json.dumps(host,indent=2)+'\n')

    def launch(arguments,filename,timeout=120):
        result=results/filename
        result.unlink(missing_ok=True)
        print('Launching',arguments,flush=True)
        command('xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,*arguments)
        deadline=time.monotonic()+timeout
        while not result.exists():
            if time.monotonic()>deadline:
                raise TimeoutError(f'Benchmark did not write {result}. Check simulator app for an error.')
            time.sleep(0.25)
        shutil.copyfile(result,output/filename)
        print('Saved',filename,flush=True)

    launch(['--validate-only'],'validation.json')
    formats=['uncompressed','per-entry','blocks-128']
    for trial in range(3):
        # Rotate the format order to reduce systematic cache/host-load bias.
        for format in formats[trial:]+formats[:trial]:
            run_id=f'trial-{trial+1}'
            launch(['--format',format,'--run-id',run_id],f'{run_id}-{format}.json')
    command('xcrun','simctl','terminate',device,BUNDLE)
    print('Results:',output,flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--device',required=True,help='Booted watchOS simulator UDID')
    run(parser.parse_args().device)
