# Getestete Frischinstallation – Debian 13, BCHN, CKPool und Dashboard mit NAS-Rücksicherung

**Stand: 30.10.2026 · Branch: `installer-v1` · Testsystem: `bchscripttest` (Login `matten`)**

Diese Anleitung dokumentiert den erfolgreich durchgeführten Test auf einer **neuen** Debian-13-VM. **Nicht auf der produktiven VM `debbch` ausführen.** Die bisherige Test-VM und das NAS-Archiv unangetastet lassen. Das Repository-`main` wird nicht verändert.

## Voraussetzungen

- Debian 13 (Trixie), x86_64, Netzwerk, SSH und normaler Login mit `sudo`-Rechten
- Eigene **öffentliche** BCH-Mainnet-Legacy-P2PKH-Adresse (beginnt mit `1`); niemals Seed oder privaten Schlüssel eingeben
- Optional: vertrauenswürdiges BCHN-29.2.0-Backup einer **gestoppten** Node mit `bch-node/blocks` und `bch-node/chainstate`
- DHCP-Reservierung empfohlen, damit Miner und Dashboard nach Neustarts unter derselben IP erreichbar bleiben

Bei einer Debian-Minimalinstallation ohne `sudo` als root `apt-get update && apt-get install -y sudo` und `usermod -aG sudo BENUTZER` ausführen, danach **neu anmelden**.

## 1. Repository vorbereiten

Als **normaler Benutzer**, nicht mit `sudo bash`:

```bash
sudo apt-get update
sudo apt-get install -y git python3 openssl iproute2
git clone --branch installer-v1 https://github.com/matlen67/debian-bitcoincache-mining-pool.git
cd debian-bitcoincache-mining-pool
```

Der Installer erkennt die Server-IPv4 automatisch über die Standardroute (vergleichbar mit `ip -4 route get 1.1.1.1`) und zeigt sie vor dem Speichern an. Bei mehreren Netzwerkkarten unbedingt prüfen, ob die erkannte IP die gewünschte LAN-IP ist.

## 2. Optional: Blockchain-Sicherung vom NAS bereitstellen

Die **konkreten Testwerte** waren SMB-Server `192.168.178.24`, Freigabe `Filme`, Unterordner `bchnode`, Archiv `bchn-blockchain.tar.gz`. Bei anderen NAS-Installationen entsprechend ersetzen.

```bash
sudo apt-get install -y cifs-utils smbclient
sudo mkdir -p /mnt/bchnode-backup
```

SMB-Zugangsdaten **nicht in die Shell-History, GitHub oder die Anleitung schreiben**. Auf der Test-VM wurde eine nur für root lesbare Datei `/root/.smbcredentials` mit `username=...`, `password=...` und optional `domain=WORKGROUP` angelegt (`sudo chmod 600 /root/.smbcredentials`). Die Freigabe wird dann eingebunden:

```bash
findmnt /mnt/bchnode-backup || sudo mount -t cifs //192.168.178.24/Filme /mnt/bchnode-backup -o credentials=/root/.smbcredentials,vers=3.0
ls -lh /mnt/bchnode-backup/bchnode/bchn-blockchain.tar.gz
sudo tar -tzf /mnt/bchnode-backup/bchnode/bchn-blockchain.tar.gz >/dev/null && echo "Blockchain-Archiv OK"
```

Die Archivprüfung kann bei mehreren GB dauern. Erst nach `Blockchain-Archiv OK` fortfahren. `mount error(16): Device or resource busy` kann schlicht bedeuten, dass das NAS bereits eingehängt ist: `findmnt /mnt/bchnode-backup` prüfen.

**Sicherheit:** Das vollständige Archiv kann alte RPC-Zugangsdaten enthalten. Nicht öffentlich teilen. Das Restore-Skript übernimmt ausschließlich `blocks` und `chainstate`, **nicht** die gesicherte `bitcoin.conf`. Die neue Konfiguration und neue RPC-Zugangsdaten bleiben erhalten. Das Skript verweigert die Rücksicherung bei laufendem BCHN oder bereits vorhandenen Blockchain-Verzeichnissen.

## 3. Installer starten und Restore auswählen

```bash
bash setup-pool.sh
```

- Eigene BCH-Legacy-Referenzadresse eingeben und automatisch ermittelte IP kontrollieren
- BCHN 29.2.0 herunterladen/installieren bestätigen
- Bei der Frage nach dem Archivpfad im Test eingeben: `/mnt/bchnode-backup/bchnode/bchn-blockchain.tar.gz`
- Rücksicherung von Blöcken und Chainstate bestätigen
- BCHN-Start bestätigen

Beim ersten Node-Start kann `bitcoin-cli` `error code: -28` mit `Verifying wallet...` melden. Das ist zunächst eine Startphase; der Installer hält sicher an. **Nicht die Installation von CKPool erzwingen.**

