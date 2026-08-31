// Measurement collector (F1.3, TR-16-TR-19).
//
// Ingests batches of structured measurement records synced from the device
// (specs/phase-1/measurement-harness.md §4). The device persists records
// locally first and retries sync until acknowledged (§3), so this service
// only needs to be idempotent on record_id - re-delivery of an
// already-seen record is a no-op, not a duplicate entry.
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3003;
const RECORDS_DIR = path.join(__dirname, "..", "records");
const RECORDS_FILE = path.join(RECORDS_DIR, "records.ndjson");

fs.mkdirSync(RECORDS_DIR, { recursive: true });

function loadSeenRecordIds() {
  const seen = new Set();
  if (!fs.existsSync(RECORDS_FILE)) return seen;
  const lines = fs.readFileSync(RECORDS_FILE, "utf8").split("\n");
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const rec = JSON.parse(line);
      if (rec.record_id) seen.add(rec.record_id);
    } catch {
      // ignore malformed lines rather than fail startup
    }
  }
  return seen;
}

let seenRecordIds = loadSeenRecordIds();

function isValidRecord(rec) {
  return (
    rec &&
    typeof rec.record_id === "string" &&
    typeof rec.timestamp === "string" &&
    rec.device &&
    typeof rec.device.is_simulator === "boolean" &&
    rec.circuit &&
    rec.backend &&
    rec.metrics &&
    rec.run_context
  );
}

function handleIngest(req, res) {
  let body = "";
  req.on("data", (chunk) => {
    body += chunk;
    // guard against unbounded bodies from a misbehaving client
    if (body.length > 50 * 1024 * 1024) {
      req.destroy();
    }
  });
  req.on("end", () => {
    let records;
    try {
      const parsed = JSON.parse(body);
      records = Array.isArray(parsed) ? parsed : [parsed];
    } catch (err) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "invalid JSON body" }));
      return;
    }

    let accepted = 0;
    let duplicates = 0;
    let rejected = 0;
    const lines = [];

    for (const rec of records) {
      if (!isValidRecord(rec)) {
        rejected++;
        continue;
      }
      if (seenRecordIds.has(rec.record_id)) {
        duplicates++;
        continue;
      }
      seenRecordIds.add(rec.record_id);
      lines.push(JSON.stringify(rec));
      accepted++;
    }

    if (lines.length > 0) {
      fs.appendFileSync(RECORDS_FILE, lines.join("\n") + "\n");
    }

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ accepted, duplicates, rejected }));
  });
}

const server = http.createServer((req, res) => {
  if (req.method === "POST" && req.url === "/records") {
    handleIngest(req, res);
    return;
  }
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, records_seen: seenRecordIds.size }));
    return;
  }
  res.writeHead(404);
  res.end();
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`measurement collector listening on :${PORT}`);
  console.log(`writing to ${RECORDS_FILE}`);
});
