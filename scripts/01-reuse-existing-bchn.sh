#!/usr/bin/env bash
# Reuse existing BCHN on a dedicated Debian 13 test VM, without modifying it.
set -Eeuo pipefail
umask 077
die(){ echo "FEHLER: $*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Nicht als root starten."
sudo -v || die "sudo fehlt."
source /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 ]] || die "Nur Debian 13."
[[ -x /usr/local/bin/bitcoin-cli && -f /etc/systemd/system/bchn.service ]] || die "BCHN fehlt."
for p in /opt/bch-solo-pool/ckpool /etc/systemd/system/bch-ckpool.service /etc/systemd/system/bch-dashboard.service; do [[ ! -e "$p" ]] || die "Bestehende Poolinstallation: $p"; done
id bchn >/dev/null || die "BCHN-Systembenutzer fehlt."
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 750 /opt/bch-solo-pool
sudo usermod -aG bchn "$(id -un)"
sudo chmod 640 /var/lib/bch-node/bitcoin.conf
sudo systemctl is-active --quiet bchn.service || die "BCHN läuft nicht."
sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["chain"]=="main" and d["initialblockdownload"] is False and d["blocks"]>=d["headers"]' || die "BCHN ist nicht synchronisiert."
STATE="$HOME/.config/bch-solo-installer"
[[ ! -e "$STATE/setup.env" ]] || die "setup.env existiert bereits; wird nicht überschrieben."
echo 'Hinweis: Im CKPool-Solo-Modus (-B) bestimmt jeder Miner seine Auszahlung über die BCH-Adresse im Stratum-Benutzernamen.'
echo 'Die folgende Adresse ist eine Konfigurations-/Dashboard-Referenz, keine feste Auszahlung für alle Miner.'
read -r -p 'BCH Legacy-Referenzadresse (beginnt mit 1): ' ADDRESS
[[ "$ADDRESS" =~ ^1[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{25,34}$ ]] || die "Ungültiges Adressformat."
printf '\033[1;32m%s\033[0m' 'Bitte eine eigene Coinbase-Signatur eingeben (z.B. /BCH Solo Pool/) [Mein BCH Solo Pool]: '
read -r BTC_SIG
BTC_SIG="${BTC_SIG:-Mein BCH Solo Pool}"
[[ "$BTC_SIG" =~ ^[[:print:]]+$ && "${#BTC_SIG}" -le 40 ]] || die "Coinbase-Signatur muss aus druckbaren Zeichen bestehen und darf maximal 40 Zeichen lang sein."
# Determine the IPv4 address of the interface used for the default route.
SERVER_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$SERVER_IP" ]] || die "Keine IPv4-Adresse über die Standardroute ermittelbar."
python3 - "$SERVER_IP" <<'PY' || die "Ungültige IPv4."
import ipaddress,sys
x=ipaddress.ip_address(sys.argv[1])
assert x.version==4 and not (x.is_unspecified or x.is_multicast or x.is_loopback)
PY
sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf validateaddress "$ADDRESS" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("isvalid") is True' || die "BCHN lehnt Adresse ab."
printf 'Automatisch ermittelte Server-IP: %s\n' "$SERVER_IP"
read -r -p 'RPC-Daten aus bestehender Node in lokale setup.env übernehmen? [j/N] ' ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
mkdir -p "$STATE"
chmod 700 "$STATE"
# Config is piped; secrets are not exposed in command arguments or printed.
sudo cat /var/lib/bch-node/bitcoin.conf | python3 -c '
import os,re,shlex,sys
path,addr,ip,sig=sys.argv[1:]
values={}
for line in sys.stdin:
    s=line.strip()
    if not s or s.startswith("#") or "=" not in s: continue
    k,v=s.split("=",1)
    if k.strip() in ("rpcuser","rpcpassword"): values[k.strip()]=v.strip()
if not re.fullmatch(r"[A-Za-z0-9_-]+",values.get("rpcuser","")): sys.exit("RPC-Benutzer nicht unterstützt")
if not values.get("rpcpassword") or any(c in values["rpcpassword"] for c in "\\r\\n"): sys.exit("RPC-Passwort fehlt oder ist ungültig")
fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,"w") as f:
    for k,v in (("BCH_ADDRESS",addr),("SERVER_IP",ip),("RPC_USER",values["rpcuser"]),("RPC_PASSWORD",values["rpcpassword"]),("BTC_SIG",sig)):
        f.write(k+"="+shlex.quote(v)+"\n")
' "$STATE/setup.env" "$ADDRESS" "$SERVER_IP" "$BTC_SIG" || die "RPC-Übernahme fehlgeschlagen. BCHN unverändert."
echo "Vorhandene BCHN übernommen. BCHN und Blockchain wurden nicht geändert."
