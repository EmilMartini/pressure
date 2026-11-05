// Pressure telemetry endpoint, alternative: a Google Apps Script web app that appends each
// posted record to a Google Sheet (no Cloudflare account needed).
//
// Setup
//   1. Create a Google Sheet (any name). Extensions > Apps Script. Replace Code.gs with this file.
//   2. Project Settings (gear) > Script Properties > add DUMP_KEY = a long random string.
//   3. Deploy > New deployment > type "Web app". Execute as: Me. Who has access: Anyone.
//      Authorize when asked. Copy the Web app URL (ends in /exec).
//   4. In scripts/telemetry.gd set ENDPOINT to that URL and ENDPOINT_SIMPLE = true.
//      Apps Script cannot answer a CORS preflight, so the web build must send a "simple"
//      request (text/plain, no X-Build header); the build is inside the record anyway.
//      The response itself is a redirect the browser may not let the game read; the row is
//      written before that, so a record can be sent twice (the analysis dedupes by run_id).
//   5. After changing this script: Deploy > Manage deployments > edit > Version: New version.
//
// Rows: received time, run_id, kind, build, partial, then the JSON split over as many cells as
// needed (a cell holds at most 50,000 characters).
//
// Fetch the data
//   curl -sL "<exec URL>?key=<DUMP_KEY>" > dump.jsonl
//   python tools/analyze_telemetry.py dump.jsonl
//   (Partial uploads and their final versions are separate rows; the analysis keeps the
//   finished one per run_id.)

var MAX_BYTES = 256 * 1024;
var CHUNK = 45000;
var SHEET = "runs";

function sheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  return ss.getSheetByName(SHEET) || ss.insertSheet(SHEET);
}

function doPost(e) {
  var body = (e && e.postData && e.postData.contents) || "";
  if (body.length === 0 || body.length > MAX_BYTES) {
    return ContentService.createTextOutput("rejected");
  }
  var rec;
  try {
    rec = JSON.parse(body);
  } catch (err) {
    return ContentService.createTextOutput("not json");
  }
  if (!rec || typeof rec !== "object" || !/^[A-Za-z0-9-]{4,40}$/.test(String(rec.run_id || ""))) {
    return ContentService.createTextOutput("bad record");
  }
  var row = [new Date(), String(rec.run_id), String(rec.kind || ""), String(rec.build || ""), rec.partial === true];
  for (var i = 0; i < body.length; i += CHUNK) {
    row.push(body.substring(i, i + CHUNK));
  }
  var lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    sheet_().appendRow(row);
  } finally {
    lock.releaseLock();
  }
  return ContentService.createTextOutput("ok");
}

function doGet(e) {
  var want = PropertiesService.getScriptProperties().getProperty("DUMP_KEY");
  if (!want || !e || !e.parameter || e.parameter.key !== want) {
    return ContentService.createTextOutput("forbidden");
  }
  var values = sheet_().getDataRange().getValues();
  var lines = [];
  for (var r = 0; r < values.length; r++) {
    var parts = values[r].slice(5).filter(function (c) { return c !== ""; });
    if (parts.length > 0) lines.push(parts.join(""));
  }
  return ContentService.createTextOutput(lines.join("\n") + "\n").setMimeType(ContentService.MimeType.TEXT);
}
