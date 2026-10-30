#!/usr/bin/env bash
# Optional restore of pruned BCHN blocks + chainstate from a trusted local archive.
# Run only on a fresh BCHN installation before the first node start.
set -Eeuo pipefail
die() { echo "FEHLER: $*" >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || die "Als normaler Benutzer ausführen."
[[ $# -eq 1 ]] || die "Verwendung: bash scripts/09-restore-blockchain.sh /pfad/bchn-blockchain.tar.gz"
ARCHIVE="$1"
DATA=/var/lib/bch-node
sudo -v
[[ -f "$ARCHIVE" && -r "$ARCHIVE" ]] || die "Archiv nicht lesbar: $ARCHIVE"
sudo test -f "$DATA/bitcoin.conf" || die "BCHN muss zuerst installiert sein."
sudo systemctl is-active --quiet bchn.service && die "BCHN läuft. Wiederherstellung nur bei gestopptem Dienst."
for p in blocks chainstate; do
  if sudo test -e "$DATA/$p"; then die "Vorhandene Blockchain-Daten ($p) werden nicht überschrieben."; fi
done
echo "Prüfe Archivstruktur (nur Blöcke und Chainstate werden übernommen) ..."
python3 - "$ARCHIVE" <<'PY'
import sys,tarfile
seen=set()
with tarfile.open(sys.argv[1],"r:gz") as t:
    for m in t:
        n=m.name.removeprefix("./").rstrip("/")
        if n in ("bch-node/blocks","bch-node/chainstate"):
            seen.add(n)
        if n.startswith(("bch-node/blocks/","bch-node/chainstate/")):
            if not (m.isfile() or m.isdir()):
                raise SystemExit("Unsicherer Archiveintrag: "+n)
            if ".." in n.split("/"):
                raise SystemExit("Ungültiger Archiveintrag: "+n)
if seen != {"bch-node/blocks","bch-node/chainstate"}:
    raise SystemExit("Archiv enthält nicht beide erwarteten Verzeichnisse.")
PY
read -r -p "Blöcke und Chainstate aus diesem Archiv wiederherstellen? [j/N] " ANSWER
[[ "$ANSWER" =~ ^[jJyY]$ ]] || { echo "Abgebrochen."; exit 0; }
STAGING="$(sudo mktemp -d "$DATA/.restore.XXXXXXXX")"
cleanup() { sudo rm -rf -- "$STAGING"; }
trap cleanup EXIT
sudo tar -xzf "$ARCHIVE" -C "$STAGING" --no-same-owner bch-node/blocks bch-node/chainstate
sudo test -d "$STAGING/bch-node/blocks" && sudo test -d "$STAGING/bch-node/chainstate" || die "Extraktion unvollständig."
sudo chown -R bchn:bchn "$STAGING/bch-node"
sudo mv "$STAGING/bch-node/blocks" "$DATA/blocks"
sudo mv "$STAGING/bch-node/chainstate" "$DATA/chainstate"
echo "Blockchain-Daten wiederhergestellt. Neue bitcoin.conf und RPC-Zugangsdaten bleiben unverändert."
