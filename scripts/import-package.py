#!/usr/bin/env python3
"""Import the eight ORIGINAL text files from the user's tested v2 ZIP.
Run locally: python3 scripts/import-package.py /path/to/bch-mainnet-installationspaket_v2.zip
Never import unknown archives.
"""
import hashlib
import pathlib
import sys
import zipfile

EXPECTED = {
    "dashboard/app.py",
    "dashboard/ckpool_api.py",
    "dashboard/block_history.py",
    "dashboard/templates/index.html",
    "dashboard/static/script.js",
    "dashboard/static/style.css",
    "bch-ckpool-mainnet.patch",
    "INSTALLATIONSANLEITUNG.md",
}
ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = {
    "bch-ckpool-mainnet.patch": "patches/bch-ckpool-mainnet.patch",
    "INSTALLATIONSANLEITUNG.md": "docs/INSTALLATIONSANLEITUNG-v2.md",
}
def main():
    if len(sys.argv) != 2:
        raise SystemExit("Aufruf: python3 scripts/import-package.py /pfad/zum/paket.zip")
    archive = pathlib.Path(sys.argv[1]).resolve()
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        if len(names) != len(EXPECTED) or set(names) != EXPECTED:
            raise SystemExit("Unerwarteter ZIP-Inhalt: Import verweigert.")
        for info in z.infolist():
            if info.is_dir() or info.file_size > 200_000 or info.compress_size == 0:
                raise SystemExit("Ungültiger ZIP-Eintrag: " + info.filename)
            if info.external_attr >> 16 & 0o170000 == 0o120000:
                raise SystemExit("Symlink im ZIP verweigert.")
        data = {name: z.read(name) for name in EXPECTED}
    for name, raw in sorted(data.items()):
        text = raw.decode("utf-8")
        rel = DEST.get(name, name)
        path = ROOT / rel
        if path.exists():
            raise SystemExit(f"Zieldatei existiert bereits, kein Überschreiben: {rel}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print(f"{rel}: SHA256 {hashlib.sha256(raw).hexdigest()}")
    print("Originaldateien importiert. Vor einem Commit Inhalte auf Zugangsdaten prüfen!")
if __name__ == "__main__":
    main()
