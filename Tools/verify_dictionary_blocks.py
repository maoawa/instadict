#!/usr/bin/env python3
"""Verify every block and optionally compare every entry/alias with older packs."""
import argparse
from itertools import zip_longest
import json
from pathlib import Path
import sqlite3
import zlib


def entries(db):
    schema = db.execute('PRAGMA user_version').fetchone()[0]
    if schema == 2:
        for word, rank, payload, size in db.execute('SELECT word,rank,payload,payload_size FROM entries ORDER BY word'):
            raw = zlib.decompress(payload)
            assert len(raw) == size
            yield word, rank, raw
    elif schema == 3:
        last, raw = None, None
        for word, rank, block, offset, size in db.execute('SELECT word,rank,block_id,byte_offset,payload_size FROM entries ORDER BY word'):
            if block != last:
                payload, length = db.execute('SELECT payload,payload_size FROM blocks WHERE id=?', (block,)).fetchone()
                raw = zlib.decompress(payload)
                assert len(raw) == length and 0 < length <= 2_000_000
                last = block
            assert 0 <= offset < len(raw) and 0 < size <= len(raw) - offset
            yield word, rank, raw[offset:offset + size]
    else:
        raise ValueError(f'Unsupported schema {schema}')


def verify(directory, baseline=None):
    catalog = json.loads((directory / 'manifest.json').read_text())
    for pack in catalog['packs']:
        name = pack['url'].rsplit('/', 1)[-1]
        with sqlite3.connect(f'file:{directory / name}?mode=ro', uri=True) as db:
            assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            count = 0
            if baseline:
                with sqlite3.connect(f'file:{baseline / name}?mode=ro', uri=True) as old:
                    for before, after in zip_longest(entries(old), entries(db)):
                        assert before == after, f'Entry changed: {(before or after)[0]}'
                        count += 1
                    for before, after in zip_longest(old.execute('SELECT alias,word FROM aliases ORDER BY alias,word'), db.execute('SELECT alias,word FROM aliases ORDER BY alias,word')):
                        assert before == after, 'Alias changed'
            else:
                for word, _, raw in entries(db):
                    assert json.loads(raw)['word'] == word
                    count += 1
            assert count == pack['entryCount']
            if pack['schemaVersion'] == 3:
                assert db.execute('SELECT max(n) FROM (SELECT count(*) n FROM entries GROUP BY block_id)').fetchone()[0] <= 128
                maximum = db.execute('SELECT max(payload_size) FROM blocks').fetchone()[0]
                assert db.execute('SELECT count(*) FROM blocks b WHERE b.payload_size > 131072 AND (SELECT count(*) FROM entries e WHERE e.block_id=b.id) != 1').fetchone()[0] == 0
            else:
                maximum = db.execute('SELECT max(payload_size) FROM entries').fetchone()[0]
            print(pack['id'], f'{count:,} entries verified', 'largest raw block/record:', maximum, 'bytes', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parents[1] / 'Distribution/Dictionaries')
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    verify(args.directory, args.baseline)
