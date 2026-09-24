# Third-party notices

This application is distributed under GPL-3.0-or-later. Original integration
code is Copyright (c) 2026 AirPlayReceiver_iOS contributors. Dependencies retain
their own copyright notices and licenses; no original attribution is removed.

Sources and hashes are recorded in `dependencies.lock.json`. Run
`python3 scripts/fetch_dependencies.py` to retrieve the corresponding upstream
source, and follow `docs/development.md` to rebuild or relink the application.
The `research` entries in that file are not included in the current binary.

| Component | Source | License |
| --- | --- | --- |
| UxPlay | https://github.com/FDH2/UxPlay | GPL-3.0-or-later; many individual receiver source files LGPL-2.1-or-later |
| PlayFair (included by UxPlay) | UxPlay `lib/playfair` | See bundled PlayFair notice and source headers |
| llhttp (included by UxPlay) | UxPlay `lib/llhttp` | MIT |
| libplist | https://github.com/libimobiledevice/libplist | LGPL-2.1-or-later; see per-file notices |
| libcnary (included by libplist) | libplist `libcnary` | LGPL-2.1-or-later |
| OpenSSL | https://github.com/openssl/openssl | Apache-2.0 |

The iOS discovery backend's TXT fields follow UxPlay's DNS-SD backend:
Copyright (C) 2011-2012 Juho Vähä-Herttua, modified by fduncanh 2022, 2026.
Upstream source archives remain unchanged. `cmake/Upstream.cmake` applies an
explicit build-time null guard to a generated copy of `raop.c` so partial
initialization can be destroyed safely. This is the only current upstream patch.

Complete upstream licenses are copied into the app and build artifact by
`scripts/collect_licenses.py`. Preserve these notices and corresponding source
availability when redistributing compiled builds.

AirPlay is an Apple trademark. This is an independent experimental project,
not an Apple product or a certified AirPlay implementation.
