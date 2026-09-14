# Dictionary distribution through R2

Public catalog: https://instadict.marsinside.com/manifest.json

- Account: `21c28b8e58474ce2bcadbec17d99f45b`
- Bucket: `instadict-dictionaries`, Standard storage, APAC location
- Custom domain: `instadict.marsinside.com`, in zone `marsinside.com`
- Minimum TLS: 1.2
- Managed testing address: https://pub-d3dd17f1b84247f39bef689c3df0431d.r2.dev/

No Pages project or Worker is required. The managed `r2.dev` address is rate-limited;
the mirror uses the custom domain. The app’s built-in source is now
`https://fastcdn.candyrect.com/instadict/`. Domain ownership and certificates are managed by R2.

Run from this directory:

```sh
npm ci
npx wrangler login --scopes account:read user:read workers:write
npm run check
npm run deploy
npm run verify
```

Wrangler credentials stay in its local credential storage, outside the repository.
The reduced OAuth scope set is sufficient for R2 uploads; Wrangler's `whoami` may
mention other unused scopes. `distribution.json` selects the exact account, bucket
and public base URL. Both catalogs contain relative filenames, so the same manifest
works on R2 and the default CDN. Changing the built-in host only requires changing
`DictionaryCatalog.remoteURL`; users can also choose a source in Settings.

The uploader checks the two catalogs agree and verifies local file sizes and SHA-256
hashes. It uploads only the three current SQLite files, three license notices, then
`manifest.json`. All objects use `Cache-Control: no-cache` during internal testing.
It does not upload raw sources, development files or earlier dictionary versions.

The verifier downloads all seven objects from the custom domain, checks lengths and
hashes, and checks a byte-range request against each SQLite header. Do not attach
HTML challenges or login requirements to the download paths. Native apps do not
need CORS headers.

R2 Standard's monthly free allowance is 10 GB-month storage, 1 million Class A
operations and 10 million Class B operations, shared with other account usage.
Internet egress is free. Usage above the allowance is billed; consult
https://developers.cloudflare.com/r2/pricing/ for current rates.
