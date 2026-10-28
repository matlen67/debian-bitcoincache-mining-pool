> [!WARNING]
> # Achtung! Die Anleitung ist noch nicht getestet. Ich habe den Mining-Pool erstellt und er läuft, eine Auszahlung erfolgte bisher nur im Testnet4 und nicht im Mainnet. Die Anleitung wurde aus meinen Installationsschritten erstellt.
<br>
<br>
# Bitcoin Cash MAINNET Solo-Mining-Pool – Installationsanleitung

**Stand:** 28. Oktober 2026 · **Ziel:** Debian 13 (Trixie), BCHN 29.2.0, angepasster CKPool, Flask-Dashboard · **Keine Testnet-Konfiguration**

> **Geltungsbereich:** Dies ist eine reproduzierbare Installationsvorlage aus den Dateien und Einstellungen der funktionierenden Referenz-VM. Sie wurde **nicht auf einer zweiten frischen VM Ende-zu-Ende getestet**. Alle Befehle ausschließlich auf einer **neuen** VM ausführen, **nicht** auf dem produktiven Server. Besonders RPC-Anmeldung, Patch und Miner-Betrieb vor produktiver Nutzung testen.

## Inhaltsverzeichnis

1. Überblick und Platzhalter
2. Debian 13 vorbereiten
3. BCHN 29.2.0 installieren und prüfen
4. BCHN Mainnet konfigurieren und synchronisieren
5. CKPool-Quellen und lokalen Patch einspielen
6. CKPool konfigurieren und starten
7. Dashboard installieren
8. Drei systemd-Dienste und Rechte
9. Tests, Miner und Fehlersuche
10. Betrieb, Updates, Sicherheit und Grenzen

## 1. Überblick und Platzhalter

**Referenzsystem:** Debian 13, 2 vCPU, 11 GiB RAM, 128 GB Disk, 6,5 GB Swap. Für Neuinstallation: 2+ vCPU, 12 GB RAM, zunächst mindestens 64 GB **erweiterbare** Disk; freie Kapazität überwachen. Pruning reduziert langfristige Blockchain-Daten, verhindert aber nicht temporären Speicherbedarf. Netzwerk: feste LAN-IP, SSH. Ports: BCH-P2P TCP 8333, BCH-RPC TCP 8332 **nur localhost**, Stratum TCP 3333 im LAN, Dashboard TCP 8080 im LAN.

**Architektur:** ASIC-Miner → CKPool (Stratum 3333) ↔ BCHN (RPC 8332); Dashboard (Flask 8080) liest BCHN-RPC, CKPool-Unix-Socket und CKPool-Log.

**Beispielwerte in dieser Anleitung – vor der Inbetriebnahme anpassen:**

| Einstellung | Beispielwert | Was muss ich ändern? |
|---|---|---|
| Server-IP | `192.168.1.50` | Durch die feste LAN-IP der neuen VM ersetzen; überall dieselbe IP verwenden |
| BCH-Auszahlungsadresse | `HIER_EIGENE_BCH_MAINNET_ADRESSE_EINTRAGEN` | Durch die **eigene öffentliche BCH-Mainnet-Empfangsadresse** ersetzen |
| RPC-Benutzer | `bchpool` | Kann so bleiben; muss in `bitcoin.conf` und `bchsolo.conf` identisch sein |
| RPC-Passwort | `HIER_EIGENES_SICHERES_RPC_PASSWORT_EINTRAGEN` | Durch ein mit `openssl rand -hex 32` erzeugtes Passwort ersetzen; in beiden Dateien identisch |
| Coinbase-Signatur | `Mein BCH Solo Pool` | Optionaler kurzer, selbst gewählter Text |
| Auszahlungs-Script | `HIER_EIGENEN_SCRIPTPUBKEY_IN_HEX_EINTRAGEN` | Durch den zur eigenen BCH-Adresse gehörenden `scriptPubKey` ersetzen; siehe Kapitel 7 |
| Minername | `miner01` | Frei wählbarer Name des ASIC-Miners |

**Wichtig:** Texte wie `HIER_EIGENE_BCH_MAINNET_ADRESSE_EINTRAGEN` sind **keine gültigen Konfigurationswerte**. Dienste erst starten, wenn alle so gekennzeichneten Angaben ersetzt wurden. Die IP `192.168.1.50` ist ein Beispiel und muss zur neuen VM passen.

