# Upload these files

Publish the seven files below together under `https://fastcdn.candyrect.com/instadict/`.
The manifest uses relative filenames; the same files also work in any custom source
folder, including the existing R2 mirror. Do not rename the versioned SQLite files.
The SQLite content is unchanged by this UI release. If the current compressed packs
are already uploaded, only the updated relative-URL `manifest.json` needs uploading.
For the optional R2 mirror, see `Cloudflare/README.md` for validation and publishing.

| File | Purpose |
| --- | --- |
| `english-english-2026.09.14.sqlite` | English definitions, examples, phonetics, synonyms and word forms (23.5 MiB) |
| `english-chinese-2026.09.14.sqlite` | English headwords with Chinese definitions and English phonetics (51.8 MiB) |
| `chinese-english-2026.09.14.sqlite` | CC-CEDICT Chinese headwords, traditional aliases, pinyin and English meanings (9.9 MiB) |
| `manifest.json` | Current versions, file URLs, byte sizes, SHA-256 checksums and entry counts |
| `english-english-licenses.txt` | Source attribution and licenses |
| `english-chinese-licenses.txt` | Source attribution and licenses |
| `chinese-english-licenses.txt` | CC-CEDICT attribution, modification notice and CC BY-SA 4.0 license |

Upload the packs and licenses first, then `manifest.json` last.
This release fixes malformed source text and missing entries, and uses lossless
block compression. Install app version 0.5 build 8 (iPhone and Watch) before testing
these schema-3 packs. They remain compressed on the Watch; no whole-pack expansion
is needed during installation. Pinyin tone marks and example highlighting are included.
During internal testing, this folder keeps only the current manifest's three packs.
The corrected packs use the requested `2026.09.14` filenames, replacing the earlier
test release. Upload the new bytes and manifest, refresh any cached CDN copies,
and remove installed copies on the test devices before downloading again. Refresh
the iPhone catalog, download, and send the new packs to Watch.
The iPhone app also includes a small initial catalog, so all three choices appear
before the server is populated. Until you publish the files, downloads will fail
with a clear error; no sample dictionary is substituted.

Recommended HTTP settings:

- SQLite: `Content-Type: application/octet-stream`; this internal release uses
  `Cache-Control: no-cache` because testing reuses the dated filenames. Future
  immutable versioned URLs can use `public, max-age=31536000, immutable`.
- Manifest: `Content-Type: application/json`; `Cache-Control: no-cache` so a catalog
  refresh sees new releases. Public HTTPS access; no login or HTML challenge page.
- Serve the SQLite bytes exactly as built. Supporting byte-range requests and
  Content-Length helps background downloads. CORS is unnecessary for native apps.

Future releases: run `python3 Tools/build_dictionary.py --version NEW.VERSION`
from the repository root. It generates new filenames and hashes and updates the
app's initial catalog. Publish the new manifest after the new files. The app's
Refresh button fetches it. Once publicly released, retain old versioned URLs for
downloads in flight; the current internal test rollout uses a manual reset instead.

For public releases, do not replace bytes at an existing versioned URL without also
changing the version and manifest. This internal test release intentionally reuses
the requested filenames with updated checksums. Packs are verified on both iPhone and Watch. The database
schema version is 3; the updated app reads both schemas 2 and 3, while older app
builds cannot read schema 3.

CC-CEDICT's derived Chinese–English pack is distributed under CC BY-SA 4.0. Its
license and attribution are embedded in the database and included in the iPhone
source page. The other packs retain their respective source licenses.
The original CC-CEDICT source stays in the local build cache; it is not needed
by either app or in the upload folder. Source links and the snapshot checksum
remain in the pack's notices and provenance.
