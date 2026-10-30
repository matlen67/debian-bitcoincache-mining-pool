# Bitcoin Cash Mainnet Solo Mining Pool — Installer v1 (Teststand)

**Nur auf einer frischen Debian-13-(Trixie)-Test-VM verwenden.** Niemals auf dem produktiven Pool `debbch`. Der Branch `main` bleibt unverändert.

## Status

Der Ablauf ist implementiert, aber **noch nicht Ende-zu-Ende getestet**. Die Originaldateien aus dem Referenz-ZIP müssen vor der Installation ins Repository importiert werden. Die BCHN-Release-Signatur, der CKPool-Referenzcommit und das tatsächliche Miner-/Auszahlungsverhalten sind vor produktiver Freigabe zu verifizieren.

## Voraussetzungen

Debian 13 x86_64 ohne Desktop, SSH, normaler Benutzer mit `sudo`, feste LAN-IP, eigene **BCH-Mainnet-Legacy-P2PKH-Adresse** (beginnt mit `1`). Kein bereits installierter BCHN-/CKPool-/Dashboard-Dienst.

## Originaldateien importieren

Das getestete Paket `bch-mainnet-installationspaket_v2.zip` enthält sechs Dashboard-Dateien, `bch-ckpool-mainnet.patch` und die Referenzanleitung. Das Importskript akzeptiert auch das umstrukturierte `bch-installer-v1-originaldateien.zip`, prüft die SHA256-Werte und überschreibt keine Dateien.

Auf einem lokalen Rechner mit Git-Zugang:

```bash
git clone --branch installer-v1 https://github.com/matlen67/debian-bitcoincache-mining-pool.git
cd debian-bitcoincache-mining-pool
python3 scripts/import-package.py /pfad/zum/bch-mainnet-installationspaket_v2.zip
git status --short
# Dateien prüfen, besonders keine Zugangsdaten committen
git add dashboard patches docs
git commit -m "Add tested original CKPool patch and dashboard assets"
git push origin installer-v1
```

Die Originalanleitung in `docs/INSTALLATIONSANLEITUNG-v2.md` ist bereits versioniert. Der Importer erkennt sie anhand ihrer SHA256-Prüfsumme und überspringt sie, wenn sie bytegleich ist. Andere vorhandene Zieldateien werden nicht überschrieben.

## Installation auf neuer Test-VM

Erst nach vollständigem Import der Originaldateien:

```bash
git clone --branch installer-v1 https://github.com/matlen67/debian-bitcoincache-mining-pool.git
cd debian-bitcoincache-mining-pool
bash setup-pool.sh
```

`setup-pool.sh` führt die Schritte kontrolliert aus und **stoppt während der BCHN-Synchronisierung**. Sobald BCHN vollständig synchronisiert ist, denselben Befehl erneut ausführen. Er startet CKPool und Dashboard **nicht automatisch**.

Für einzelne Schritte: `bash run-stages.sh --help`. Read-only-Prüfung: `bash scripts/07-health-check.sh`.

## Sicherheits- und Testgrenzen

- BCHN-Download wird gegen die SHA256-Prüfsumme der Referenzinstallation geprüft, **nicht** gegen eine unabhängig verifizierte Herausgebersignatur.
- CKPool-Patch wird nur bei erfolgreichem `git apply --check` angewendet; Commit-Kompatibilität ist auf einer neuen VM noch nicht nachgewiesen.
- Dashboard bietet keine Anmeldung: ausschließlich in einem vertrauenswürdigen LAN betreiben.
- `validateaddress` und das automatisch ermittelte `scriptPubKey` ersetzen keine Prüfung einer echten Solo-Coinbase und einer Miner-Share.
- RPC-Passwörter, private Schlüssel, Wallet-Seeds und erzeugte `bitcoin.conf`/`bchsolo.conf` niemals ins Repository committen.