Das begleitende Paket `bch-mainnet-installationspaket.zip` enthält **Originaldateien des bereitgestellten Dashboards** und den **CKPool-Quellpatch**, nicht den kompletten CKPool-Quellbaum oder BCHN-Binärdateien.

## 2. Debian 13 vorbereiten

Auf einer frisch installierten Debian-13-VM mit sudo-Benutzer:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y curl wget git ca-certificates gnupg tar gzip jq \
  build-essential yasm autoconf automake libtool pkgconf \
  libzmq3-dev libsodium-dev libcurl4-openssl-dev libjansson-dev libssl-dev \
  python3 python3-venv python3-pip
sudo reboot
```

Nach erneutem SSH-Login:

```bash
cat /etc/os-release
python3 --version
gcc --version
```

**Systembenutzer:** `bchn` betreibt Node und Dashboard; `pooladmin` betreibt CKPool. Die Benutzer sind nicht für interaktive Anmeldung gedacht.

```bash
sudo useradd --system --user-group --home-dir /var/lib/bch-node --shell /usr/sbin/nologin bchn
sudo useradd --system --user-group --home-dir /opt/bch-solo-pool --shell /usr/sbin/nologin pooladmin
sudo install -d -o bchn -g bchn -m 750 /var/lib/bch-node
sudo install -d -o pooladmin -g pooladmin -m 750 /opt/bch-solo-pool
sudo usermod -aG pooladmin bchn
```

Bei bereits existierenden Benutzern nicht erneut `useradd` ausführen. Alle weiteren Pfade setzen diese Benutzer voraus.

## 3. BCHN 29.2.0 installieren und prüfen

**Release:** https://github.com/bitcoin-cash-node/bitcoin-cash-node/releases/tag/v29.2.0

```bash
cd /tmp
wget -O bitcoin-cash-node-29.2.0-x86_64-linux-gnu.tar.gz \
  https://github.com/bitcoin-cash-node/bitcoin-cash-node/releases/download/v29.2.0/bitcoin-cash-node-29.2.0-x86_64-linux-gnu.tar.gz
