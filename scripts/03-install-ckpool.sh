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
CKDIR=/opt/bch-solo-pool/ckpool
if [[ -e "$CKDIR" ]]; then
  [[ -d "$CKDIR/.git" ]] || fail "Bestehendes CKPool-Verzeichnis ist kein Git-Checkout."
  [[ -z "$(sudo -u pooladmin git -C "$CKDIR" status --porcelain)" ]] || fail "CKPool-Checkout hat Änderungen; Abbruch."
fi
for c in git make; do command -v "$c" >/dev/null || fail "$c fehlt."; done
# Tested on testpool; do not silently switch to upstream HEAD.
COMMIT=4bba986ce63550cdc9c1a456e3ff2edf2406e1e9
read -r -p "CKPool-Quellcode holen und BCH-Patch prüfen? [j/N] " ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
if [[ ! -e "$CKDIR" ]]; then
  sudo -u pooladmin git clone https://bitbucket.org/ckolivas/ckpool.git "$CKDIR"
else
  echo "Vorhandenen unveränderten CKPool-Checkout wiederverwenden."
fi
# The parent directory is intentionally private (0750); the invoking user
# must not cd into it. Run all checkout/build operations as pooladmin.
PATCH_COPY="$(mktemp /tmp/bch-ckpool-patch.XXXXXXXX)"
trap 'rm -f -- "$PATCH_COPY"' EXIT
install -m 644 "$PATCH" "$PATCH_COPY"
sudo -u pooladmin bash -euo pipefail -c '
  cd "$1"
  COMMIT="$2"
  PATCH_COPY="$3"
  [[ "$(git rev-parse HEAD)" == "$COMMIT" ]] || git checkout --detach "$COMMIT"
  git submodule update --init --recursive
  git apply --check "$PATCH_COPY" || { echo "Patch passt nicht zu Commit $COMMIT. KEIN Build." >&2; exit 1; }
  git apply "$PATCH_COPY"
  ./autogen.sh
  ./configure
  make -j"$(nproc)"
  [[ -x src/ckpool ]] || { echo "CKPool-Binary fehlt nach Build." >&2; exit 1; }
' bash "$CKDIR" "$COMMIT" "$PATCH_COPY"
echo "CKPool erfolgreich gebaut. Keine Konfiguration und kein Dienststart."
echo "Nächster Schritt: BCH-Adresse via BCHN prüfen, Konfiguration erzeugen und Dienst einrichten."
