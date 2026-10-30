import json
import re
import subprocess
from datetime import datetime
from pathlib import Path

LOGFILE = Path(
    "/opt/bch-solo-pool/ckpool/logs/ckpool.log"
)

DATADIR = "/var/lib/bch-node"
BITCOIN_CLI = "/usr/local/bin/bitcoin-cli"

PAYOUT_SCRIPT = (
    "76a914cb253d57d470b7309c3c1ac8a17c0ce418df5c8388ac"
)

BLOCK_PATTERN = re.compile(
    r"\[(.*?)\] Solved and confirmed block "
    r"(\d+) by (\S+) on SV1"
)


def bchn_rpc(command, *args):
    result = subprocess.run(
        [
            BITCOIN_CLI,
            f"-datadir={DATADIR}",
            command,
            *map(str, args)
        ],
        capture_output=True,
        text=True,
        timeout=10,
        check=True
    )

    return result.stdout.strip()


def get_block_history(limit=50):
    if not LOGFILE.exists():
        return []

    found = {}

    with LOGFILE.open(
        "r", encoding="utf-8", errors="replace"
    ) as logfile:
        for line in logfile:
            match = BLOCK_PATTERN.search(line)

            if not match:
                continue

            timestamp, height, miner = match.groups()
            height = int(height)

            found[height] = {
                "height": height,
                "time": timestamp,
                "miner": miner
            }

    blocks = sorted(
        found.values(),
        key=lambda b: b["height"],
        reverse=True
    )[:limit]

    for block in blocks:
        try:
            block_hash = bchn_rpc(
                "getblockhash", block["height"]
            )

            block_info = json.loads(
                bchn_rpc("getblock", block_hash, 2)
            )

            block["hash"] = block_hash
            block["confirmations"] = block_info.get(
                "confirmations", 0
            )

            coinbase = block_info["tx"][0]
            outputs = coinbase.get("vout", [])

            payout_matches = any(
                output.get("scriptPubKey", {}).get("hex", "").lower()
                == PAYOUT_SCRIPT
                for output in outputs
            )

            if payout_matches and block["confirmations"] > 0:
                block["status"] = "confirmed"
            else:
                block["status"] = "not_verified"

        except Exception:
            block["hash"] = None
            block["confirmations"] = 0
            block["status"] = "unknown"

    return blocks


if __name__ == "__main__":
    blocks = get_block_history(10)

    print(json.dumps(blocks, indent=2))