sha256sum bitcoin-cash-node-29.2.0-x86_64-linux-gnu.tar.gz
```

**SHA256 des auf der Referenz-VM vorhandenen Archivs:**

```text
23bbe9ff749136a9b832a2a59023ce76a5391322c1ea2f4f24b5b91f035081bc
```

Prüfung:

```bash
echo '23bbe9ff749136a9b832a2a59023ce76a5391322c1ea2f4f24b5b91f035081bc  bitcoin-cash-node-29.2.0-x86_64-linux-gnu.tar.gz' | sha256sum -c -
```

**Sicherheits-Hinweis:** Diese Prüfsumme ist aus dem lokalen Referenzarchiv bekannt; die Echtheit des Herausgebers ist damit **nicht** bewiesen. Zusätzlich die signierten Release-Checksums/GPG-Schlüssel von der offiziellen Projektseite verifizieren. Bei Abweichung **nicht installieren**.

```bash
tar -xzf bitcoin-cash-node-29.2.0-x86_64-linux-gnu.tar.gz
sudo install -m 755 bitcoin-cash-node-29.2.0/bin/bitcoind /usr/local/bin/bitcoind
sudo install -m 755 bitcoin-cash-node-29.2.0/bin/bitcoin-cli /usr/local/bin/bitcoin-cli
/usr/local/bin/bitcoind --version
```

Referenzversion: `v29.2.0-07576013c`. Keine Kompilierung von BCHN erforderlich.

## 4. BCHN Mainnet konfigurieren und synchronisieren

Ein eigenes, zufälliges RPC-Passwort erzeugen:

```bash
openssl rand -hex 32
```

Die Ausgabe sicher notieren und **denselben Wert** in `bitcoin.conf` und `bchsolo.conf` anstelle von `HIER_EIGENES_SICHERES_RPC_PASSWORT_EINTRAGEN` einsetzen. `bitcoin.conf` wird nur vom Benutzer `bchn` gelesen; Dashboard-RPC nutzt später dessen Cookie.

```bash
sudo nano /var/lib/bch-node/bitcoin.conf
```

**Inhalt:** `bchpool` ist ein verwendbarer Benutzername. Das RPC-Passwort unbedingt durch den zuvor erzeugten Wert ersetzen:

```ini
server=1
daemon=0
prune=550
txindex=0
dbcache=2048
listen=1
port=8333
maxconnections=32
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=8332
blocksonly=0
rpcuser=bchpool
rpcpassword=HIER_EIGENES_SICHERES_RPC_PASSWORT_EINTRAGEN
```

Die Referenzinstallation nutzt `rpcauth`; die Vorlage verwendet zur einfacheren Reproduktion `rpcuser`/`rpcpassword` mit strikten Dateirechten und localhost-Bindung. Für langfristigen Betrieb kann auf `rpcauth` umgestellt werden. **Nie RPC-Port 8332 im Router oder LAN freigeben.**

```bash
sudo chown bchn:bchn /var/lib/bch-node/bitcoin.conf
sudo chmod 600 /var/lib/bch-node/bitcoin.conf
sudo nano /etc/systemd/system/bchn.service
```

```ini
[Unit]
Description=Bitcoin Cash Node (Mainnet)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=bchn
Group=bchn
WorkingDirectory=/var/lib/bch-node
ExecStart=/usr/local/bin/bitcoind -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf
ExecStop=/usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node stop
Restart=on-failure
RestartSec=10
TimeoutStopSec=300
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bchn.service
sudo systemctl status bchn.service --no-pager
sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node getblockchaininfo
```

Die Synchronisierung kann je nach Hardware und Netzwerk lange dauern. `initialblockdownload` muss vor produktivem Mining `false` sein und `blocks`/`headers` sollten übereinstimmen. Prüfen:

```bash
sudo -u bchn bitcoin-cli -datadir=/var/lib/bch-node getblockchaininfo | jq '{chain,blocks,headers,initialblockdownload,verificationprogress,pruned}'
sudo -u bchn bitcoin-cli -datadir=/var/lib/bch-node getconnectioncount
```

Wenn RPC-Authentifizierung als `bchn` trotz Cookie nicht klappt, `bitcoin-cli` explizit mit `-conf=/var/lib/bch-node/bitcoin.conf` aufrufen; Konfigurationsrechte kontrollieren. Keine Credentials in Shell-History kopieren.

## 5. CKPool-Quellen und lokalen Patch einspielen

**Quellcode-Repository:** https://bitbucket.org/ckolivas/ckpool.git

**Festgehaltener Referenz-Commit:** `1f5a92013be5c314b5645785fdf60396b008721c`.

**Benötigte Paketdatei:** `bch-ckpool-mainnet.patch` aus dem mitgelieferten ZIP. Sie enthält die drei lokalen Änderungen an `src/bitcoin.c`, `src/ckpool.h` und `src/stratifier.c`, unter anderem die Unix-Socket-API-Antwort für das Dashboard.

```bash
sudo -u pooladmin git clone https://bitbucket.org/ckolivas/ckpool.git /opt/bch-solo-pool/ckpool
cd /opt/bch-solo-pool/ckpool
sudo -u pooladmin git checkout 1f5a92013be5c314b5645785fdf60396b008721c
sudo -u pooladmin git submodule update --init --recursive
sudo -u pooladmin git submodule status
```

Die Referenz hatte `src/secp256k1` auf Commit `ebf594320dc838b9de1abb54d5ba98cef84f4297`.

Den Patch aus dem Installationspaket in `/tmp/bch-ckpool-mainnet.patch` kopieren (beispielsweise per `scp`). Danach:

```bash
cd /opt/bch-solo-pool/ckpool
sudo -u pooladmin git apply --check /tmp/bch-ckpool-mainnet.patch
sudo -u pooladmin git apply /tmp/bch-ckpool-mainnet.patch
sudo -u pooladmin ./autogen.sh
sudo -u pooladmin ./configure
sudo -u pooladmin make -j"$(nproc)"
ls -lh src/ckpool
ldd src/ckpool
```

**Hinweise:** Der lokale Patch wurde auf der Referenz-VM gegen den obigen Commit geprüft. Er ist kein offizieller BCHN/CKPool-Upstream-Patch. Nicht ohne Prüfung auf einen anderen Commit anwenden. Der Build kann `-march=native` verwenden: **auf der Ziel-VM kompilieren**, kein fremdes Binary kopieren. Falls `git apply --check` fehlschlägt: stoppen, keine erzwungene Patch-Anwendung.

## 6. CKPool konfigurieren und starten

Erforderlich sind die eigene **Mainnet**-BCH-Auszahlungsadresse und die in Kapitel 4 eingerichteten RPC-Zugangsdaten. Die Referenzkonfiguration verwendet Solo-Modus `-B`, Stratum-Port 3333, `mindiff=1`, `startdiff=1000`.

```bash
sudo -u pooladmin nano /opt/bch-solo-pool/ckpool/bchsolo.conf
```

```json
{
  "btcd": [
    {"url":"127.0.0.1:8332","auth":"bchpool","pass":"HIER_EIGENES_SICHERES_RPC_PASSWORT_EINTRAGEN","notify":false}
  ],
  "btcaddress": "HIER_EIGENE_BCH_MAINNET_ADRESSE_EINTRAGEN",
  "btcsig": "Mein BCH Solo Pool",
  "blockpoll": 100,
  "donation": 0,
  "nonce1length": 4,
  "nonce2length": 8,
  "update_interval": 30,
  "version_mask": "1fffe000",
  "dropidle": 0,
  "serverurl": ["192.168.1.50:3333"],
  "mindiff": 1,
  "startdiff": 1000,
  "maxdiff": 0,
  "logdir": "logs"
}
```

Die Konfiguration entspricht der Referenz mit verständlichen Beispielwerten. Vor dem Start eigene BCH-Adresse, RPC-Passwort und tatsächliche Server-IP einsetzen. **Wallet-Adressformat unbedingt mit CKPool/BCHN prüfen**; nicht mit einem Testnet-Ziel oder einer Bitcoin-Wallet verwechseln. Die Adresse bestimmt, wohin eine gefundene Coinbase-Auszahlung geht. `donation=0` entspricht der Referenz, ist keine allgemeine Empfehlung für fremde Pools.

```bash
sudo chmod 600 /opt/bch-solo-pool/ckpool/bchsolo.conf
sudo install -d -o pooladmin -g pooladmin -m 750 /opt/bch-solo-pool/ckpool/logs
sudo nano /etc/systemd/system/bch-ckpool.service
```

```ini
[Unit]
Description=Bitcoin Cash Solo Mining Pool (CKPool)
Wants=network-online.target
After=network-online.target bchn.service
Requires=bchn.service