Synchronisierung prüfen:

```bash
sudo -u bchn /usr/local/bin/bitcoin-cli \
  -datadir=/var/lib/bch-node \
  -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo
```

Erst bei `chain=main`, `initialblockdownload=false` und `blocks >= headers` erneut starten:

```bash
bash setup-pool.sh
```

Der Installer installiert dann CKPool und Dashboard, prüft die Voraussetzungen und startet die Dienste. Im Test wurde ein wiederhergestellter pruned Mainnet-Stand von **975242 Blöcken** unmittelbar erfolgreich erkannt; später meldete der Installer **975244 Blöcke**.

## 4. Erreichbarkeit und Dienste prüfen

```bash
sudo systemctl is-active bchn.service bch-ckpool.service bch-dashboard.service
sudo systemctl show bch-dashboard.service -p Environment
sudo ss -tlnp | grep -E ':(3333|8080) '
```

Dashboard: **`http://SERVER-IP:8080/`** (nicht 5000). Miner: **`SERVER-IP:3333`**; Stratum-Benutzer ist die jeweilige gültige BCH-Legacy-Adresse, optional mit Worker-Suffix, Passwort etwa `x`. Der CKPool-Solo-Modus `-B` verwendet die jeweilige Miner-Adresse; die Referenzadresse im Setup ist keine zentrale Auszahlung für alle Miner.

Der BCHN-Dienst läuft als `bchn`; CKPool und Dashboard laufen unter dem installierenden Benutzer (im Test `matten`), **nicht** unter einem eigens angelegten `pooladmin`.

## 5. Fehler aus dem Praxistest und dauerhafte Abhilfe

**Symptom:** Installer meldet Erfolg, aber Dashboard ist nicht erreichbar. `systemctl status bch-dashboard.service` zeigt `activating (auto-restart)`; im Journal steht `Cannot assign requested address`.

**Ursache im Test:** Die ursprünglich manuell eingegebene falsche Adresse `192.168.178.136` stand noch in der bereits erzeugten systemd-Unit. Die VM hatte tatsächlich `192.168.178.128` auf `ens18`. Eine Korrektur in `~/.config/bch-solo-installer/setup.env` aktualisiert bestehende Units **nicht** automatisch.

**Installer-Änderung:** Neue Installationen erkennen die IP automatisch. Die Dashboard-Unit bindet Flask an `DASHBOARD_HOST=0.0.0.0` auf TCP 8080, damit DHCP-Adresswechsel keinen Bind-Fehler erzeugen; `STRATUM_HOST` wird mit der beim Setup ermittelten Server-IP gesetzt. Der Abschlusscheck wartet zusätzlich auf einen tatsächlich erreichbaren lokalen TCP-Port 8080 und einen weiterhin aktiven Dienst.

**Bestehende Test-VM reparieren:** Zuerst tatsächliche IP (`ip -4 addr show`) und gespeicherte Unit (`sudo systemctl show bch-dashboard.service -p Environment`) vergleichen. Falls die Unit noch eine falsche IP enthält, diese **gezielt** in `/etc/systemd/system/bch-dashboard.service` korrigieren, anschließend:

```bash
sudo systemctl daemon-reload
sudo systemctl restart bch-dashboard.service
sudo systemctl is-active bch-dashboard.service
sudo ss -tlnp | grep ':8080 '
sudo journalctl -u bch-dashboard.service -n 30 --no-pager
```

Die Änderung an `DASHBOARD_HOST=0.0.0.0` vergrößert die erreichbaren Interfaces: **Dashboard nur im vertrauenswürdigen LAN, niemals Port 8080 ins Internet weiterleiten**. Das Dashboard hat keinen Login. Bei einer späteren IP-Änderung außerdem die angezeigte `STRATUM_HOST`-Adresse und CKPool-Konfiguration prüfen.

## 6. Testgrenzen

Erfolgreich geprüft: frische Debian-13-VM, unabhängiger Login-Name, BCHN-29.2.0-Installation, NAS-Archivprüfung, Restore von Blöcken/Chainstate, Mainnet-Synchronisierung, CKPool-Installation/-Dienststart, Dashboard-Start und Browser-Erreichbarkeit auf TCP 8080.

**Noch nicht durch diesen Frischinstallationstest bewiesen:** Vollsynchronisierung ohne Backup ab Genesis, tatsächlicher Blockfund und reale BCH-Auszahlung. Vor produktivem Einsatz weitere Miner- und Auszahlungsprüfungen durchführen.

Die ältere `docs/INSTALLATIONSANLEITUNG-v2.md` bleibt **unverändert**, weil der Installer ihren SHA256-Referenzwert kontrolliert. Ihre frühere Benutzer-/Installationsstruktur ist für den aktuellen automatischen Installer nicht maßgeblich.
