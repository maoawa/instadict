# Upload these files

Upload this directory's contents to `https://fastcdn.candyrect.com/instadict/`.
Do not rename the versioned SQLite files: the app's catalog points to these exact URLs.

| File | Purpose |
| --- | --- |
| `english-english-2026.09.14.sqlite` | English definitions, examples, phonetics, synonyms and word forms |
| `english-chinese-2026.09.14.sqlite` | English headwords with Chinese definitions and English phonetics |
| `chinese-english-2026.09.14.sqlite` | CC-CEDICT Chinese headwords, traditional aliases, numbered pinyin and English meanings |
| `manifest.json` | Current versions, file URLs, byte sizes, SHA-256 checksums and entry counts |
| `english-english-licenses.txt` | Source attribution and licenses |
| `english-chinese-licenses.txt` | Source attribution and licenses |
| `chinese-english-licenses.txt` | CC-CEDICT attribution, modification notice and CC BY-SA 4.0 license |
| `cc-cedict-source.txt.gz` | Unchanged source snapshot for the Chinese–English pack |

Upload the packs, licenses and source snapshot first, then `manifest.json` last.
The iPhone app also includes a small initial catalog, so all three choices appear
before the server is populated. Until you publish the files, downloads will fail
with a clear error; no sample dictionary is substituted.

Recommended HTTP settings:

- SQLite: `Content-Type: application/octet-stream`; immutable versioned URLs can
  use `Cache-Control: public, max-age=31536000, immutable`.
- Manifest: `Content-Type: application/json`; `Cache-Control: no-cache` so a catalog
  refresh sees new releases. Public HTTPS access; no login or HTML challenge page.
- Serve the SQLite bytes exactly as built. Supporting byte-range requests and
  Content-Length helps background downloads. CORS is unnecessary for native apps.

Future releases: run `python3 Tools/build_dictionary.py --version NEW.VERSION`
from the repository root. It generates new filenames and hashes and updates the
app's initial catalog. Publish the new manifest after the new files. The app's
Refresh button fetches it. Keep old versioned URLs available for downloads in flight.

Do not replace bytes at an existing versioned URL without also changing the
version and manifest. Packs are verified on both iPhone and Watch. The database
schema version is 2; format changes require a compatible app update.

CC-CEDICT's derived Chinese–English pack is distributed under CC BY-SA 4.0. Its
license and attribution are embedded in the database and included in the iPhone
source page. The other packs retain their respective source licenses.

No server files have been uploaded by this implementation.
