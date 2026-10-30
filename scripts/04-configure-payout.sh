#!/usr/bin/env bash
# Stage 04: validate the payout address with BCHN and write CKPool configuration.
# No pool service is started here.
set -Eeuo pipefail
umask 077
fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || fail "Nicht als root ausführen."
sudo -v || fail "sudo erforderlich."
SETUP="$HOME/.config/bch-solo-installer/setup.env"
[[ -f "$SETUP" && ! -L "$SETUP" ]] || fail "setup.env fehlt."
[[ "$(stat -c %a "$SETUP")" == 600 ]] || fail "setup.env benötigt Dateimodus 600."
# shellcheck disable=SC1090
source "$SETUP"
[[ "${RPC_USER:-}" =~ ^[A-Za-z0-9_-]+$ && -n "${RPC_PASSWORD:-}" ]] || fail "RPC-Zugangsdaten fehlen."
[[ "${BCH_ADDRESS:-}" =~ ^1[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{25,34}$ ]] || fail "Ungültiges Legacy-Adressformat."
[[ "${SERVER_IP:-}" =~ ^[0-9.]+$ ]] || fail "Ungültige Server-IP."
python3 - "$SERVER_IP" <<'PY' || fail "Ungültige IPv4."
import ipaddress,sys
a=ipaddress.ip_address(sys.argv[1])
assert a.version==4 and not (a.is_loopback or a.is_multicast or a.is_unspecified)
PY
CKDIR=/opt/bch-solo-pool/ckpool
DASH=/opt/bch-solo-pool/webinterface/bch-solo-dashboard
[[ -x "$CKDIR/src/ckpool" ]] || fail "CKPool ist noch nicht gebaut."
[[ -f "$DASH/block_history.py" ]] || fail "Dashboard-Originaldateien fehlen."
[[ ! -e "$CKDIR/bchsolo.conf" ]] || fail "bchsolo.conf existiert bereits; kein Überschreiben."
id pooladmin >/dev/null 2>&1 || fail "pooladmin fehlt."
id bchn >/dev/null 2>&1 || fail "bchn fehlt."
[[ -x /usr/local/bin/bitcoin-cli ]] || fail "bitcoin-cli fehlt."
echo "Prüfe BCH-Mainnet-Adresse über lokalen BCHN-RPC ..."
VALIDATION="$(sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf validateaddress "$BCH_ADDRESS")" || fail "BCHN-RPC nicht erreichbar."
SCRIPT="$(python3 -c 'import json,sys,re; x=json.load(sys.stdin); s=x.get("scriptPubKey",""); assert x.get("isvalid") is True and re.fullmatch(r"76a914[0-9a-fA-F]{40}88ac",s); print(s.lower())' <<<"$VALIDATION")" || fail "Adresse nicht gültig oder kein P2PKH-scriptPubKey. Abbruch."
echo "Adresse durch BCHN validiert. scriptPubKey: $SCRIPT"
read -r -p 'Konfiguration für diese Adresse erzeugen? [j/N] ' ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP/bchsolo.conf" "$BCH_ADDRESS" "$SERVER_IP" "$RPC_USER" "$RPC_PASSWORD" <<'PY'
import json,sys
path,addr,ip,user,pwd=sys.argv[1:]
cfg={
 "btcd":[{"url":"127.0.0.1:8332","auth":user,"pass":pwd,"notify":False}],
 "btcaddress":addr,"btcsig":"Mein BCH Solo Pool",
 "blockpoll":100,"donation":0,"nonce1length":4,"nonce2length":8,
 "update_interval":30,"version_mask":"1fffe000","dropidle":0,
 "serverurl":[ip+":3333"],"mindiff":1,"startdiff":1000,
 "maxdiff":0,"logdir":"logs"
}
with open(path,"x") as f: json.dump(cfg,f,indent=2);f.write("\n")
PY
# Do not modify the original dashboard file in place until its expected
# reference constant has been found exactly once.
python3 - "$DASH/block_history.py" "$TMP/block_history.py" "$SCRIPT" <<'PY'
import pathlib,re,sys
src=pathlib.Path(sys.argv[1]).read_text()
pattern=r'PAYOUT_SCRIPT\s*=\s*\(\s*"[0-9a-fA-F]{50}"\s*\)'
if len(re.findall(pattern,src))!=1:
    raise SystemExit("Unerwartete PAYOUT_SCRIPT-Struktur; nichts geändert.")
out=re.sub(pattern,'PAYOUT_SCRIPT = (\n    "'+sys.argv[3]+'"\n)',src)
pathlib.Path(sys.argv[2]).write_text(out)
PY
sudo install -o pooladmin -g pooladmin -m 600 "$TMP/bchsolo.conf" "$CKDIR/bchsolo.conf"
sudo install -d -o pooladmin -g pooladmin -m 750 "$CKDIR/logs"
sudo install -o bchn -g bchn -m 640 "$TMP/block_history.py" "$DASH/block_history.py"
echo "CKPool-Konfiguration und Dashboard-Auszahlungsscript eingerichtet."
echo "Noch keine CKPool- oder Dashboard-Dienste gestartet."
