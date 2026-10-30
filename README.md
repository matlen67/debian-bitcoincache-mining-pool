# Bitcoin Cash Mainnet Solo Mining Pool – Installer v1

Automatisierte **Testinstallation** für eine neue Debian-13-(Trixie)-VM auf x86_64. Enthält BCHN 29.2.0, den angepassten CKPool, das originale Flask-Dashboard, systemd-Dienste und Diagnose-Skripte.

**Status: Testkandidat – der Installer lief auf einer bestehenden Test-VM erfolgreich durch; der Restore auf einer neuen VM ist noch nicht Ende-zu-Ende getestet.** Nicht auf dem produktiven Pool `debbch` ausführen. Der Branch `main` bleibt unverändert.

## Voraussetzungen

- Debian 13 ohne Desktop, SSH-Zugang; ein normaler Benutzer mit eingerichteten `sudo`-Rechten (bei Minimalinstallation ggf. erst einrichten)
- Feste IPv4-Adresse im vertrauenswürdigen LAN
- Eigene **Bitcoin-Cash-Mainnet-Legacy-P2PKH-Adresse** (beginnt mit `1`); **niemals Seed oder privaten Schlüssel eingeben**
- Mindestens ca. 4 GB RAM empfohlen, ausreichend Speicherplatz und Internetverbindung; der BCHN-Download benötigt Zeit
- Noch **kein** BCHN, CKPool oder Dashboard auf dieser Test-VM

## Kurzanleitung

Nach der Debian-Installation auf der **neuen Test-VM** anmelden. **Falls `sudo` noch nicht installiert ist**, zunächst als `root` anmelden (z. B. mit `su -`) und `sudo` installieren sowie dem eigenen Benutzer die Berechtigung geben:

```bash
su -
apt-get update
apt-get install -y sudo
usermod -aG sudo DEIN_BENUTZERNAME
exit
```

Danach **neu anmelden** (damit die Gruppenzugehörigkeit aktiv wird) und mit dem normalen Benutzer fortfahren:

```bash
sudo apt-get update
sudo apt-get install -y git python3 openssl iproute2
git clone --branch installer-v1 https://github.com/matlen67/debian-bitcoincache-mining-pool.git
cd debian-bitcoincache-mining-pool
bash setup-pool.sh
```

Der Installer fragt nach einer BCH-Legacy-Adresse als Konfigurations- und Dashboard-Referenz sowie nach der LAN-IP. **Im CKPool-Solo-Modus (`-B`) bestimmt jedoch die gültige BCH-Adresse im Stratum-Benutzernamen jedes Miners dessen eigene Coinbase-Auszahlung; die Konfigurationsadresse ist keine feste Auszahlung für alle Miner.** Er erzeugt ein zufälliges RPC-Passwort und fragt vor Installationsschritten nach Bestätigung. Er installiert zunächst BCHN und bietet vor dem ersten Node-Start die optionale Rücksicherung einer vorhandenen Blockchain an.

## Optionale Blockchain-Rücksicherung vom NAS (vor dem ersten Installer-Start)

Für einen Test mit einer **frischen Debian-13-VM** kann die vorhandene, geprüfte Sicherung genutzt werden. Das spart den Großteil der erstmaligen Blockchain-Synchronisierung. Das Archiv enthält möglicherweise RPC-Zugangsdaten und andere private Node-Dateien; deshalb nicht öffentlich freigeben.

Auf der neuen VM nach dem Klonen des Repositorys zunächst SMB/CIFS installieren und die Freigabe einbinden:

```bash
sudo apt-get install -y cifs-utils
sudo mkdir -p /mnt/bchnode-backup
sudo mount -t cifs //192.168.178.24/Filme /mnt/bchnode-backup -o username=share,vers=3.0
```

Das **SMB-Passwort** wird interaktiv abgefragt; nicht in Befehlen oder GitHub hinterlegen. Die Adresse und Freigabe sind das **konkrete Test-NAS** und müssen bei anderen Installationen entsprechend ersetzt werden.

Prüfen, ob das Archiv vorhanden und lesbar ist:

```bash
ls -lh /mnt/bchnode-backup/bchnode/bchn-blockchain.tar.gz
sudo tar -tzf /mnt/bchnode-backup/bchnode/bchn-blockchain.tar.gz >/dev/null
```

Danach im geklonten Repository als **normaler Benutzer** starten:

```bash
bash setup-pool.sh
```

Bei der Installation von BCHN fragt das Skript:

