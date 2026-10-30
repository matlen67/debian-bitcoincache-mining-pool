#!/usr/bin/env bash
# Controlled installer for a fresh Debian 13 VM or existing synced BCHN.
# No automatic CKPool/dashboard startup; rerun after BCHN synchronization.
set -Eeuo pipefail
die() { echo "FEHLER: $*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Nicht als root ausführen."
[[ $# -le 1 ]] || die "Verwendung: bash setup-pool.sh [--reuse-bchn]"
MODE="${1:-}"
[[ -z "$MODE" || "$MODE" == "--reuse-bchn" ]] || die "Unbekannte Option: $MODE"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/install.sh" ]] || die "install.sh fehlt."
[[ -f "$ROOT/docs/INSTALLATIONSANLEITUNG-v2.md" ]] || die "Originalanleitung fehlt."
for f in patches/bch-ckpool-mainnet.patch dashboard/app.py dashboard/ckpool_api.py dashboard/block_history.py dashboard/templates/index.html dashboard/static/script.js dashboard/static/style.css; do
  [[ -s "$ROOT/$f" ]] || die "Originaldatei fehlt: $f. Vorher Original-ZIP importieren."
done
# Verify that every original source file matches the tested reference package.
python3 - "$ROOT" <<'PY' || die "Originaldateien beschädigt oder verändert."
import hashlib, runpy, sys
from pathlib import Path
root = Path(sys.argv[1])
mod = runpy.run_path(str(root / "scripts/import-package.py"))
for name, digest in mod["SHA256"].items():
    path = root / mod["DEST"].get(name, name)
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit("SHA256 stimmt nicht: " + str(path))
print("Alle acht Originaldateien geprüft.")
PY
if [[ "$MODE" == "--reuse-bchn" ]]; then
  [[ -f /etc/systemd/system/bchn.service ]] || die "Vorhandene BCHN fehlt."
  if [[ ! -f "$HOME/.config/bch-solo-installer/setup.env" ]]; then
    bash "$ROOT/scripts/01-reuse-existing-bchn.sh"
  fi
else
  if [[ ! -f "$HOME/.config/bch-solo-installer/setup.env" ]]; then
    bash "$ROOT/install.sh"
  fi
fi
[[ -f "$HOME/.config/bch-solo-installer/setup.env" ]] || die "Setup nicht abgeschlossen."
if [[ ! -f /etc/systemd/system/bchn.service ]]; then
  [[ "$MODE" != "--reuse-bchn" ]] || die "BCHN fehlt im Wiederverwendungsmodus."
  bash "$ROOT/scripts/02-install-bchn.sh"
fi
if ! sudo systemctl is-active --quiet bchn.service; then
  echo "BCHN muss zuerst gestartet werden:"
  echo "  sudo systemctl enable --now bchn.service"
  exit 3
fi
# Do not compile or configure the pool until the node is fully synchronized.
# BCHN may still be loading its wallet or block index immediately after startup.
# Capture RPC output before parsing so startup errors do not become JSON tracebacks.
if ! CHAIN_INFO="$(sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo 2>&1)"; then
  echo "BCHN läuft, aber der RPC ist noch nicht bereit (Startphase oder vorübergehender Fehler)."
  echo "RPC-Hinweis: $CHAIN_INFO"
  echo "Installer sicher angehalten. Später erneut starten: bash setup-pool.sh"
  exit 3
fi
if ! printf '%s' "$CHAIN_INFO" | python3 -c 'import json,sys; x=json.load(sys.stdin); sys.exit(0 if x.get("chain")=="main" and x.get("initialblockdownload") is False and x.get("blocks",0)>=x.get("headers",1) else 1)' 2>/dev/null; then
  echo "BCHN ist noch nicht vollständig auf Mainnet synchronisiert oder liefert unerwartete Daten."
  echo "Fortschritt prüfen: sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo"
  echo "Installer sicher angehalten. Nach der Synchronisierung erneut starten: bash setup-pool.sh"
  exit 3
fi
if ! sudo test -x /opt/bch-solo-pool/ckpool/src/ckpool; then bash "$ROOT/scripts/03-install-ckpool.sh"; fi
sudo test -x /opt/bch-solo-pool/ckpool/src/ckpool || die "CKPool-Build fehlt oder wurde abgebrochen."
if ! sudo test -e /opt/bch-solo-pool/webinterface/bch-solo-dashboard; then bash "$ROOT/scripts/05-install-dashboard.sh"; fi
sudo test -f /opt/bch-solo-pool/webinterface/bch-solo-dashboard/block_history.py || die "Dashboard-Installation fehlt."
if ! sudo test -e /opt/bch-solo-pool/ckpool/bchsolo.conf; then bash "$ROOT/scripts/04-configure-payout.sh"; fi
sudo test -f /opt/bch-solo-pool/ckpool/bchsolo.conf || die "Payout-Konfiguration fehlt."
[[ ! -e /etc/systemd/system/bch-ckpool.service ]] && bash "$ROOT/scripts/06-install-ckpool-service.sh"
bash "$ROOT/scripts/08-migrate-pool-user.sh"
bash "$ROOT/scripts/07-health-check.sh"
echo "Basisprüfung bestanden. Starte CKPool und Dashboard ..."
sudo systemctl enable --now bch-ckpool.service
sudo systemctl enable --now bch-dashboard.service
sudo systemctl is-active --quiet bch-ckpool.service || die "CKPool-Dienst läuft nicht. Logs: sudo journalctl -u bch-ckpool.service -n 50 --no-pager"
sudo systemctl is-active --quiet bch-dashboard.service || die "Dashboard-Dienst läuft nicht. Logs: sudo journalctl -u bch-dashboard.service -n 50 --no-pager"
# systemd may report active briefly before Flask attempts to bind its socket.
# Wait until the HTTP listener is actually reachable, and verify the service
# has not crashed into an auto-restart loop.
if ! python3 - <<'PY'
import socket, subprocess, time, sys
for _ in range(30):
    active = subprocess.run(["systemctl", "is-active", "--quiet", "bch-dashboard.service"]).returncode == 0
    if active:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.5):
                time.sleep(1)
                if subprocess.run(["systemctl", "is-active", "--quiet", "bch-dashboard.service"]).returncode == 0:
                    sys.exit(0)
        except OSError:
            pass
    time.sleep(0.5)
sys.exit(1)
PY
then
  die "Dashboard ist nicht dauerhaft auf TCP 8080 erreichbar. Prüfen: sudo systemctl show bch-dashboard.service -p Environment; sudo journalctl -u bch-dashboard.service -n 50 --no-pager"
fi
echo "Installation abgeschlossen: BCHN, CKPool und Dashboard laufen; Dashboard-Port 8080 erreichbar."
