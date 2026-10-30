# Bitcoin Cash Mainnet Solo Mining Pool – Installer v1

Automatisierte **Testinstallation** für eine neue Debian-13-(Trixie)-VM auf x86_64. Enthält BCHN 29.2.0, den angepassten CKPool, das originale Flask-Dashboard, systemd-Dienste und Diagnose-Skripte.

**Status: Testkandidat – noch nicht auf einer frischen VM Ende-zu-Ende getestet.** Nicht auf dem produktiven Pool `debbch` ausführen. Der Branch `main` bleibt unverändert.

## Voraussetzungen

- Debian 13 ohne Desktop, SSH-Zugang, normaler Benutzer mit `sudo`
- Feste IPv4-Adresse im vertrauenswürdigen LAN
- Eigene **Bitcoin-Cash-Mainnet-Legacy-P2PKH-Adresse** (beginnt mit `1`); **niemals Seed oder privaten Schlüssel eingeben**
- Mindestens ca. 4 GB RAM empfohlen, ausreichend Speicherplatz und Internetverbindung; der BCHN-Download benötigt Zeit
- Noch **kein** BCHN, CKPool oder Dashboard auf dieser Test-VM

## Kurzanleitung

Nach der Debian-Installation auf der **neuen Test-VM** anmelden:

```bash
sudo apt-get update
sudo apt-get install -y git python3 openssl iproute2 sudo
git clone --branch installer-v1 https://github.com/matlen67/debian-bitcoincache-mining-pool.git
cd debian-bitcoincache-mining-pool
bash setup-pool.sh
```

Der Installer fragt nach der BCH-Auszahlungsadresse und der LAN-IP. Er erzeugt ein zufälliges RPC-Passwort und fragt vor Installationsschritten nach Bestätigung. Er installiert zunächst BCHN und kann dessen Synchronisierung starten.

**Während der Blockchain-Synchronisierung hält der Installer absichtlich an.** Den Fortschritt so prüfen:

```bash
sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo
```

Sobald `initialblockdownload` auf `false` steht und `blocks` mindestens `headers` erreicht hat, den Installer erneut starten:

```bash
bash setup-pool.sh
```

Er baut CKPool, installiert das Dashboard, validiert die Auszahlungsadresse über BCHN und richtet die Dienste ein. **CKPool und Dashboard werden noch nicht automatisch gestartet.**

Nach erfolgreichem Health-Check beide Dienste **bewusst** aktivieren:

```bash
bash scripts/07-health-check.sh
bash scripts/08-start-services.sh
```

Danach im LAN das Dashboard öffnen: `http://DEINE-SERVER-IP:8080/`. Miner verwenden die Server-IP mit Stratum-Port `3333`.

## Diagnose

```bash
sudo systemctl status bchn.service bch-ckpool.service bch-dashboard.service --no-pager
sudo journalctl -u bch-ckpool.service -n 80 --no-pager
sudo journalctl -u bch-dashboard.service -n 80 --no-pager
sudo ss -ltnp | grep -E ':(3333|8080) '
```

Bei Fehlern **nicht auf der produktiven VM nachstellen**. Die vollständige manuelle Referenz ist in [docs/INSTALLATIONSANLEITUNG-v2.md](docs/INSTALLATIONSANLEITUNG-v2.md). Einzelne Stufen: `bash run-stages.sh --help`.

## Originaldateien und Integrität

Alle acht Dateien aus dem getesteten Referenzpaket sind im Branch vorhanden: sechs Dashboard-Dateien, der [BCH-CKPool-Patch](patches/bch-ckpool-mainnet.patch) und die Installationsanleitung. Der Installer prüft ihre SHA256-Werte vor Beginn. **Es ist kein zusätzliches ZIP und kein manueller Import mehr erforderlich.**

Der Patch wird nur nach erfolgreichem `git apply --check` angewendet. Wenn der gepinnte CKPool-Commit nicht erreichbar ist oder der Patch nicht passt, stoppt die Installation.

## Sicherheits- und Testgrenzen

- Der BCHN-Download wird mit der SHA256-Prüfsumme der Referenzinstallation verglichen. Eine unabhängige Herausgebersignatur wurde noch nicht überprüft.
- Das Dashboard verwendet den Flask-Entwicklungsserver **ohne Login**. Port 8080 niemals ins öffentliche Internet freigeben.
- Noch nicht verifiziert: CKPool-Build auf einer neuen VM, Unix-Socket-Rechte, echte Miner-Shares, Blockeinreichung und Coinbase-Auszahlung.
- RPC-Zugangsdaten und `bitcoin.conf`/`bchsolo.conf` nicht committen; Wallet-Seeds und private Schlüssel werden nicht benötigt.
- Bei Installationsfehlern kann eine teilweise Einrichtung verbleiben. Auf einer **wegwerfbaren Test-VM mit Snapshot** testen.

## GitHub-Prüfung

[Installer static checks](.github/workflows/installer-checks.yml) prüft Bash-/Python-/JavaScript-Syntax und die SHA256-Werte der Originaldateien. Ein grüner Syntax-Check ersetzt **keinen** Ende-zu-Ende-Test.