[Service]
Type=simple
User=pooladmin
Group=pooladmin
WorkingDirectory=/opt/bch-solo-pool/ckpool
ExecStart=/opt/bch-solo-pool/ckpool/src/ckpool -B -c bchsolo.conf
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

**Erst starten, wenn BCHN vollständig synchronisiert ist.**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bch-ckpool.service
sudo systemctl status bch-ckpool.service --no-pager
sudo journalctl -u bch-ckpool.service -n 80 --no-pager
sudo ss -ltnp | grep ':3333'
```

Der CKPool-API-Socket sollte unter `/tmp/ckpool/stratifier` entstehen. Der Benutzer `bchn` wurde in Kapitel 2 der Gruppe `pooladmin` zugeordnet und kann damit bei den Referenzrechten auf den Socket und die Logs zugreifen. Nach Gruppenänderungen Dienste neu starten, damit die Mitgliedschaft übernommen wird.

## 7. Dashboard installieren

**Mitgelieferte Dateien** (Originalstand der Referenz-VM):

```text
app.py
ckpool_api.py
block_history.py
templates/index.html
static/script.js
static/style.css
```

**Dateien aus dem ZIP** in das Zielverzeichnis `/opt/bch-solo-pool/webinterface/bch-solo-dashboard/` kopieren. Beispiel: Das ZIP liegt auf der neuen VM in `/tmp/bch-mainnet-installationspaket.zip`.

```bash
sudo apt install -y unzip
sudo install -d -o bchn -g bchn -m 750 /opt/bch-solo-pool/webinterface
sudo install -d -o bchn -g bchn -m 750 /opt/bch-solo-pool/webinterface/bch-solo-dashboard
cd /tmp
unzip -o bch-mainnet-installationspaket.zip -d bch-install
sudo cp -a bch-install/dashboard/. /opt/bch-solo-pool/webinterface/bch-solo-dashboard/
sudo chown -R bchn:bchn /opt/bch-solo-pool/webinterface
sudo -u bchn python3 -m venv /opt/bch-solo-pool/webinterface/venv
sudo -u bchn /opt/bch-solo-pool/webinterface/venv/bin/python -m pip install \
  'Flask==3.1.3'
