#!/usr/bin/env python3
"""Bundle the actual licenses from the verified source trees."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
LICENSES = {
    "UxPlay-GPL.txt": "uxplay/LICENSE",
    "PlayFair.txt": "uxplay/lib/playfair/LICENSE.md",
    "llhttp-MIT.txt": "uxplay/lib/llhttp/LICENSE-MIT",
    "libplist-GPL.txt": "libplist/COPYING",
    "libplist-LGPL.txt": "libplist/COPYING.LESSER",
    "libcnary-LGPL.txt": "libplist/libcnary/COPYING",
    "OpenSSL-Apache.txt": "openssl/LICENSE.txt",
}
destination = ROOT / "Resources/Licenses"
destination.mkdir(parents=True, exist_ok=True)
for name, path in LICENSES.items():
    shutil.copyfile(ROOT / ".deps/src" / path, destination / name)
shutil.copyfile(ROOT / "THIRD_PARTY_NOTICES.md", destination / "ThirdPartyNotices.txt")
