#!/usr/bin/env bash
# BCH Solo Pool — guarded stage runner for a fresh Debian 13 test VM.
# Deliberately does NOT start CKPool or dashboard automatically.
set -Eeuo pipefail
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Nicht als root ausführen."
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/scripts/02-install-bchn.sh" ]] || die "Unvollständiges Repository."
usage() {
  cat <<'EOF'
Verwendung: bash run-stages.sh <Schritt>
  check-assets  Original-Patch und alle Dashboarddateien prüfen
  bchn          BCHN installieren (Stufe 02)
  ckpool        CKPool bauen (Stufe 03)
  dashboard     Original-Dashboard installieren (Stufe 05)
  payout        BCH-Auszahlungsadresse konfigurieren (Stufe 04)
  service       CKPool-Dienst einrichten (Stufe 06)
  health        Synchronisierung und Installationsstatus prüfen (Stufe 07)

Reihenfolge: zuerst bash install.sh, dann check-assets, bchn, ckpool,
dashboard, payout, service, health.
WICHTIG: BCHN-Synchronisierung kann lange dauern. Dieser Runner startet
keine Pool- oder Dashboard-Dienste und verändert keine bestehende Installation.
EOF
}
assets() {
  local missing=0 f
  for f in \
    patches/bch-ckpool-mainnet.patch \
    dashboard/app.py dashboard/ckpool_api.py dashboard/block_history.py \
    dashboard/templates/index.html dashboard/static/script.js \
    dashboard/static/style.css; do
    if [[ ! -s "$ROOT/$f" ]]; then
      printf '[FEHLT] %s\n' "$f" >&2
      missing=1
    else
      printf '[OK] %s\n' "$f"
    fi
  done
  ((missing == 0)) || die "Originaldateien fehlen. Bitte erst mit scripts/import-package.py importieren."
}
[[ $# -eq 1 ]] || { usage; exit 2; }
case "$1" in
  check-assets) assets ;;
  bchn) bash "$ROOT/scripts/02-install-bchn.sh" ;;
  ckpool) assets; bash "$ROOT/scripts/03-install-ckpool.sh" ;;
  dashboard) assets; bash "$ROOT/scripts/05-install-dashboard.sh" ;;
  payout) bash "$ROOT/scripts/04-configure-payout.sh" ;;
  service) bash "$ROOT/scripts/06-install-ckpool-service.sh" ;;
  health) bash "$ROOT/scripts/07-health-check.sh" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