```

Die Referenz verwendete Python 3.13.5 und Flask 3.1.3; `pip` installiert die zugehörigen Abhängigkeiten. Für vollständig reproduzierbare Pakete später ein geprüften `requirements.lock` mit Hashes erstellen.

### 7.1 Wichtige Anpassung: individuelle Wallet-Auszahlung

In `block_history.py` ist im Referenzstand folgender **walletspezifischer** Wert fest eingetragen:

```python
PAYOUT_SCRIPT = (
    "76a914cb253d57d470b7309c3c1ac8a17c0ce418df5c8388ac"
)
```

**Unbedingt durch den scriptPubKey der eigenen BCH-Auszahlungsadresse ersetzen**, sonst kann die Dashboard-Blockverifikation fälschlich `not_verified` melden. Die passende HEX-Ausgabe kann, sofern BCHN die Adresse erkennt, mit diesem Befehl geprüft werden:

```bash
sudo -u bchn bitcoin-cli -datadir=/var/lib/bch-node validateaddress 'HIER_EIGENE_BCH_MAINNET_ADRESSE_EINTRAGEN'
```

Prüfen, ob `isvalid: true` und ein `scriptPubKey`-Feld vorhanden sind. Nicht blind irgendeinen Hash aus der Adresse übernehmen; das Script muss zur tatsächlich in CKPool verwendeten Auszahlungsadresse passen. Falls das RPC-Ergebnis kein Script liefert, diesen Schritt anhand eines verifizierten BCH-Adressdecoders und eines Testblocks gesondert klären. Der Beispielwert darf **nicht** stehen bleiben.

### 7.2 Dashboard-Adresse und Umgebungsvariablen

`app.py` enthält in der Referenz IP-Defaults der ursprünglichen VM. Im neuen systemd-Dienst werden diese **ohne Änderung der Originaldatei** überschrieben:

```bash
sudo nano /etc/systemd/system/bch-dashboard.service
```

```ini
[Unit]
Description=BCH Solo Pool Dashboard
After=network.target bchn.service bch-ckpool.service
Wants=bchn.service bch-ckpool.service

[Service]
Type=simple
User=bchn
Group=bchn
WorkingDirectory=/opt/bch-solo-pool/webinterface/bch-solo-dashboard
Environment=DASHBOARD_HOST=192.168.1.50
Environment=STRATUM_HOST=192.168.1.50
Environment=STRATUM_PORT=3333
Environment=BCH_DATADIR=/var/lib/bch-node
Environment=BITCOIN_CLI=/usr/local/bin/bitcoin-cli
ExecStart=/opt/bch-solo-pool/webinterface/venv/bin/python app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`192.168.1.50` in beiden Environment-Zeilen durch die tatsächliche feste IP der neuen VM ersetzen. Das Dashboard läuft wie auf der Referenz-VM mit dem Flask-Entwicklungsserver (`app.run`). **Nur für ein vertrauenswürdiges LAN** geeignet, nicht ungeschützt ins Internet stellen. Für öffentliche Bereitstellung: produktiven WSGI-Server, Reverse Proxy, TLS und Authentifizierung ergänzen.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bch-dashboard.service
sudo systemctl status bch-dashboard.service --no-pager
sudo journalctl -u bch-dashboard.service -n 60 --no-pager
```

Dashboard im Browser beispielsweise unter `http://192.168.1.50:8080/` öffnen (mit der tatsächlichen Server-IP).

### 7.3 Zugriff auf CKPool-API und Log prüfen

