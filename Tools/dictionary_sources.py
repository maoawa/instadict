#!/usr/bin/env python3
"""Build the bundled, read-only dictionary. Network is used only by this build tool."""

import csv
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import urllib.request
import zlib
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".dictionary-sources"
RESOURCES = ROOT / "Distribution" / "Dictionaries"
ECDICT_REV = "bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"
IPA_REV = "43c3570eb3553bdd19fccd2bd0091534889af023"
NLTK_REV = "550b6625bcef1f2abff2ff770a5a0d272c9c6b2a"
SOURCES = {
    "ecdict.csv": f"https://raw.githubusercontent.com/skywind3000/ECDICT/{ECDICT_REV}/ecdict.csv",
    "en_US.txt": f"https://raw.githubusercontent.com/open-dict-data/ipa-dict/{IPA_REV}/data/en_US.txt",
    "wordnet.zip": f"https://raw.githubusercontent.com/nltk/nltk_data/{NLTK_REV}/packages/corpora/wordnet.zip",
    "ECDICT-LICENSE.txt": f"https://raw.githubusercontent.com/skywind3000/ECDICT/{ECDICT_REV}/LICENSE",
    "IPA-DICT-LICENSE.txt": f"https://raw.githubusercontent.com/open-dict-data/ipa-dict/{IPA_REV}/LICENSE",
    "CMUDICT-IPA-LICENSE.txt": "https://raw.githubusercontent.com/lingz/cmudict-ipa/master/LICENSE",
}
POS = {
    "n": "noun", "v": "verb", "vt": "verb", "vi": "verb", "v. t": "verb",
    "v. i": "verb", "a": "adjective", "adj": "adjective", "s": "adjective",
    "r": "adverb", "adv": "adverb", "ad": "adverb", "prep": "preposition",
    "pron": "pronoun", "conj": "conjunction", "interj": "interjection",
    "int": "interjection", "art": "article", "definite article": "article",
    "num": "number", "aux": "auxiliary verb", "abbr": "abbreviation",
    "pl": "plural noun", "n. pl": "plural noun", "det": "determiner",
}
POS_PATTERN = re.compile(r"^(" + "|".join(re.escape(k) for k in sorted(POS, key=len, reverse=True)) + r")\.?(?:\s+|$)", re.I)
FORM_LABELS = {"p": "past tense", "d": "past participle", "i": "present participle",
               "3": "third person", "r": "comparative", "t": "superlative", "s": "plural"}


def normalize(word):
    return " ".join(word.replace("’", "'").replace("‘", "'").replace("‑", "-").replace("–", "-").lower().split())


def fetch_sources():
    CACHE.mkdir(exist_ok=True)
    RESOURCES.mkdir(parents=True, exist_ok=True)
    for filename, url in SOURCES.items():
        target = CACHE / filename
        if not target.exists():
            print(f"Downloading {filename}", flush=True)
            with urllib.request.urlopen(url, timeout=120) as response:
                target.write_bytes(response.read())


def parse_sections(raw):
    sections = []
    # Decode only known text separators, not arbitrary Python/Unicode escapes.
    raw = re.sub(r"\\+[rn]", "\n", raw)
    raw = re.sub(r"\\+t", " ", raw)
    for line in raw.splitlines():
        if not line.strip():
            continue
        if line[0].isspace() and sections:
            sections[-1]["senses"][-1]["definition"] += " " + line.strip()
            continue
        line = line.strip()
        match = POS_PATTERN.match(line)
        part = POS[match.group(1).lower()] if match else "meaning"
        definition = line[match.end():] if match else line
        if not definition.strip():
            continue
        if not sections or sections[-1]["partOfSpeech"] != part:
            sections.append({"partOfSpeech": part, "senses": []})
        sections[-1]["senses"].append({"definition": definition, "examples": [], "synonyms": []})
    return sections


def wordnet():
    result, exceptions = {}, {}
    with ZipFile(CACHE / "wordnet.zip") as archive:
        for kind in ("noun", "verb", "adj", "adv"):
            synsets = {}
            for line in archive.read(f"wordnet/data.{kind}").decode().splitlines():
                if not line or not line[0].isdigit():
                    continue
                data, gloss = line.split(" | ", 1)
                fields = data.split()
                count = int(fields[3], 16)
                words = [re.sub(r"\((?:a|p|ip)\)$", "", fields[4 + i * 2]).replace("_", " ") for i in range(count)]
                examples = re.findall(r'"([^\"]+)"', gloss)
                definition = re.sub(r';?\s*"[^\"]+"', "", gloss).strip(" ;")
                synsets[fields[0]] = (definition, examples, words)
            # The index orders senses by usage frequency, unlike data-file offsets.
            for line in archive.read(f"wordnet/index.{kind}").decode().splitlines():
                if not line or line.startswith(" "):
                    continue
                fields = line.split()
                word = normalize(fields[0].replace("_", " "))
                count = int(fields[2])
                senses = []
                for offset in fields[-count:]:
                    definition, examples, synonyms = synsets[offset]
                    senses.append({"definition": definition, "examples": examples,
                                   "synonyms": [w for w in synonyms if normalize(w) != word]})
                result.setdefault(word, []).append({"partOfSpeech": POS[fields[1]], "senses": senses})
            for line in archive.read(f"wordnet/{kind}.exc").decode().splitlines():
                words = line.split()
                exceptions.setdefault(normalize(words[0]), normalize(words[1]))
    return result, exceptions


def british_ipa(value):
    # Normalize ECDICT's legacy IPA glyphs; never derive UK IPA from US IPA.
    value = value.strip().strip("/[]")
    # Backslashes in this source replace lost phonetic characters. Deleting them
    # would invent a pronunciation; omit it unless a reviewed correction exists.
    if "\\" in value:
        return None
    for old, new in [("'", "ˈ"), (",", "ˌ"), (":", "ː"), ("ә", "ə"), ("ɡ", "g")]:
        value = value.replace(old, new)
    value = re.sub(r"i(?!ː)", "ɪ", value)
    value = re.sub(r"u(?!ː)", "ʊ", value)
    return f"/{value}/" if value else None


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
