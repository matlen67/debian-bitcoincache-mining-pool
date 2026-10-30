#!/usr/bin/env bash
# Stage 05 — dashboard environment and systemd unit (development).
# Correct order: run this BEFORE 04-configure-payout.sh so PAYOUT_SCRIPT stays configured.
# Does not start services; only use on a fresh test VM after original files were imported.
set -Eeuo pipefail
umask 077
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Bitte als normaler sudo-Benutzer starten."
sudo -v || die "sudo fehlt."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 ]] || die "Debian 13 erforderlich."
CONF="$HOME/.config/bch-solo-installer/setup.env"
[[ -f "$CONF" && ! -L "$CONF" && "$(stat -c %a "$CONF")" == 600 ]] || die "Sichere setup.env fehlt."
# shellcheck disable=SC1090
source "$CONF"
python3 - "$SERVER_IP" <<'PY' || die "Ungültige IPv4-Adresse."
import ipaddress,sys
a=ipaddress.ip_address(sys.argv[1])
assert a.version==4 and not (a.is_unspecified or a.is_multicast or a.is_loopback)
PY
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/dashboard"
DEST=/opt/bch-solo-pool/webinterface/bch-solo-dashboard
VENV=/opt/bch-solo-pool/webinterface/venv
SERVICE=/etc/systemd/system/bch-dashboard.service
for f in app.py ckpool_api.py block_history.py templates/index.html static/script.js static/style.css; do
  [[ -s "$SRC/$f" ]] || die "Original-Dashboarddatei fehlt: $SRC/$f"
done
[[ -x /usr/local/bin/bitcoin-cli ]] || die "BCHN fehlt."
[[ -x /opt/bch-solo-pool/ckpool/src/ckpool ]] || die "CKPool-Binary fehlt. Erst Stufe 03 ausführen."
[[ ! -e "$DEST" && ! -e "$VENV" && ! -e "$SERVICE" ]] || die "Dashboard ist bereits installiert; kein Überschreiben."
id bchn >/dev/null 2>&1 || die "Benutzer bchn fehlt."
command -v python3 >/dev/null || die "Python fehlt."
read -r -p 'Original-Dashboard installieren und systemd-Dienst anlegen (ohne Start)? [j/N] ' OK
[[ "$OK" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip
sudo install -d -o bchn -g bchn -m 750 /opt/bch-solo-pool/webinterface
sudo install -d -o bchn -g bchn -m 750 "$DEST" "$DEST/templates" "$DEST/static"
for f in app.py ckpool_api.py block_history.py templates/index.html static/script.js static/style.css; do
  sudo install -o bchn -g bchn -m 640 "$SRC/$f" "$DEST/$f"
done
sudo -u bchn python3 -m venv "$VENV"
sudo -u bchn "$VENV/bin/python" -m pip install 'Flask==3.1.3'
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
[Unit]
Description=BCH Solo Pool Dashboard (LAN only)
After=network.target bchn.service bch-ckpool.service
Wants=bchn.service bch-ckpool.service

[Service]
Type=simple
User=bchn
Group=bchn
WorkingDirectory=$DEST
Environment=DASHBOARD_HOST=$SERVER_IP
Environment=STRATUM_HOST=$SERVER_IP
Environment=STRATUM_PORT=3333
Environment=BCH_DATADIR=/var/lib/bch-node
Environment=BITCOIN_CLI=/usr/local/bin/bitcoin-cli
ExecStart=$VENV/bin/python app.py
Restart=on-failure
RestartSec=10
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
sudo install -o root -g root -m 644 "$TMP" "$SERVICE"
sudo systemctl daemon-reload
echo "Dashboard-Dateien, Flask und systemd-Dienst installiert, aber NICHT gestartet."
echo "WICHTIG: Dashboard nur im vertrauenswürdigen LAN betreiben (Flask ohne Authentifizierung)."
echo "Nächster Schritt: 04-configure-payout.sh, danach CKPool-Service und Ende-zu-Ende-Prüfung."