```bash
id bchn
ls -ld /tmp/ckpool
ls -l /tmp/ckpool/stratifier
ls -ld /opt/bch-solo-pool/ckpool/logs
sudo -u bchn test -r /opt/bch-solo-pool/ckpool/logs/ckpool.log && echo 'Log lesbar'
```

Wenn der Socket oder das Log nicht lesbar ist: Besitz-/Gruppenrechte und die Mitgliedschaft von `bchn` in `pooladmin` kontrollieren. **Nicht** mit `chmod 777` umgehen.

## 8. Dienste und Startreihenfolge

| Dienst | Benutzer | Pfad | Zweck |
|---|---|---|---|
| `bchn.service` | `bchn` | `/usr/local/bin/bitcoind` | Blockchain und RPC |
| `bch-ckpool.service` | `pooladmin` | `/opt/bch-solo-pool/ckpool/src/ckpool` | Solo-Stratum und Mining |
| `bch-dashboard.service` | `bchn` | `.../venv/bin/python app.py` | Web-Dashboard |

```bash
sudo systemctl is-enabled bchn bch-ckpool bch-dashboard
sudo systemctl --no-pager --full status bchn bch-ckpool bch-dashboard
sudo ss -ltnp | grep -E ':(8332|8333|3333|8080)\b'
```

**Sicherheitscheck:** Port 8332 muss an `127.0.0.1` gebunden sein. Port 8333 ist der BCH-P2P-Port, nicht mit RPC 8332 verwechseln.

## 9. Funktionstests und Miner verbinden

### 9.1 Node

```bash
sudo -u bchn bitcoin-cli -datadir=/var/lib/bch-node getblockchaininfo | jq '{chain,blocks,headers,initialblockdownload,verificationprogress,pruned}'
sudo -u bchn bitcoin-cli -datadir=/var/lib/bch-node getnetworkinfo | jq '{connections,version,subversion}'
```

Soll: `chain="main"`, `initialblockdownload=false`, sinnvolle Peerzahl, `blocks` gleich `headers`.

### 9.2 CKPool

```bash
sudo systemctl is-active bch-ckpool
sudo journalctl -u bch-ckpool -n 100 --no-pager
sudo ss -ltnp | grep ':3333'
```

Soll: Dienst aktiv, Listener auf Stratum 3333, keine RPC-Authentifizierungsfehler, keine Blocktemplate-Fehler. Die Existenz eines offenen Ports allein beweist noch nicht, dass Shares korrekt verarbeitet werden.

### 9.3 Dashboard

```bash
sudo systemctl is-active bch-dashboard
curl -fsS http://192.168.1.50:8080/api/status | jq .
```

Soll: JSON-Antwort mit Node- und Mining-Daten. Die Dashboard-Datei verwendet zusätzlich die CKPool-API-Befehle `poolstats`, `clients`, `workers`; diese funktionieren nur mit der mitgelieferten CKPool-Anpassung und passendem Socketzugriff.

### 9.4 ASIC-Miner

In der Miner-Weboberfläche konfigurieren:

```text
Stratum URL: stratum+tcp://192.168.1.50:3333
Worker:      HIER_EIGENE_BCH_MAINNET_ADRESSE_EINTRAGEN.miner01  (nur falls vom verwendeten CKPool/Miner so erwartet)
Passwort:    x
```

**Achtung:** Der konkrete Workername kann je nach Miner und CKPool-Solo-Modus abweichen. Vor echtem Mining einen Testminer verbinden und im CKPool-Log die Worker-Zuordnung, akzeptierte Shares und die tatsächlich konfigurierte **BCH-Mainnet-Auszahlungsadresse** prüfen. Ein Dashboard mit Hashrate ist noch kein Nachweis einer korrekten Auszahlung.

### 9.5 Prüfprotokoll für Abnahme

