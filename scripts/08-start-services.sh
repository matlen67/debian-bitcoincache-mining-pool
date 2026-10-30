#!/usr/bin/env bash
# Explicitly activate pool services after installation and BCHN synchronization.
set -Eeuo pipefail
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Als normaler sudo-Benutzer starten."
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo -v || die "sudo erforderlich."
bash "$ROOT/scripts/07-health-check.sh" || die "Basisprüfung nicht bestanden; nichts gestartet."
[[ -f /etc/systemd/system/bch-ckpool.service && -f /etc/systemd/system/bch-dashboard.service ]] || die "Dienste fehlen."
[[ -s /opt/bch-solo-pool/ckpool/bchsolo.conf ]] || die "Poolkonfiguration fehlt."
read -r -p 'CKPool und Dashboard JETZT starten und beim Booten aktivieren? [j/N] ' ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
sudo systemctl enable --now bch-ckpool.service
sleep 3
if ! sudo systemctl is-active --quiet bch-ckpool.service; then
  sudo journalctl -u bch-ckpool.service -n 40 --no-pager >&2 || true
  die "CKPool nicht aktiv; Dashboard wird nicht gestartet."
fi
sudo systemctl enable --now bch-dashboard.service
sleep 2
if ! sudo systemctl is-active --quiet bch-dashboard.service; then
  sudo journalctl -u bch-dashboard.service -n 40 --no-pager >&2 || true
  die "Dashboard nicht aktiv."
fi
echo "Beide Dienste laufen."
echo "Ports prüfen: sudo ss -ltnp | grep -E ':(3333|8080) '"
echo "Dashboard: http://SERVER_IP:8080/ (SERVER_IP durch deine LAN-IP ersetzen)"
echo "Miner: stratum+tcp://SERVER_IP:3333"
echo "WICHTIG: Dashboard ohne Login, nicht ins Internet freigeben."
