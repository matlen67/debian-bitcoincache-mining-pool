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
sudo test -x /opt/bch-solo-pool/ckpool/src/ckpool || die "CKPool-Binary fehlt. Erst Stufe 03 ausführen."
[[ ! -e "$DEST" && ! -e "$VENV" && ! -e "$SERVICE" ]] || die "Dashboard ist bereits installiert; kein Überschreiben."
id bchn >/dev/null 2>&1 || die "Benutzer bchn fehlt."
command -v python3 >/dev/null || die "Python fehlt."
echo "Installiere Dashboard und richte den systemd-Dienst automatisch ein, bitte warten ..."
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 750 /opt/bch-solo-pool/webinterface
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 750 "$DEST" "$DEST/templates" "$DEST/static"
for f in app.py ckpool_api.py block_history.py templates/index.html static/script.js static/style.css; do
  sudo install -o "$(id -un)" -g "$(id -gn)" -m 640 "$SRC/$f" "$DEST/$f"
done
# Keep the six reference dashboard files unchanged in Git; apply the small
# Uptime-only display override to the installed copy after checksum validation.
printf '\n/* Pool-Uptime: compact value, other metric cards unchanged */\n#pool-uptime { font-size: 22px; letter-spacing: -0.6px; }\n' | sudo tee -a "$DEST/static/style.css" >/dev/null
# Apply a checked JavaScript override to the installed copy only.
# Keep the immutable reference script and its SHA256 unchanged.
JS_TMP="$(mktemp)"
trap 'rm -f "$JS_TMP"' EXIT
sudo install -o "$(id -un)" -g "$(id -gn)" -m 600 "$DEST/static/script.js" "$JS_TMP"
python3 - "$JS_TMP" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
start = s.index("function formatPoolUptime(seconds) {")
end = s.index("\nfunction formatHashrate(", start)
old = s[start:end]
new = """let poolUptimeAnchor = null;

function formatPoolUptime(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  const total = Math.floor(seconds);
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  return `${days} ${days === 1 ? 'Tag' : 'Tage'} ` +
    [hours, minutes, secs].map(n => String(n).padStart(2, '0')).join(':');
}

function tickPoolUptime() {
  if (poolUptimeAnchor === null) return;
  const elapsed = Math.max(0, Math.floor((Date.now() - poolUptimeAnchor.at) / 1000));
  document.getElementById('pool-uptime').textContent =
    formatPoolUptime(poolUptimeAnchor.seconds + elapsed);
}
"""
if "const totalMinutes = Math.floor(seconds / 60);" not in old:
    raise SystemExit("Unexpected uptime formatter; dashboard JS left unchanged")
s = s[:start] + new + s[end:]
old_status = """    $('pool-uptime').textContent = mining.online
      ? formatPoolUptime(mining.uptime)
      : '—';"""
new_status = """    poolUptimeAnchor = mining.online && Number.isFinite(mining.uptime)
      ? { seconds: mining.uptime, at: Date.now() }
      : null;
    $('pool-uptime').textContent = poolUptimeAnchor
      ? formatPoolUptime(poolUptimeAnchor.seconds)
      : '—';"""
if s.count(old_status) != 1 or s.count("setInterval(updateStatus, 5000);") != 1:
    raise SystemExit("Unexpected uptime update logic; dashboard JS left unchanged")
s = s.replace(old_status, new_status)
s = s.replace("setInterval(updateStatus, 5000);", "setInterval(updateStatus, 5000);\nsetInterval(tickPoolUptime, 1000);")
p.write_text(s)
PY
sudo install -o "$(id -un)" -g "$(id -gn)" -m 640 "$JS_TMP" "$DEST/static/script.js"
# Blue accent for the four top metric cards, matching the tested production CSS.
# Apply to the installed copy; keep the original dashboard assets unchanged.
cat <<'CSS' | sudo tee -a "$DEST/static/style.css" >/dev/null

/* Blaue Akzentkacheln – obere Dashboard-Reihe */
.metrics .panel {
    border: 1px solid #263852;
    border-left: 4px solid #168bfa;
    background: linear-gradient(
        105deg,
        rgba(22, 139, 250, 0.09) 0%,
        #141f32 65%
    );
    box-shadow:
        -3px 0 14px rgba(22, 139, 250, 0.16),
        0 8px 35px rgba(0, 0, 0, 0.10);
}
CSS
python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install 'Flask==3.1.3'
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
[Unit]
Description=BCH Solo Pool Dashboard (LAN only)
After=network.target bchn.service bch-ckpool.service
Wants=bchn.service bch-ckpool.service

[Service]
Type=simple
User=$(id -un)
Group=$(id -gn)
SupplementaryGroups=bchn
WorkingDirectory=$DEST
Environment=DASHBOARD_HOST=0.0.0.0
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
echo "Dashboard-Dateien, Flask und systemd-Dienst installiert, aber NICHT gestartet."\necho "Dashboard bindet auf 0.0.0.0:8080 (nur im vertrauenswürdigen LAN betreiben)."
echo "WICHTIG: Dashboard nur im vertrauenswürdigen LAN betreiben (Flask ohne Authentifizierung)."
echo "Nächster Schritt: 04-configure-payout.sh, danach CKPool-Service und Ende-zu-Ende-Prüfung."