```text
Pfad zur bchn-blockchain.tar.gz (Enter = neu synchronisieren):
```

Dort eingeben:

```text
/mnt/bchnode-backup/bchnode/bchn-blockchain.tar.gz
```

Die Rücksicherung fragt nochmals nach Bestätigung. Sie übernimmt ausschließlich `blocks` und `chainstate` in die neu installierte BCHN-Datenablage, **nicht** die alte `bitcoin.conf`. Sie bricht ab, wenn bereits Blockchain-Verzeichnisse existieren, und überschreibt diese nicht. BCHN muss während der Rücksicherung gestoppt sein. Das Archiv stammt von einem pruned BCHN-Mainnet-Knoten; für den Test dieselbe BCHN-Version und Mainnet-Einstellungen verwenden.

Danach den ersten BCHN-Start bestätigen. BCHN prüft die Daten und lädt die seit der Sicherung fehlenden Blöcke nach. **Erst wenn `initialblockdownload=false` und `blocks >= headers` erreicht sind**, `bash setup-pool.sh` erneut ausführen. Dann installiert und startet der Installer CKPool und Dashboard automatisch.

**Wichtig:** Ein vollständiger Restore auf einer neuen VM ist noch nicht praktisch verifiziert. Die bisherige Test-VM und das NAS-Archiv nicht löschen, bevor dieser Test erfolgreich abgeschlossen ist.

**Während der Blockchain-Synchronisierung hält der Installer absichtlich an.** Den Fortschritt so prüfen:

```bash
sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo
```

Sobald `initialblockdownload` auf `false` steht und `blocks` mindestens `headers` erreicht hat, den Installer erneut starten:

```bash
bash setup-pool.sh
```

Er baut CKPool, installiert das Dashboard, validiert die Auszahlungsadresse über BCHN und richtet die Dienste ein. **CKPool und Dashboard werden nach erfolgreichem Health-Check automatisch gestartet und für den Autostart aktiviert.**

Der Installer prüft die Installation und aktiviert anschließend beide Dienste automatisch. Status prüfen:

```bash
sudo systemctl is-active bchn.service bch-ckpool.service bch-dashboard.service
```

Danach im LAN das Dashboard öffnen: `http://DEINE-SERVER-IP:8080/`. Miner verwenden die Server-IP mit Stratum-Port `3333` und als Benutzernamen `DEINE_BCH_LEGACY_ADRESSE.workername` (Passwort z. B. `x`). Bei einem Walletwechsel nur die Adresse im Miner ändern; CKPool muss dafür nicht neu konfiguriert werden. **Wichtig:** Die fest konfigurierte `PAYOUT_SCRIPT`-Referenz im Dashboard ist nicht automatisch eine vollständige Abbildung aller individuellen Miner-Auszahlungen. Dashboard-Anzeigen zur Auszahlung daher nicht ohne gesonderte Prüfung als verbindlich ansehen.

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
- **Getestet auf Debian 13 mit bereits synchronisierter BCHN:** Wiederholungsinstallation (`--reuse-bchn`), CKPool-/Dashboard-Dienststart und echte akzeptierte Bitaxe-Shares (0 Rejected im beobachteten Log). Zwei unterschiedliche BCH-Legacy-Adressen wurden als Stratum-Benutzernamen autorisiert; die jeweiligen P2PKH-Auszahlungsskripte wurden in den zusammengesetzten Coinbase-Daten eines empfangenen Mining-Jobs gefunden. Beide Adressen können zur selben Wallet gehören.
- **Noch nicht verifiziert:** Vollständige Neuinstallation inklusive BCHN-Synchronisierung auf frischer VM, unabhängige vollständige Dekodierung aller Coinbase-Ausgänge, tatsächlich gefundener/eingereichter Block und reale Blockauszahlung. Die bisherigen Coinbase-Tests prüfen das Vorkommen des erwarteten Skripts, nicht den erfolgreichen Mainnet-Blockfund.
- RPC-Zugangsdaten und `bitcoin.conf`/`bchsolo.conf` nicht committen; Wallet-Seeds und private Schlüssel werden nicht benötigt.
- Bei Installationsfehlern kann eine teilweise Einrichtung verbleiben. Auf einer **wegwerfbaren Test-VM mit Snapshot** testen.

## GitHub-Prüfung

[Installer static checks](.github/workflows/installer-checks.yml) prüft Bash-/Python-/JavaScript-Syntax und die SHA256-Werte der Originaldateien. Ein grüner Syntax-Check ersetzt **keinen** Ende-zu-Ende-Test.

