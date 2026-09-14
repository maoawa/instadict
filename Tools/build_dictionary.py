#!/usr/bin/env python3
"""Build three independent CDN packs. Never writes SQLite into an app target."""
import argparse
import csv
import gzip
import hashlib
import json
import re
import sqlite3
import urllib.request
import zlib
from pathlib import Path
from zipfile import ZipFile
from dictionary_sources import (ROOT, CACHE, SOURCES, ECDICT_REV, IPA_REV, NLTK_REV,
                                fetch_sources, wordnet, normalize, parse_sections,
                                FORM_LABELS, british_ipa, compact)

OUTPUT = ROOT / 'Distribution' / 'Dictionaries'
PHONE = ROOT / 'InstaDict iOS App' / 'Resources'
SHARED = ROOT / 'Shared' / 'Resources'
CEDICT_URL = 'https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz'
LICENSE_URL = 'https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt'
SCHEMA = 3
BLOCK_ENTRIES = 128
BLOCK_TARGET_BYTES = 128 * 1024
MAX_PAYLOAD_BYTES = 2_000_000
CORRECTIONS = Path(__file__).with_name('dictionary_corrections.json')

def sha256(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()

class Pack:
    def __init__(self, identifier, version):
        self.id = identifier
        self.version = version
        self.file = OUTPUT / f'{identifier}-{version}.sqlite'
        self.temporary = self.file.with_suffix('.building')
        self.temporary.unlink(missing_ok=True)
        self.connection = sqlite3.connect(self.temporary)
        self.connection.executescript('''
          PRAGMA journal_mode=OFF;
          PRAGMA user_version=3;
          CREATE TABLE entries(word TEXT PRIMARY KEY,rank INTEGER NOT NULL,block_id INTEGER NOT NULL,byte_offset INTEGER NOT NULL,payload_size INTEGER NOT NULL) WITHOUT ROWID;
          CREATE TABLE blocks(id INTEGER PRIMARY KEY,payload BLOB NOT NULL,payload_size INTEGER NOT NULL);
          CREATE TABLE aliases(alias TEXT NOT NULL,word TEXT NOT NULL,PRIMARY KEY(alias,word)) WITHOUT ROWID;
          CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL) WITHOUT ROWID;
        ''')
        self.words = set()
        self.pending = []
        self.pending_bytes = 0
        self.block_id = 0

    def insert(self, word, rank, entry):
        payload = compact(entry).encode()
        assert 0 < len(payload) <= MAX_PAYLOAD_BYTES
        if self.pending and (len(self.pending) >= BLOCK_ENTRIES or self.pending_bytes + len(payload) > BLOCK_TARGET_BYTES):
            self.flush_block()
        self.pending.append((word, rank, payload))
        self.pending_bytes += len(payload)
        self.words.add(word)

    def flush_block(self):
        if not self.pending:
            return
        payload = b''.join(item[2] for item in self.pending)
        self.connection.execute('INSERT INTO blocks VALUES(?,?,?)', (self.block_id, zlib.compress(payload, 9), len(payload)))
        offset = 0
        for word, rank, entry in self.pending:
            self.connection.execute('INSERT INTO entries VALUES(?,?,?,?,?)', (word, rank, self.block_id, offset, len(entry)))
            offset += len(entry)
        self.pending.clear()
        self.pending_bytes = 0
        self.block_id += 1

    def finish(self, aliases, provenance, base_url):
        self.flush_block()
        self.connection.executemany('INSERT OR IGNORE INTO aliases VALUES(?,?)',
            [(alias,word) for alias,word in sorted(aliases.items()) if word in self.words and alias != word])
        metadata = {'pack_id':self.id,'version':self.version,'schema_version':str(SCHEMA),'entries':str(len(self.words)),
                    'provenance':compact(provenance), 'compression':'zlib-blocks',
                    'block_entry_limit':str(BLOCK_ENTRIES), 'block_target_bytes':str(BLOCK_TARGET_BYTES)}
        self.connection.executemany('INSERT INTO metadata VALUES(?,?)',metadata.items())
        self.connection.commit()
        assert self.connection.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        self.connection.execute('VACUUM')
        self.connection.close()
        self.temporary.replace(self.file)
        return {'id':self.id,'version':self.version,'schemaVersion':SCHEMA,'entryCount':len(self.words),
                'byteCount':self.file.stat().st_size,'sha256':sha256(self.file),
                'url':(base_url.rstrip('/')+'/' if base_url else '')+self.file.name}

def fetch_extra(filename,url):
    target=CACHE/filename
    if not target.exists():
        with urllib.request.urlopen(url,timeout=120) as response: target.write_bytes(response.read())
    return target

def build(version,base_url):
    fetch_sources()
    for directory in (OUTPUT,PHONE,SHARED): directory.mkdir(parents=True,exist_ok=True)
    english,aliases=wordnet()
    american={normalize(w):ipa for w,ipa in (line.split('\t',1) for line in (CACHE/'en_US.txt').read_text().splitlines())}
    with (CACHE/'ecdict.csv').open() as file: rows={normalize(r['word']):r for r in csv.DictReader(file)}
    corrections=json.loads(CORRECTIONS.read_text())
    for word, correction in corrections.items():
        rows.setdefault(word, {'word':word}).update({k:v for k,v in correction.items() if k!='reason'})
    # Each language pack selects its own nonempty definitions below. Requiring
    # English content here used to discard Chinese-only entries and base forms.
    words=sorted(set(english)|set(rows))
    ee=Pack('english-english',version)
    ec=Pack('english-chinese',version)
    for word in words:
        row=rows.get(word,{})
        sections=english.get(word) or parse_sections(row.get('definition',''))
        chinese=parse_sections(row.get('translation',''))
        forms=[];lemma=None
        for exchange in row.get('exchange','').split('/'):
            if ':' not in exchange:continue
            key,value=exchange.split(':',1)
            if key=='0' and normalize(value)!=word: lemma=normalize(value)
            elif key in FORM_LABELS and normalize(value)!=word:
                forms.append({'label':FORM_LABELS[key],'word':value})
                aliases.setdefault(normalize(value),word)
        ranks=[int(row[k]) for k in ('bnc','frq') if row.get(k,'').isdigit() and int(row[k])>0]
        entry={'word':word,'displayWord':row.get('word',word),'britishIPA':british_ipa(row.get('phonetic','')),
               'americanIPA':american.get(word),'forms':forms,'lemma':lemma,'pinyin':None}
        if sections:ee.insert(word,min(ranks,default=999999),{**entry,'english':sections,'chinese':[]})
        if chinese:ec.insert(word,min(ranks,default=999999),{**entry,'english':[],'chinese':chinese})
    provenance={'ecdict':ECDICT_REV,'ipa':IPA_REV,'wordnet':NLTK_REV,
                'local_corrections':corrections,
                'source_sha256':{name:sha256(CACHE/name) for name in SOURCES}}
    packs=[ee.finish(aliases,provenance,base_url),ec.finish(aliases,provenance,base_url)]
    cedict=fetch_extra('cedict.txt.gz',CEDICT_URL)
    license_file=fetch_extra('CC-BY-SA-4.0.txt',LICENSE_URL)
    ce=Pack('chinese-english',version)
    entries={};traditional_aliases={};header=[]
    with gzip.open(cedict,'rt',encoding='utf-8') as file:
        for line in file:
            if line.startswith('#'):header.append(line.rstrip());continue
            match=re.match(r'^(\S+) (\S+) \[([^\]]+)\] /(.+)/$',line.strip())
            if not match:continue
            traditional,simplified,pinyin,gloss=match.groups()
            word=normalize(simplified)
            item=entries.setdefault(word,{'pinyin':[],'senses':[]})
            if pinyin not in item['pinyin']:item['pinyin'].append(pinyin)
            for definition in gloss.split('/'):
                sense={'definition':definition,'examples':[],'synonyms':[]}
                if sense not in item['senses']:item['senses'].append(sense)
            traditional_aliases[normalize(traditional)]=word
    for word,item in sorted(entries.items()):
        ce.insert(word,999999,{'word':word,'displayWord':word,'britishIPA':None,'americanIPA':None,
                  'pinyin':' / '.join(item['pinyin']),'forms':[],'lemma':None,'chinese':[],
                  'english':[{'partOfSpeech':'meaning','senses':item['senses']}]})
    packs.append(ce.finish(traditional_aliases,{'source_url':CEDICT_URL,'source_sha256':sha256(cedict),
                     'source_header':header,'license':'CC BY-SA 4.0'},base_url))
    catalog={'schemaVersion':SCHEMA,'packs':packs}
    english_notice=('InstaDict dictionary sources\n\nEnglish definitions, examples and synonyms: WordNet 3.0, Princeton University.\n'
       'Additional English definitions, Chinese translations, word forms and primarily British phonetics: ECDICT, Linwei.\n'
       'American IPA: ipa-dict / cmudict-ipa.\n\n'
       'Modified by selecting records, cleaning escaped line breaks, normalizing legacy IPA, applying reviewed local corrections '
       '(personalise pronunciation, hentai definition, multimeter definition and word forms), and compiling separate SQLite packs '
       'with lossless zlib compression in blocks of up to 128 entries. '
       'The replacement definitions are locally authored. Malformed phonetics without a reviewed correction are omitted. '
       'ECDICT phonetics are primarily British, not individually accent-verified. Coverage varies and some language is dated.\n\n')
    with ZipFile(CACHE/'wordnet.zip') as archive:english_notice+=archive.read('wordnet/LICENSE').decode()+'\n\n'
    for name in SOURCES:
        if name.endswith('LICENSE.txt'):english_notice+=name+'\n'+SOURCES[name]+'\n'+(CACHE/name).read_text()+'\n\n'
    chinese_notice=('Chinese–English: CC-CEDICT, community contributors, published by MDBG.\n'
       'https://www.mdbg.net/chinese/dictionary?page=cc-cedict\n'
       'CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0/\n\n'
       'Modifications: grouped simplified headwords and senses, retained numbered pinyin, indexed traditional spellings, '
       'and compiled a SQLite database with lossless zlib compression in blocks of up to 128 entries. '
       'This derived dictionary pack is licensed under CC BY-SA 4.0. '
       'Original source: '+CEDICT_URL+'\nThe cached source snapshot SHA-256 is recorded in the pack provenance.\n\n'
       +'\n'.join(header)+'\n\n'+license_file.read_text())
    for identifier,notice in [('english-english',english_notice),('english-chinese',english_notice),('chinese-english',chinese_notice)]:
        for directory in (OUTPUT,PHONE):(directory/f'{identifier}-licenses.txt').write_text(notice)
        pack=next(p for p in packs if p['id']==identifier)
        database=OUTPUT / pack['url'].rsplit('/',1)[-1]
        connection=sqlite3.connect(database)
        connection.execute('INSERT OR REPLACE INTO metadata VALUES(?,?)',('licenses',notice))
        connection.commit()
        connection.execute('VACUUM')
        connection.close()
        pack['byteCount']=database.stat().st_size
        pack['sha256']=sha256(database)
    for target in (OUTPUT/'manifest.json',SHARED/'DictionaryCatalog.json'):
        target.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    for pack in packs:print(pack['id'],pack['entryCount'],round(pack['byteCount']/1024**2,1),'MiB',pack['url'],flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',default='2026.09.14')
    parser.add_argument('--base-url',default='',help='Optional absolute download prefix; default: filenames relative to the manifest')
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9.-]+',args.version):parser.error('Version must be safe for filenames')
    build(args.version,args.base_url)
