#!/usr/bin/env python3
"""Import the eight ORIGINAL text files from the user's tested v2 ZIP.
Run locally: python3 scripts/import-package.py /path/to/bch-installer-v1-originaldateien.zip\nAlso accepts the original bch-mainnet-installationspaket_v2.zip.
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
SHA256 = {
    "dashboard/app.py": "1468e64765cab0335fe5a47204e34187d1d85f3ef00fced55765f915a271f4c9",
    "dashboard/ckpool_api.py": "9b0b2e0d246fe9d1ba81303138d0c5b98350e884bddee5f21a3d4e58c13b4b2a",
    "dashboard/block_history.py": "1f292235205b8c955d66470c7b5f70ef938dc0af82d26fb40ed0dd4ab1df8cc8",
    "dashboard/templates/index.html": "157e48df2f8384b714ab7e4b817ab99cb1841f1ff180c88225946d88797e8ef2",
    "dashboard/static/script.js": "bace340ff9d1938db4363e114936853f669768e8fbf77834c5565fea86cb10f0",
    "dashboard/static/style.css": "f5ebc472b9561c39854a9f232f2f14b99f6b6f407d27c31e9092cbe15345c79d",
    "bch-ckpool-mainnet.patch": "631abb14914e84c1550d92d0fc19d1b95eca38b37b912d7d7240e01cba82f916",
    "INSTALLATIONSANLEITUNG.md": "9e49bcd9d5bcfd18f3d4ab0a17ba856c6ebc362a2e961f1687dd50185504892f",
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
    prepared_names = {DEST.get(name, name) for name in EXPECTED}
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        if len(names) != len(EXPECTED) or set(names) != EXPECTED:
            raise SystemExit("Unerwarteter ZIP-Inhalt: Import verweigert.")
        for info in z.infolist():
            if info.is_dir() or info.file_size > 200_000 or info.compress_size == 0:
                raise SystemExit("Ungültiger ZIP-Eintrag: " + info.filename)
            if info.external_attr >> 16 & 0o170000 == 0o120000:
                raise SystemExit("Symlink im ZIP verweigert.")
        data = {reverse[name]: z.read(name) for name in names}
    for name, raw in data.items():
        digest = hashlib.sha256(raw).hexdigest()
        if digest != SHA256[name]:
            raise SystemExit(f"SHA256 stimmt nicht: {name}. Import verweigert.")
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
