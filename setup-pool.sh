#!/usr/bin/env bash
# Controlled installer for a NEW Debian 13 test VM.
# No automatic CKPool/dashboard startup; rerun after BCHN synchronization.
set -Eeuo pipefail
die() { echo "FEHLER: $*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Nicht als root ausführen."
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/install.sh" ]] || die "install.sh fehlt."
[[ -f "$ROOT/docs/INSTALLATIONSANLEITUNG-v2.md" ]] || die "Originalanleitung fehlt."
for f in patches/bch-ckpool-mainnet.patch dashboard/app.py dashboard/ckpool_api.py dashboard/block_history.py dashboard/templates/index.html dashboard/static/script.js dashboard/static/style.css; do
  [[ -s "$ROOT/$f" ]] || die "Originaldatei fehlt: $f. Vorher Original-ZIP importieren."
done
if [[ ! -f "$HOME/.config/bch-solo-installer/setup.env" ]]; then
  bash "$ROOT/install.sh"
fi
[[ -f "$HOME/.config/bch-solo-installer/setup.env" ]] || die "Setup nicht abgeschlossen."
if [[ ! -f /etc/systemd/system/bchn.service ]]; then
  bash "$ROOT/scripts/02-install-bchn.sh"
fi
if ! sudo systemctl is-active --quiet bchn.service; then
  echo "BCHN muss zuerst gestartet werden:"
  echo "  sudo systemctl enable --now bchn.service"
  exit 3
fi
# Do not compile or configure the pool until the node is fully synchronized.
if ! sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["chain"]=="main" and x["initialblockdownload"] is False and x["blocks"]>=x["headers"]'; then
  echo "BCHN synchronisiert noch. Installer hier sicher angehalten."
  echo "Nach vollständiger Synchronisierung erneut starten: bash setup-pool.sh"
  exit 3
fi
[[ ! -e /opt/bch-solo-pool/ckpool ]] && bash "$ROOT/scripts/03-install-ckpool.sh"
[[ -x /opt/bch-solo-pool/ckpool/src/ckpool ]] || die "CKPool-Build fehlt oder wurde abgebrochen."
[[ ! -e /opt/bch-solo-pool/webinterface/bch-solo-dashboard ]] && bash "$ROOT/scripts/05-install-dashboard.sh"
[[ -f /opt/bch-solo-pool/webinterface/bch-solo-dashboard/block_history.py ]] || die "Dashboard-Installation fehlt."
[[ ! -e /opt/bch-solo-pool/ckpool/bchsolo.conf ]] && bash "$ROOT/scripts/04-configure-payout.sh"
[[ -f /opt/bch-solo-pool/ckpool/bchsolo.conf ]] || die "Payout-Konfiguration fehlt."
[[ ! -e /etc/systemd/system/bch-ckpool.service ]] && bash "$ROOT/scripts/06-install-ckpool-service.sh"
bash "$ROOT/scripts/07-health-check.sh"
echo "Basisprüfung bestanden. CKPool und Dashboard bleiben gestoppt."
echo "Vor Freigabe: RPC, CKPool-Socket, Miner-Share und Auszahlungsscript separat prüfen."
