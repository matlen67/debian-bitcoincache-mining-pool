#!/usr/bin/env bash
# Read-only readiness checks. No services are started or changed.
set -Eeuo pipefail
fail=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[FEHLER] %s\n' "$*" >&2; fail=1; }
warn() { printf '[HINWEIS] %s\n' "$*"; }
[[ "$(id -u)" -ne 0 ]] || { echo "Bitte als normaler sudo-Benutzer ausführen." >&2; exit 2; }
sudo -v || exit 2
for unit in bchn.service bch-ckpool.service bch-dashboard.service; do
  if systemctl cat "$unit" >/dev/null 2>&1; then ok "$unit vorhanden"; else bad "$unit fehlt"; fi
done
if [[ ! -x /usr/local/bin/bitcoin-cli ]]; then
  bad "bitcoin-cli fehlt"
  exit 1
fi
if ! command -v python3 >/dev/null; then bad "Python 3 fehlt"; exit 1; fi
if ! sudo systemctl is-active --quiet bchn.service; then
  bad "BCHN läuft nicht"
  exit 1
fi
info="$(sudo -u bchn /usr/local/bin/bitcoin-cli -datadir=/var/lib/bch-node -conf=/var/lib/bch-node/bitcoin.conf getblockchaininfo 2>/dev/null)" || { bad "BCHN RPC nicht erreichbar"; exit 1; }
python3 - "$info" <<'PY' || fail=1
import json,sys
try:
    x=json.loads(sys.argv[1])
    blocks=x["blocks"]; headers=x["headers"]
    chain=x["chain"]; ibd=x["initialblockdownload"]
    print(f"Chain: {chain}, Blöcke: {blocks}, Header: {headers}, IBD: {ibd}")
    if chain!="main" or ibd is not False or blocks < headers:
        print("[FEHLER] BCHN ist noch nicht vollständig synchronisiert.")
        sys.exit(1)
    print("[OK] BCHN Mainnet vollständig synchronisiert")
except (ValueError, KeyError, TypeError) as e:
    print("[FEHLER] BCHN-Antwort ungültig:",e)
    sys.exit(1)
PY
for path in /opt/bch-solo-pool/ckpool/src/ckpool /opt/bch-solo-pool/ckpool/bchsolo.conf /opt/bch-solo-pool/webinterface/bch-solo-dashboard/app.py /opt/bch-solo-pool/webinterface/venv/bin/python; do
  if sudo test -e "$path"; then ok "$path vorhanden"; else bad "$path fehlt"; fi
done
if sudo test -f /opt/bch-solo-pool/ckpool/bchsolo.conf; then
  mode="$(sudo stat -c %a /opt/bch-solo-pool/ckpool/bchsolo.conf)"
  [[ "$mode" == 600 ]] && ok "CKPool-Konfiguration geschützt (0600)" || bad "CKPool-Konfiguration hat Dateimodus $mode statt 600"
fi
if sudo systemctl is-active --quiet bch-ckpool.service; then
  ok "CKPool läuft"
else
  warn "CKPool läuft noch nicht (vor dem ersten Start normal)"
fi
if sudo systemctl is-active --quiet bch-dashboard.service; then
  ok "Dashboard läuft"
else
  warn "Dashboard läuft noch nicht (vor dem ersten Start normal)"
fi
if [[ "$fail" -eq 0 ]]; then
  echo "Basisprüfung bestanden. Keine Dienste wurden verändert."
else
  echo "Basisprüfung NICHT bestanden. Pool noch nicht starten." >&2
fi
exit "$fail"
