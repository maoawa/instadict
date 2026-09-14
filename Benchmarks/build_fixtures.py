#!/usr/bin/env python3
"""Build lossless, full-vocabulary fixtures outside the shipping app targets."""
import hashlib
import json
from pathlib import Path
import random
import sqlite3
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build-benchmark' / 'Fixtures'
sys.path.insert(0, str(ROOT / 'Tools'))
from verify_dictionary_blocks import entries as source_entries


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((ROOT / 'Distribution/Dictionaries/manifest.json').read_text())
    pack = next(p for p in catalog['packs'] if p['id'] == 'english-chinese')
    source = ROOT / 'Distribution/Dictionaries' / pack['url'].rsplit('/', 1)[-1]
    original = sqlite3.connect(f'file:{source}?mode=ro', uri=True)
    dbs = {}
    for name in ['uncompressed', 'per-entry', 'blocks-128']:
        path = OUTPUT / f'{name}.sqlite'
        path.unlink(missing_ok=True)
        db = sqlite3.connect(path)
        db.executescript('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; CREATE TABLE aliases(alias TEXT,word TEXT,PRIMARY KEY(alias,word)) WITHOUT ROWID; CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT) WITHOUT ROWID;')
        if name != 'blocks-128':
            db.execute('CREATE TABLE entries(word TEXT PRIMARY KEY,rank INTEGER NOT NULL,payload BLOB NOT NULL,payload_size INTEGER NOT NULL) WITHOUT ROWID')
        else:
            db.executescript('CREATE TABLE entries(word TEXT PRIMARY KEY,rank INTEGER NOT NULL,block_id INTEGER NOT NULL,byte_offset INTEGER NOT NULL,payload_size INTEGER NOT NULL) WITHOUT ROWID; CREATE TABLE blocks(id INTEGER PRIMARY KEY,payload BLOB NOT NULL,payload_size INTEGER NOT NULL);')
        db.executemany('INSERT INTO aliases VALUES(?,?)', original.execute('SELECT alias,word FROM aliases'))
        db.executemany('INSERT INTO metadata VALUES(?,?)', original.execute('SELECT key,value FROM metadata'))
        schema = 3 if name == 'blocks-128' else 2
        db.execute(f'PRAGMA user_version={schema}')
        db.execute("UPDATE metadata SET value=? WHERE key='schema_version'", (str(schema),))
        dbs[name] = db
    block_id, buffer, words = 0, [], []
    largest_block = 0

    def flush():
        nonlocal block_id, largest_block
        if not buffer:
            return
        raw = b''.join(item[2] for item in buffer)
        compressed = zlib.compress(raw, 9)
        assert zlib.decompress(compressed) == raw
        dbs['blocks-128'].execute('INSERT INTO blocks VALUES(?,?,?)', (block_id, compressed, len(raw)))
        offset = 0
        for word, rank, payload in buffer:
            assert raw[offset:offset + len(payload)] == payload
            dbs['blocks-128'].execute('INSERT INTO entries VALUES(?,?,?,?,?)', (word, rank, block_id, offset, len(payload)))
            offset += len(payload)
        largest_block = max(largest_block, len(raw))
        block_id += 1
        buffer.clear()

    for word, rank, raw in source_entries(original):
        dbs['uncompressed'].execute('INSERT INTO entries VALUES(?,?,?,?)', (word, rank, raw, len(raw)))
        dbs['per-entry'].execute('INSERT INTO entries VALUES(?,?,?,?)', (word, rank, zlib.compress(raw, 9), len(raw)))
        buffer.append((word, rank, raw))
        words.append(word)
        if len(buffer) == 128:
            flush()
    flush()
    for db in dbs.values():
        db.commit()
        db.execute('VACUUM')
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert db.execute('SELECT count(*) FROM entries').fetchone()[0] == len(words)
        db.close()
    rng = random.Random(20260914)
    # The production reader accepts at most 128 characters.
    eligible = [word for word in words if len(word) <= 128]
    common = [word for word in ['hello', 'run', 'apple', 'roam', 'multimeter', 'digital multimeter', 'environment', 'personalise', 'dictionary', 'watch', 'time', 'work', 'good', 'book', 'water', 'home'] if word in words]
    existing = set(words)
    aliases = [(alias, word) for alias, word in original.execute('SELECT alias,word FROM aliases ORDER BY alias') if alias not in existing and len(alias) <= 128]
    chosen_aliases = rng.sample(aliases, min(64, len(aliases)))
    workloads = {
        'random': [{'query': w, 'expectedWord': w} for w in rng.sample(eligible, 512)],
        'repeated': [{'query': common[i % len(common)], 'expectedWord': common[i % len(common)]} for i in range(512)],
        'aliases': [{'query': a, 'expectedWord': w} for a, w in chosen_aliases],
        'misses': [{'query': 'zzqvxxnotaword' + str(i), 'expectedWord': None} for i in range(32)],
    }
    # Misses above exercise empty result handling; these exercise the production
    # spelling-suggestion algorithm as well and are reported separately.
    workloads['typos'] = [{'query': w, 'expectedWord': None} for w in ['dictionray', 'zzzzzzzzzzzzzzzz'] if w not in existing]
    manifest = {'sourceSHA256': pack['sha256'], 'entries': len(words), 'seed': 20260914,
                'largestBlockBytes': largest_block, 'workloads': workloads, 'files': {}}
    for path in OUTPUT.glob('*.sqlite'):
        with path.open('rb') as f:
            sha = hashlib.file_digest(f, 'sha256').hexdigest()
        manifest['files'][path.stem] = {'bytes': path.stat().st_size, 'sha256': sha}
    (OUTPUT / 'queries.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    for name, info in manifest['files'].items():
        print(name, round(info['bytes'] / 1024**2, 2), 'MiB', flush=True)
    print('Entries:', len(words), 'largest raw block:', largest_block, 'bytes', flush=True)


if __name__ == '__main__':
    build()
