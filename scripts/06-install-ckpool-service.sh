#!/usr/bin/env bash
# Stage 06 — install CKPool systemd unit; never start until BCHN is fully synced.
set -Eeuo pipefail
umask 077
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Als sudo-Benutzer ausführen."
sudo -v || die "sudo erforderlich."
CKDIR=/opt/bch-solo-pool/ckpool
SERVICE=/etc/systemd/system/bch-ckpool.service
sudo test -x "$CKDIR/src/ckpool" || die "CKPool-Binary fehlt."
sudo test -f "$CKDIR/bchsolo.conf" || die "Konfiguration fehlt; erst 04-configure-payout.sh ausführen."
[[ ! -e "$SERVICE" ]] || die "Service existiert bereits; kein Überschreiben."
[[ -f /etc/systemd/system/bchn.service ]] || die "BCHN-Service fehlt."
[[ -f /etc/systemd/system/bch-dashboard.service ]] || die "Dashboard-Service fehlt."

echo "Lege CKPool-systemd-Dienst automatisch an (Start nach erfolgreicher Gesamtprüfung) ..."
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat >"$TMP" <<EOF
[Unit]
Description=Bitcoin Cash Mainnet Solo Pool (CKPool)
Wants=network-online.target
After=network-online.target bchn.service
Requires=bchn.service

[Service]
Type=simple
User=$(id -un)
Group=$(id -gn)
WorkingDirectory=/opt/bch-solo-pool/ckpool
ExecStart=/opt/bch-solo-pool/ckpool/src/ckpool -B -c bchsolo.conf
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
sudo install -o root -g root -m 644 "$TMP" "$SERVICE"
sudo systemctl daemon-reload
echo "CKPool-Dienst angelegt, aber NICHT aktiviert oder gestartet."
echo "BCHN muss zuerst vollständig synchronisieren. Prüfen mit:"
echo "sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo"
echo "Poolstart wird erst nach separatem Health-Check freigegeben."
