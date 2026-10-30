# Bitcoin Cash Mainnet Solo Pool — Installer (Entwicklung)

**Branch `installer-v1`: noch kein vollständiger Installer.** Ausschließlich auf einer frischen Test-VM verwenden, niemals auf dem produktiven Pool.

## Voraussetzungen

Debian 13 (Trixie), ohne Desktop-Umgebung, mit SSH und einem normalen Benutzer mit funktionierendem `sudo`. Feste LAN-IP und eine eigene **BCH Mainnet Legacy-P2PKH-Adresse** (beginnt mit `1`).

## Aktueller Funktionsumfang

`install.sh` prüft Betriebssystem, sudo und bereits vorhandene Pool-Konfigurationen. Anschließend fragt es die BCH-Legacy-Adresse und die Server-IP ab und erzeugt ein zufälliges RPC-Passwort. Die Angaben werden ausschließlich lokal unter `~/.config/bch-solo-installer/setup.env` mit Dateirechten 0600 gespeichert. **Es werden noch keine Programme installiert und keine Dienste gestartet.** Die Eingabeprüfung der Adresse ist vorläufig; die endgültige Validierung durch BCHN folgt in einer späteren Ausbaustufe.

```bash
git clone --branch installer-v1 https://github.com/matlen67/debian-bitcoincache-mining-pool.git
cd debian-bitcoincache-mining-pool
bash install.sh
```

## Geplante Ausbaustufen

- Original-CKPool-Patch und Dashboard aus dem getesteten Installationspaket einbinden
- BCHN 29.2.0 mit Prüfsummen-/Versionsprüfung installieren und Mainnet-RPC konfigurieren
- CKPool auf einen geprüften Commit festlegen, BCH-Patch anwenden und bauen
- BCH-Adresse mit `validateaddress` prüfen und `scriptPubKey` im Dashboard konfigurieren
- systemd-Dienste, Synchronisationsprüfung und Health-Checks ergänzen

**Sicherheit:** RPC-Zugangsdaten, Wallet-Seeds, private Schlüssel, `bitcoin.conf` und `bchsolo.conf` niemals nach GitHub committen. Bestehende Installationen werden nicht automatisch überschrieben.
