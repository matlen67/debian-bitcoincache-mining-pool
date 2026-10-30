
import json
import os
import subprocess
import threading
import time
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template
from block_history import get_block_history, LOGFILE, BLOCK_PATTERN
from ckpool_api import get_poolstats, get_clients, get_workers, dsps_to_ghs


app = Flask(__name__)

BCH_DATADIR = os.environ.get('BCH_DATADIR', '/var/lib/bch-node')
BITCOIN_CLI = os.environ.get('BITCOIN_CLI', '/usr/local/bin/bitcoin-cli')
STRATUM_HOST = os.environ.get('STRATUM_HOST', '192.168.178.36')
STRATUM_PORT = int(os.environ.get('STRATUM_PORT', '3333'))


# ============================================================
# CKPool - Laufzeit seit dem letzten Start
# ============================================================

def ckpool_uptime():
    result = subprocess.run(
        [
            '/usr/bin/systemctl', 'show', 'bch-ckpool.service',
            '--property=ActiveEnterTimestampMonotonic',
            '--value'
        ],
        capture_output=True,
        text=True,
        timeout=3,
        check=True
    )

    started_us = int(result.stdout.strip())

    if started_us <= 0:
        return None

    with open('/proc/uptime', 'r') as f:
        uptime_seconds = float(f.read().split()[0])

    return max(0, int(uptime_seconds - started_us / 1_000_000))


# ============================================================
# BCHN - Blockchain-Informationen
# ============================================================

def bchn_info():
    # Dashboard läuft als Benutzer bchn und kann den RPC-Cookie lesen.
    result = subprocess.run(
        [BITCOIN_CLI, f'-datadir={BCH_DATADIR}', 'getblockchaininfo'],
        capture_output=True,
        text=True,
        timeout=8,
        check=True
    )

    return json.loads(result.stdout)


# ============================================================
# BCHN - Anzahl verbundener Peers
# ============================================================

def bchn_peers():
    result = subprocess.run(
        [BITCOIN_CLI, f'-datadir={BCH_DATADIR}', 'getconnectioncount'],
        capture_output=True,
        text=True,
        timeout=8,
        check=True
    )

    return int(result.stdout.strip())


# ============================================================
# Webseite
# ============================================================

@app.get('/')
def index():
    return render_template(
        'index.html',
        stratum_host=STRATUM_HOST,
        stratum_port=STRATUM_PORT
    )


# ============================================================
# API - Node-Status und Mining-Statistiken
# ============================================================

@app.get('/api/status')
def status():

    payload = {
        'updated_at': datetime.now(timezone.utc).isoformat(),

        'node': {
            'online': False,
            'blocks': None,
            'headers': None,
            'difficulty': None,
            'peers': None,
            'verificationprogress': None,
            'initialblockdownload': None,
            'error': None
        },

        'mining': {
            'hashrate': None,
            'miners': None,
            'accepted': None,
            'rejected': None,
            'best_diff': None,
            'blocks_found': None
        }
    }

    # --------------------------------------------------------
    # BCHN - Blockchain-Status
    # --------------------------------------------------------

    try:
        info = bchn_info()

        payload['node'].update({
            'online': True,
            'blocks': info.get('blocks'),
            'headers': info.get('headers'),
            'difficulty': info.get('difficulty'),
            'verificationprogress': info.get('verificationprogress'),
            'initialblockdownload': info.get('initialblockdownload')
        })

        # Anzahl verbundener Peers separat abfragen.
        # Ein Fehler darf den Blockchain-Status nicht beeinflussen.
        try:
            payload['node']['peers'] = bchn_peers()

        except (OSError, subprocess.SubprocessError, ValueError) as exc:
            app.logger.warning(
                "BCHN peer count unavailable: %s",
                exc
            )

    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        payload['node']['error'] = str(exc)[:200]

    try:
        payload['mining']['uptime'] = ckpool_uptime()
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        payload['mining']['uptime'] = None
        app.logger.warning("CKPool uptime unavailable: %s", exc)

    # --------------------------------------------------------
    # CKPool - Mining-Statistiken
    # --------------------------------------------------------

    payload['mining'].update({
        'online': False,
        'workers': [],
        'clients': [],
        'error': None
    })

    try:
        stats = get_poolstats()

        payload['mining']['online'] = True

        payload['mining']['hashrate'] = dsps_to_ghs(
            stats.get('dsps5')
        )

        payload['mining']['miners'] = stats.get('workers')
        payload['mining']['accepted'] = stats.get('accepted')
        payload['mining']['rejected'] = stats.get('rejected')

        # ----------------------------------------------------
        # Worker-Daten
        # ----------------------------------------------------

        try:
            workers = get_workers()

            payload['mining']['workers'] = workers.get(
                'workers', []
            )

        except (OSError, ValueError, TypeError) as exc:
            app.logger.warning(
                "CKPool workers unavailable: %s",
                exc
            )

        # ----------------------------------------------------
        # Client-Daten
        # ----------------------------------------------------

        try:
            clients = get_clients()

            payload['mining']['clients'] = clients.get(
                'clients', []
            )

        except (OSError, ValueError, TypeError) as exc:
            app.logger.warning(
                "CKPool clients unavailable: %s",
                exc
            )

    except (OSError, ValueError, TypeError) as exc:
        payload['mining']['error'] = str(exc)[:200]

    return jsonify(payload)



# ============================================================
# API - Gefundene Mainnet-Blöcke
# ============================================================

BLOCK_CACHE = {
    "data": None,
    "timestamp": 0
}

BLOCK_CACHE_LOCK = threading.Lock()


@app.get('/api/blocks')
def api_blocks():
    with BLOCK_CACHE_LOCK:
        now = time.monotonic()

        if (BLOCK_CACHE["data"] is not None
                and now - BLOCK_CACHE["timestamp"] < 60):
            return jsonify(BLOCK_CACHE["data"])

        try:
            blocks = get_block_history(50)

            heights = set()

            with LOGFILE.open(
                "r", encoding="utf-8", errors="replace"
            ) as logfile:
                for line in logfile:
                    match = BLOCK_PATTERN.search(line)
                    if match:
                        heights.add(int(match.group(2)))

            payload = {
                "blocks": blocks,
                "count": len(heights),
                "error": None
            }

            BLOCK_CACHE["data"] = payload
            BLOCK_CACHE["timestamp"] = time.monotonic()

            return jsonify(payload)

        except Exception as exc:
            app.logger.exception("Blockhistorie fehlgeschlagen")
            return jsonify({
                "blocks": [],
                "count": 0,
                "error": str(exc)[:200]
            }), 500


# ============================================================
# Flask Webserver
# ============================================================

if __name__ == '__main__':
    app.run(
        host=os.environ.get(
            'DASHBOARD_HOST',
            '192.168.178.36'
        ),
        port=8080,
        debug=False
    )
