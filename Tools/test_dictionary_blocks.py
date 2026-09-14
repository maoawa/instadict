import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zlib

import build_dictionary


class BlockBuilderTests(unittest.TestCase):
    def test_full_partial_and_size_limited_blocks_keep_every_byte(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(build_dictionary, 'OUTPUT', Path(directory)):
            pack = build_dictionary.Pack('english-english', 'test')
            expected = {}
            for i in range(130):
                word = f'word{i:03d}'
                entry = {'word': word, 'definition': '中文'}
                expected[word] = build_dictionary.compact(entry).encode()
                pack.insert(word, i, entry)
            # The oversized singleton is permitted, but never combined with
            # neighbors. Normal groups stop at the 128 KiB target.
            large = {'word': 'word130', 'definition': 'x' * (build_dictionary.BLOCK_TARGET_BYTES + 1)}
            expected['word130'] = build_dictionary.compact(large).encode()
            pack.insert('word130', 130, large)
            manifest = pack.finish({'alias': 'word001'}, {}, '')
            import sqlite3
            with sqlite3.connect(pack.file) as db:
                self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 3)
                self.assertEqual(db.execute('SELECT count(*) FROM blocks').fetchone()[0], 3)
                for word, offset, length, compressed, size in db.execute('SELECT e.word,e.byte_offset,e.payload_size,b.payload,b.payload_size FROM entries e JOIN blocks b ON b.id=e.block_id'):
                    raw = zlib.decompress(compressed)
                    self.assertEqual(len(raw), size)
                    self.assertEqual(raw[offset:offset + length], expected.pop(word))
                self.assertEqual(db.execute('SELECT word FROM aliases WHERE alias=?', ('alias',)).fetchone()[0], 'word001')
            self.assertFalse(expected)
            self.assertEqual(manifest['entryCount'], 131)
            self.assertEqual(manifest['schemaVersion'], 3)
            self.assertEqual(manifest['url'], 'english-english-test.sqlite')


if __name__ == '__main__':
    unittest.main()
