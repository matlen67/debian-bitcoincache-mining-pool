#!/usr/bin/env bash
# One-time, repeatable migration of an existing test-pool installation.
# Keep BCHN as bchn; run CKPool and dashboard as the invoking sudo user.
set -Eeuo pipefail
[[ "$(id -u)" -ne 0 ]] || { echo "Nicht als root ausführen." >&2; exit 1; }
sudo -v
USER_NAME="$(id -un)"
USER_GROUP="$(id -gn)"
BASE=/opt/bch-solo-pool
NODE_CONF=/var/lib/bch-node/bitcoin.conf
CK_SERVICE=/etc/systemd/system/bch-ckpool.service
DASH_SERVICE=/etc/systemd/system/bch-dashboard.service
sudo test -d "$BASE" && sudo test -f "$NODE_CONF" || { echo "Pool oder BCHN-Konfiguration fehlt." >&2; exit 1; }
id bchn >/dev/null
# Only migrate an installed pool. Fresh installs already have the correct owner.
if [[ ! -f "$CK_SERVICE" || ! -f "$DASH_SERVICE" ]]; then
  echo "Pool-Dienste noch nicht vollständig installiert; keine Migration nötig."
  exit 0
fi
if [[ "$(sudo stat -c %U "$BASE")" == "$USER_NAME" ]] &&
   [[ "$(sudo systemctl show -p User --value bch-ckpool.service)" == "$USER_NAME" ]] &&
   [[ "$(sudo systemctl show -p User --value bch-dashboard.service)" == "$USER_NAME" ]]; then
  echo "Benutzerstruktur bereits korrekt."
  exit 0
fi
echo "Migriere CKPool und Dashboard zu $USER_NAME; BCHN bleibt bchn."
sudo systemctl stop bch-dashboard.service bch-ckpool.service || true
sudo usermod -aG bchn "$USER_NAME"
sudo chmod 640 "$NODE_CONF"
sudo chown -R "$USER_NAME:$USER_GROUP" "$BASE"
# Preserve configuration secrecy; directory remains accessible to its owner.
sudo chmod 600 "$BASE/ckpool/bchsolo.conf"
sudo chmod 750 "$BASE"
for service in "$CK_SERVICE" "$DASH_SERVICE"; do
  sudo cp -p "$service" "$service.bak-before-user-migration"
  sudo sed -i -E "s/^User=.*/User=$USER_NAME/; s/^Group=.*/Group=$USER_GROUP/" "$service"
done
# Dashboard must be able to read the BCHN RPC configuration through bchn group.
if ! sudo grep -q '^SupplementaryGroups=bchn$' "$DASH_SERVICE"; then
  sudo sed -i '/^Group=/a SupplementaryGroups=bchn' "$DASH_SERVICE"
fi
sudo systemctl daemon-reload
echo "Migration abgeschlossen. setup-pool.sh startet die Dienste nach dem Health-Check."
# Remove the obsolete dedicated account only if no process is still running as it.
if id pooladmin >/dev/null 2>&1; then
  if pgrep -u pooladmin >/dev/null 2>&1; then
    echo "HINWEIS: pooladmin hat noch laufende Prozesse und wird nicht gelöscht."
  else
    sudo userdel pooladmin
    if getent group pooladmin >/dev/null 2>&1; then
      sudo gpasswd -d bchn pooladmin >/dev/null 2>&1 || true
      sudo groupdel pooladmin 2>/dev/null || true
    fi
    echo "Alter pooladmin-Account entfernt."
  fi
fi