- [ ] `bitcoind --version` zeigt BCHN 29.2.0.
- [ ] Node zeigt `chain=main`, IBD `false` und aktuelle Blockhöhe.
- [ ] RPC nur auf localhost, `bitcoin.conf` mit Modus `600`.
- [ ] CKPool-Patch ohne Fehler auf Referenz-Commit angewandt und kompiliert.
- [ ] CKPool-Log zeigt gültige RPC-/Template-Kommunikation.
- [ ] Eigene Mainnet-Auszahlungsadresse ist in `bchsolo.conf` korrekt.
- [ ] Dashboard-`PAYOUT_SCRIPT` stimmt mit der eigenen Adresse überein.
- [ ] Socketrechte erlauben Dashboard-Abfragen.
- [ ] Stratum-Miner verbindet sich und liefert akzeptierte Shares.
- [ ] Dashboard zeigt Node, Miner und Hashrate plausibel.
- [ ] Nach Neustart starten alle Dienste wieder.

## 10. Betrieb, Sicherheit, Updates und Grenzen

**Sicherheit:** Nur LAN/VPN-Zugriff auf 3333 und 8080; 8332 niemals öffentlich freigeben. Eigene BCH-Wallet sicher verwahren; im Pool liegt nur die **öffentliche Empfangsadresse**, kein Seed/Private Key. Keine RPC-Zugangsdaten in Git oder Screenshots veröffentlichen. SSH-Schlüssel verwenden. Dashboard hat in der Originalversion keine Benutzeranmeldung. Zugriff im LAN begrenzen.

**Monitoring:**

```bash
sudo journalctl -u bchn -f
sudo journalctl -u bch-ckpool -f
sudo journalctl -u bch-dashboard -f
df -h /
free -h
```

**Updates:** Vor Änderungen Sicherung der drei systemd-Dateien, der `bitcoin.conf`, `bchsolo.conf`, Dashboard-Quellen und des Patches erstellen. BCHN-Updates separat testen; CKPool-Updates können den Patch unbrauchbar machen. Keine `git pull`- oder unkontrollierten `pip install -U`-Updates auf dem laufenden Pool. Keine Updates während kritischer Diagnose.

**Pruning:** `prune=550` ist die BCHN-Einstellung in MiB für die Zielgröße alter Blockdaten, **nicht** die maximale Gesamtgröße des Datadir. Blockhistorie, Index und UTXO-Daten brauchen zusätzlichen Speicher. Alte Blockdetails können wegen Pruning nicht mehr abrufbar sein; `block_history.py` meldet dann ggf. `unknown`.

**Dashboard-Grenzen:** Der Originalstand von `block_history.py` gleicht Coinbase-Auszahlungen anhand eines festen scriptPubKey ab. Ohne individuelle Anpassung funktioniert die Verifikation nicht korrekt. Die Dashboard-API nutzt einen von unserem Patch ergänzten Unix-Socket-Antwortpfad. Flask läuft ohne Produktions-WSGI und ohne Authentifizierung. Dashboard-Zahlen und Blockchance sind Anzeigen, keine Erfolgsgarantie.

**Mining-Risiko:** Solo-Mining ist zufallsabhängig; auch bei dauerhaft gültigen Shares kann über lange Zeit kein Block gefunden werden. Das Finden eines Blocks ist nicht gleichbedeutend mit endgültig bestätigter, spendbarer Auszahlung. Coinbase-Reife und Reorganisationen beachten.

### Referenz- und Projektquellen

- Bitcoin Cash Node: https://bitcoincashnode.org/ und https://github.com/bitcoin-cash-node/bitcoin-cash-node/releases/tag/v29.2.0
- CKPool: https://bitbucket.org/ckolivas/ckpool.git
- CKPool-Buildhinweise: https://github.com/ckolivas/ckpool/blob/master/README.md
- Originaldateien: vom Betreiber bereitgestelltes Archiv `bch-mainnet-installationsdateien.tar.gz` (lokaler Patch und Dashboard)

---

**Hinweis zu Beispielwerten:** Vor dem Start alle `HIER_...`-Texte ersetzen und die Beispiel-IP anpassen. **Dokumentationsstatus:** Vollständige Installationsvorlage aus dem bestehenden Mainnet-System, einschließlich Originaldateien. **Offen vor Freigabe als garantiert funktionsfähiges One-Click-Paket:** Test auf einer zweiten frischen Debian-13-VM, Bestätigung des CKPool-Wallet-Adressformats und der Miner-Worker-Syntax, authentifizierte GPG-Release-Prüfung und produktive Dashboard-Härtung. Die Referenz-VM wurde bei der Erstellung nicht verändert.

