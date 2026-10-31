#!/usr/bin/env bash
# BCH Solo Pool installer — development stage 1: preflight and safe configuration.
set -Eeuo pipefail
umask 077
trap 'printf "Fehler in Zeile %s (Exit %s). Keine Pool-Dienste wurden gestartet.\n" "$LINENO" "$?" >&2' ERR

fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || fail "Bitte als normaler sudo-Benutzer ausführen, nicht als root."
command -v sudo >/dev/null || fail "sudo fehlt."
sudo -v || fail "sudo ist nicht eingerichtet."
[[ -r /etc/os-release ]] || fail "/etc/os-release fehlt."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || fail "Benötigt Debian 13."
for cmd in python3 openssl ip; do command -v "$cmd" >/dev/null || fail "Benötigtes Programm fehlt: $cmd"; done
for svc in bchn.service bch-ckpool.service bch-dashboard.service; do
  if systemctl list-unit-files --no-legend "$svc" 2>/dev/null | grep -q "^$svc"; then
    fail "Bestehender Dienst $svc erkannt. Keine Installation über bestehende Pools."
  fi
done
[[ ! -e /var/lib/bch-node/bitcoin.conf && ! -e /opt/bch-solo-pool/ckpool/bchsolo.conf ]] || fail "Vorhandene Pool-Konfiguration erkannt."
printf '\nBCH MAINNET Solo Pool — Installer v1 (Vorbereitung)\n'
printf 'Dieser Entwicklungsstand prüft nur das System und erzeugt eine lokale Konfiguration.\n'
printf 'Hinweis: Im späteren CKPool-Solo-Modus (-B) verwendet jeder Miner seine eigene gültige BCH-Adresse als Stratum-Benutzernamen.\n'
printf 'Die folgende Adresse ist eine Konfigurations-/Dashboard-Referenz, keine feste Auszahlung für alle Miner.\n'
printf '\033[1;32m%s\033[0m' 'BCH Legacy-Referenzadresse (beginnt mit 1): '
read -r BCH_ADDRESS
[[ "$BCH_ADDRESS" =~ ^1[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{25,34}$ ]] || fail "Keine plausible Legacy-P2PKH-Adresse. BCHN prüft die Adresse später zusätzlich."
# Determine the IPv4 address of the interface used for the default route.
SERVER_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$SERVER_IP" ]] || fail "Keine IPv4-Adresse über die Standardroute ermittelbar."
python3 - "$SERVER_IP" <<'PY' || fail "Ungültige IPv4-Adresse."
import ipaddress, sys
a = ipaddress.ip_address(sys.argv[1])
if a.version != 4 or a.is_loopback or a.is_multicast or a.is_unspecified:
    raise SystemExit(1)
PY
printf 'Automatisch ermittelte Server-IP: %s\n' "$SERVER_IP"
printf '\033[1;32m%s\033[0m' 'Konfiguration lokal speichern? [j/N] '
read -r ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo 'Abgebrochen, keine Änderungen.'; exit 0; }
STATE_DIR="$HOME/.config/bch-solo-installer"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
[[ ! -e "$STATE_DIR/setup.env" ]] || fail "Lokale Konfiguration existiert bereits; wird nicht überschrieben."
RPC_PASSWORD="$(openssl rand -hex 32)"
# Python repräsentiert Werte sicher als Shell-Strings; kein eval nötig.
python3 - "$STATE_DIR/setup.env" "$BCH_ADDRESS" "$SERVER_IP" "$RPC_PASSWORD" <<'PY'
import os, shlex, sys
path, addr, ip, password = sys.argv[1:]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    for k, v in [('BCH_ADDRESS', addr), ('SERVER_IP', ip), ('RPC_USER', 'bchpool'), ('RPC_PASSWORD', password)]:
        f.write(k + '=' + shlex.quote(v) + '\n')
PY
printf '\nVorbereitung abgeschlossen. Lokale Konfiguration: %s\n' "$STATE_DIR/setup.env"
printf 'RPC-Passwort wurde erzeugt und nicht ausgegeben.\n'
printf 'Noch NICHT installiert: BCHN, CKPool, Dashboard. Es wurden keine Dienste gestartet.\n'
