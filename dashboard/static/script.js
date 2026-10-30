const $ = (id) => document.getElementById(id);

const number = (v) =>
  Number.isFinite(v)
    ? new Intl.NumberFormat('de-DE').format(v)
    : '—';

const decimal = (v, digits = 2) =>
  Number.isFinite(v)
    ? v.toLocaleString('de-DE', {
        minimumFractionDigits: digits,
        maximumFractionDigits: digits
      })
    : '—';

// =========================================================
// KONFIGURATION
// =========================================================

// Inaktive Miner nach 48 Stunden aus der Tabelle ausblenden.
const MINER_INACTIVE_HOURS = 48;
const MINER_INACTIVE_SECONDS = MINER_INACTIVE_HOURS * 60 * 60;

// Farben fuer den Miner-Status.
const MINER_COLOR_ACTIVE = '#0ac18e';
const MINER_COLOR_INACTIVE = '#f59e0b';

// =========================================================
// FORMATIERUNGEN
// =========================================================

function formatPoolUptime(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return '—';

  const totalMinutes = Math.floor(seconds / 60);
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;

  if (days > 0) {
    return \`\${days} \${days === 1 ? 'Tag' : 'Tage'} \` +
           \`\${hours} Std. \${String(minutes).padStart(2, '0')} Min.\`;
  }

  if (hours > 0) {
    return \`\${hours} Std. \${String(minutes).padStart(2, '0')} Min.\`;
  }

  return \`\${minutes} Min.\`;
}

function formatHashrate(ghs) {
  if (!Number.isFinite(ghs)) return '—';
  if (ghs >= 1000000) return \`\${decimal(ghs / 1000000)} PH/s\`;
  if (ghs >= 1000) return \`\${decimal(ghs / 1000)} TH/s\`;
  return \`\${decimal(ghs)} GH/s\`;
}

function formatNetworkDifficulty(diff) {
  if (!Number.isFinite(diff)) return '—';
  return \`\${decimal(diff / 1e9)} G\`;
}

function formatBestDifficulty(diff) {
  if (!Number.isFinite(diff) || diff < 0) return '—';

  const units = [
    { value: 1e24, unit: 'Y' },
    { value: 1e21, unit: 'Z' },
    { value: 1e18, unit: 'E' },
    { value: 1e15, unit: 'P' },
    { value: 1e12, unit: 'T' },
    { value: 1e9,  unit: 'G' },
    { value: 1e6,  unit: 'M' },
    { value: 1e3,  unit: 'K' }
  ];

  for (const item of units) {
    if (diff >= item.value) {
      return \`\${decimal(diff / item.value)} \${item.unit}\`;
    }
  }

  return decimal(diff, 2);
}

function formatRejectedDifficulty(accepted, rejected) {
  if (!Number.isFinite(rejected) || rejected < 0) return '—';

  const rejectedText = formatBestDifficulty(rejected);

  if (!Number.isFinite(accepted) || accepted < 0) {
    return rejectedText;
  }

  const total = accepted + rejected;

  if (!Number.isFinite(total) || total <= 0) {
    return \`\${rejectedText} (0,00 %)\`;
  }

  const percentage = (rejected / total) * 100;

  return \`\${rejectedText} (\${decimal(percentage, 2)} %)\`;
}

// =========================================================
// BLOCKFUND-CHANCE
// =========================================================

function calculateBlockChance(ghs, difficulty) {
  if (!Number.isFinite(ghs) ||
      !Number.isFinite(difficulty) ||
      ghs < 0 || difficulty <= 0) {
    return '—';
  }

  const hashrate = ghs * 1e9;
  const seconds = 24 * 60 * 60;

  const expectedBlocks =
    (hashrate * seconds) / (difficulty * (2 ** 32));

  const probability = -Math.expm1(-expectedBlocks) * 100;

  return \`\${decimal(probability, 4)} %\`;
}

// =========================================================
// LETZTE AKTIVITAET
// =========================================================

function formatLastShare(timestamp) {
  if (!Number.isFinite(timestamp) || timestamp <= 0) return '—';

  return new Date(timestamp * 1000).toLocaleString('de-DE');
}

// =========================================================
// MINER AKTIVITAET UND 48-STUNDEN-FILTER
// =========================================================

function isMinerVisible(worker, connected, nowSeconds) {

  // Aktive Miner immer anzeigen.
  if (connected) {
    return true;
  }

  const lastShare = worker.lastshare;

  // Kein gueltiger Zeitstempel vorhanden.
  if (!Number.isFinite(lastShare) || lastShare <= 0) {
    return false;
  }

  // Zukuenftige Zeitstempel sichtbar lassen.
  if (lastShare > nowSeconds) {
    return true;
  }

  return (nowSeconds - lastShare) < MINER_INACTIVE_SECONDS;
}

// =========================================================
// VERBUNDENE MINER
// =========================================================

function updateMiners(mining) {
  const tbody = $('miner-rows');
  tbody.replaceChildren();

  let connectedMiners = 0;
  const countElement = $('connected-miner-count');
  countElement.textContent = '0 Miner verbunden';

  if (!mining.online) {
    const row = tbody.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 5;
    cell.className = 'empty';
    cell.textContent = 'CKPool ist offline.';
    return;
  }

  const workers = Array.isArray(mining.workers) ? mining.workers : [];
  const clients = Array.isArray(mining.clients) ? mining.clients : [];

  const nowSeconds = Date.now() / 1000;

  let visibleMiners = 0;

  // Aktive Miner zuerst, inaktive Miner danach.
  const sortedWorkers = [...workers].sort((a, b) => {
    const isConnected = (worker) => clients.some(client =>
      client.workername === (worker.worker || 'Unbekannt') &&
      client.authorised === true &&
      client.idle !== true
    );

    return Number(isConnected(b)) - Number(isConnected(a));
  });

  for (const worker of sortedWorkers) {
    const name = worker.worker || 'Unbekannt';

    // Aktive und autorisierte Stratum-Verbindung pruefen.
    const connected = clients.some(client =>
      client.workername === name &&
      client.authorised === true &&
      client.idle !== true
    );

    // Inaktive Miner nach 48 Stunden ausblenden.
    if (!isMinerVisible(worker, connected, nowSeconds)) {
      continue;
    }

    visibleMiners++;

    if (connected) {
      connectedMiners++;
    }

    const ghs = Number.isFinite(worker.dsps5)
      ? worker.dsps5 * (2 ** 32) / 1e9
      : null;

    const bestDiff = Number.isFinite(worker.bestdiff)
      ? formatBestDifficulty(worker.bestdiff)
      : '—';

    const row = tbody.insertRow();

    row.insertCell().textContent = name;
    row.insertCell().textContent = formatHashrate(ghs);
    row.insertCell().textContent = bestDiff;
    row.insertCell().textContent = formatLastShare(worker.lastshare);

    // =====================================================
    // MINER STATUS MIT FARBE
    // =====================================================

    const statusCell = row.insertCell();

    statusCell.textContent = connected ? 'Aktiv' : 'Inaktiv';
    statusCell.style.color = connected
      ? MINER_COLOR_ACTIVE
      : MINER_COLOR_INACTIVE;

    statusCell.style.fontWeight = '600';
  }

  const stratumConnections = clients.filter(client =>
    client.authorised === true &&
    client.idle !== true
  ).length;

  countElement.textContent =
    \`\${connectedMiners} \${connectedMiners === 1 ? 'Miner' : 'Miner'} verbunden \` +
    \`(\${stratumConnections} Stratum)\`;

  if (visibleMiners === 0) {
    const row = tbody.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 5;
    cell.className = 'empty';
    cell.textContent =
      'Keine aktiven Miner oder Miner mit Shares innerhalb der letzten 48 Stunden.';
  }
}

// =========================================================
// DASHBOARD AKTUALISIERUNG
// =========================================================

async function updateStatus() {
  try {
    const response = await fetch('/api/status', { cache: 'no-store' });
    if (!response.ok) throw new Error(\`HTTP \${response.status}\`);

    const data = await response.json();
    const node = data.node;
    const mining = data.mining || {};

    // =========================================================
    // BCHN
    // =========================================================

    $('blocks').textContent = number(node.blocks);
    $('headers').textContent = number(node.headers);

    $('network-difficulty').textContent =
      formatNetworkDifficulty(node.difficulty);

    $('peers').textContent = number(node.peers);

    $('node-online').textContent = node.online ? 'Online' : 'Offline';

    const pct = node.online && Number.isFinite(node.verificationprogress)
      ? Math.max(0, Math.min(100, node.verificationprogress * 100))
      : null;

    $('progress-text').textContent = pct === null
      ? '—'
      : \`\${decimal(pct)} %\`;

    $('progress-bar').style.width = pct === null ? '0%' : \`\${pct}%\`;

    const state = $('node-status');

    state.className = 'status ' +
      (!node.online ? 'offline' : node.initialblockdownload ? 'sync' : 'online');

    state.textContent = !node.online
      ? 'BCHN offline'
      : node.initialblockdownload
        ? 'BCHN synchronisiert gerade'
        : 'BCHN bereit';

    // =========================================================
    // BLOCKCHAIN SYNCHRONISATION
    // =========================================================

    const syncLabel = $('sync-label');

    syncLabel.textContent = !node.online
      ? 'Nicht erreichbar'
      : node.initialblockdownload
        ? 'Sync läuft'
        : 'Synchronisiert';

    syncLabel.className = 'status ' +
      (!node.online
        ? 'offline'
        : node.initialblockdownload
          ? 'sync'
          : 'online');

    // =========================================================
    // CKPOOL
    // =========================================================

    $('hashrate').textContent = mining.online
      ? formatHashrate(mining.hashrate)
      : '—';

    $('pool-uptime').textContent = mining.online
      ? formatPoolUptime(mining.uptime)
      : '—';

    // Aktive Miner und Stratum-Verbindungen getrennt zaehlen.
    const activeClients = Array.isArray(mining.clients)
      ? mining.clients.filter(client =>
          client.authorised === true &&
          client.idle !== true
        )
      : [];

    const activeWorkerNames = new Set(
      activeClients
        .map(client => client.workername)
        .filter(name => typeof name === 'string' && name.length > 0)
    );



    // =========================================================
    // AKZEPTIERTE DIFFICULTY
    // =========================================================

    $('accepted').textContent = mining.online
      ? formatBestDifficulty(mining.accepted)
      : '—';

    // =========================================================
    // ABGELEHNTE DIFFICULTY MIT PROZENTANGABE
    // =========================================================

    $('rejected').textContent = mining.online
      ? formatRejectedDifficulty(mining.accepted, mining.rejected)
      : '—';

    // =========================================================
    // BEST DIFFICULTY DES POOLS
    // =========================================================

    const workers = Array.isArray(mining.workers) ? mining.workers : [];

    const bestDiffs = workers
      .map(worker => worker.bestdiff)
      .filter(Number.isFinite);

    $('best-diff').textContent = mining.online && bestDiffs.length
      ? formatBestDifficulty(Math.max(...bestDiffs))
      : '—';

    // =========================================================
    // BLOCKFUND-CHANCE
    // =========================================================

    $('block-chance').textContent =
      mining.online && node.online
        ? calculateBlockChance(mining.hashrate, node.difficulty)
        : '—';

    // =========================================================
    // MINER TABELLE
    // =========================================================

    updateMiners(mining);

    // =========================================================
    // STATUS MELDUNGEN
    // =========================================================

    $('node-error').textContent = node.error
      ? \`BCHN-Abfrage fehlgeschlagen: \${node.error}\`
      : mining.online
        ? 'CKPool ist online und liefert Mining-Daten.'
        : 'CKPool ist derzeit offline.';

    $('updated').textContent =
      \`Letztes Update: \${new Date(data.updated_at).toLocaleTimeString('de-DE')}\`;

  } catch (err) {
    $('node-status').className = 'status offline';
    $('node-status').textContent = 'Dashboard-API nicht erreichbar';

    $('sync-label').className = 'status offline';
    $('sync-label').textContent = 'Nicht erreichbar';

    $('updated').textContent = String(err);
  }
}

// =========================================================
// START UND AUTOMATISCHE AKTUALISIERUNG
// =========================================================

updateStatus();
setInterval(updateStatus, 5000);

// ============================================================
// BCH Mainnet - Gefundene Blöcke
// ============================================================

async function updateBlocks() {
  const tbody = $('block-rows');
  if (!tbody) return;

  try {
    const response = await fetch('/api/blocks', {
      cache: 'no-store'
    });

    if (!response.ok) {
      throw new Error(\`HTTP \${response.status}\`);
    }

    const data = await response.json();

    if (data.error) {
      throw new Error(data.error);
    }

    const blocks = Array.isArray(data.blocks)
      ? data.blocks
      : [];

    const totalBlocks = $('total-blocks');
    if (totalBlocks) {
      totalBlocks.textContent = number(data.count);
    }

    tbody.replaceChildren();

    if (blocks.length === 0) {
      const row = tbody.insertRow();
      const cell = row.insertCell();
      cell.colSpan = 5;
      cell.className = 'empty';
      cell.textContent = 'Noch keine Blockfunde vorhanden.';
      return;
    }

    for (const block of blocks) {
      const row = tbody.insertRow();

      // Blockhöhe
      row.insertCell().textContent = number(block.height);

      // Fundzeit aus CKPool-Log (lokale Serverzeit)
      row.insertCell().textContent =
        block.time ? block.time.split('.')[0] : '—';

      // Blockhash
      const hashCell = row.insertCell();

      if (block.hash) {
        const hash = document.createElement('span');
        hash.textContent =
          block.hash.slice(0, 12) + '…' +
          block.hash.slice(-8);
        hash.title = block.hash;
        hashCell.appendChild(hash);
      } else {
        hashCell.textContent = '—';
      }

      // Minername ohne Auszahlungsadresse
      const minerName = block.miner
        ? block.miner.split('.').slice(1).join('.') || block.miner
        : '—';

      row.insertCell().textContent = minerName;

      // Bestätigungen und Prüfstatus
      const confirmationCell = row.insertCell();

      if (block.status === 'confirmed') {
        confirmationCell.textContent =
          number(block.confirmations);
      } else {
        confirmationCell.textContent = 'Nicht verifiziert';
      }
    }

  } catch (err) {
    console.error('Blockhistorie:', err);

    if (!tbody.rows.length ||
        tbody.rows[0].classList.contains('empty')) {
      tbody.replaceChildren();

      const row = tbody.insertRow();
      const cell = row.insertCell();
      cell.colSpan = 5;
      cell.className = 'empty';
      cell.textContent = 'Blockhistorie derzeit nicht verfügbar.';
    }
  }
}

// Blockhistorie separat alle 60 Sekunden aktualisieren
updateBlocks();
setInterval(updateBlocks, 60000);
