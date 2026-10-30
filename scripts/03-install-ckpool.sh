#!/usr/bin/env bash
# CKPool stage (development): requires verified BCH patch in ../patches/.
set -Eeuo pipefail
umask 077
fail() { echo "FEHLER: $*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || fail "Als normaler sudo-Benutzer starten."
sudo -v || fail "sudo nicht verfügbar."
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$ROOT/patches/bch-ckpool-mainnet.patch"
[[ -s "$PATCH" ]] || fail "Originalpatch fehlt: $PATCH. Abbruch ohne Änderungen."
[[ -f "$HOME/.config/bch-solo-installer/setup.env" ]] || fail "Erst install.sh ausführen."
[[ -x /usr/local/bin/bitcoin-cli ]] || fail "BCHN ist nicht installiert."
[[ -d /var/lib/bch-node ]] || fail "BCHN-Datenverzeichnis fehlt."
id pooladmin >/dev/null 2>&1 || fail "Benutzer pooladmin fehlt."
[[ ! -e /opt/bch-solo-pool/ckpool ]] || fail "CKPool existiert bereits; nichts überschreiben."
for c in git make; do command -v "$c" >/dev/null || fail "$c fehlt."; done
# Tested on testpool; do not silently switch to upstream HEAD.
COMMIT=4bba986ce63550cdc9c1a456e3ff2edf2406e1e9
read -r -p "CKPool-Quellcode holen und BCH-Patch prüfen? [j/N] " ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
sudo -u pooladmin git clone https://bitbucket.org/ckolivas/ckpool.git /opt/bch-solo-pool/ckpool
cd /opt/bch-solo-pool/ckpool
sudo -u pooladmin git checkout --detach "$COMMIT"
sudo -u pooladmin git submodule update --init --recursive
sudo -u pooladmin git apply --check "$PATCH" || fail "Originalpatch passt nicht zu Commit $COMMIT. KEIN Build."
sudo -u pooladmin git apply "$PATCH"
sudo -u pooladmin ./autogen.sh
sudo -u pooladmin ./configure
sudo -u pooladmin make -j"$(nproc)"
[[ -x src/ckpool ]] || fail "CKPool-Binary fehlt nach Build."
echo "CKPool erfolgreich gebaut. Keine Konfiguration und kein Dienststart."
echo "Nächster Schritt: BCH-Adresse via BCHN prüfen, Konfiguration erzeugen und Dienst einrichten."
