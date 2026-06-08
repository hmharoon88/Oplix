#!/usr/bin/env node
/**
 * Audit + fix Firestore documents that break iOS Codable decoding.
 * Uses Firebase CLI stored access token (no service account file needed).
 */
import fs from "fs";
import path from "path";
import os from "os";

const PROJECT = "oplix-3183d";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const VALID_FREQ = new Set(["one_time", "daily", "weekly", "monthly"]);
const VALID_SHIFT = new Set(["clockedIn", "clockedOut"]);
const VALID_ROLES = new Set(["manager", "employee", "supervisor"]);

const cfgPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
const TOKEN = cfg.tokens?.access_token;
if (!TOKEN) {
  console.error("No Firebase CLI access token. Run: firebase login");
  process.exit(1);
}

const DRY_RUN = process.argv.includes("--dry-run");
const fixes = [];

async function api(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`${res.status} ${url}\n${text.slice(0, 500)}`);
  }
  return body;
}

function val(v) {
  if (v == null) return undefined;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(val);
  if ("mapValue" in v) {
    const out = {};
    for (const [k, fv] of Object.entries(v.mapValue.fields || {})) out[k] = val(fv);
    return out;
  }
  return v;
}

function decodeDoc(doc) {
  const fields = {};
  for (const [k, fv] of Object.entries(doc.fields || {})) fields[k] = val(fv);
  return { id: doc.name.split("/").pop(), path: doc.name.replace(`projects/${PROJECT}/databases/(default)/documents/`, ""), ...fields };
}

async function listCollection(collectionPath) {
  const docs = [];
  let pageToken;
  do {
    const q = pageToken ? `?pageToken=${encodeURIComponent(pageToken)}` : "";
    const data = await api(`${BASE}/${collectionPath}${q}`);
    for (const doc of data.documents || []) docs.push(decodeDoc(doc));
    pageToken = data.nextPageToken;
  } while (pageToken);
  return docs;
}

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === "object") {
    const fields = {};
    for (const [k, v] of Object.entries(value)) fields[k] = encodeValue(v);
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

async function patchDoc(docPath, fieldUpdates, deleteFields = []) {
  const updateMask = [
    ...Object.keys(fieldUpdates).map((k) => `updateMask.fieldPaths=${k}`),
    ...deleteFields.map((k) => `updateMask.fieldPaths=${k}`),
  ].join("&");
  const fields = {};
  for (const [k, v] of Object.entries(fieldUpdates)) fields[k] = encodeValue(v);

  const body = { fields };
  for (const k of deleteFields) body.fields[k] = { nullValue: null };

  if (DRY_RUN) {
    console.log("[dry-run] PATCH", docPath, JSON.stringify(fieldUpdates), deleteFields);
    return;
  }
  await api(`${BASE}/${docPath}?${updateMask}`, { method: "PATCH", body: JSON.stringify(body) });
}

function queueFix(docPath, updates, deletes = [], reason) {
  fixes.push({ docPath, updates, deletes, reason });
}

function auditTask(task, context) {
  const docPath = task.path;
  const updates = {};
  const deletes = [];

  if (typeof task.id !== "string" || !task.id) {
    updates.id = task.id || task.id === "" ? task.id : docPath.split("/").pop();
    if (!updates.id) queueFix(docPath, { id: docPath.split("/").pop() }, [], `${context}: missing id`);
  }
  if (typeof task.description !== "string") {
    queueFix(docPath, { description: String(task.description ?? "") }, [], `${context}: description not string`);
  }
  if (task.frequency != null && !VALID_FREQ.has(task.frequency)) {
    queueFix(docPath, { frequency: "one_time" }, [], `${context}: bad frequency=${task.frequency}`);
  }
  if (task.assignedEmployeeIds != null && !Array.isArray(task.assignedEmployeeIds)) {
    queueFix(docPath, { assignedEmployeeIds: task.assignedEmployeeIds ? [String(task.assignedEmployeeIds)] : [] }, [], `${context}: assignedEmployeeIds not array`);
  }
  if (task.assignedLocationIds != null && !Array.isArray(task.assignedLocationIds)) {
    queueFix(docPath, { assignedLocationIds: task.assignedLocationIds ? [String(task.assignedLocationIds)] : [] }, [], `${context}: assignedLocationIds not array`);
  }
  if (task.employeeCompletions != null && (typeof task.employeeCompletions !== "object" || Array.isArray(task.employeeCompletions))) {
    queueFix(docPath, { employeeCompletions: {} }, [], `${context}: employeeCompletions not map`);
  }
  if (task.completionHistory != null && !Array.isArray(task.completionHistory)) {
    queueFix(docPath, { completionHistory: [] }, [], `${context}: completionHistory not array`);
  }

  const comps = task.employeeCompletions && typeof task.employeeCompletions === "object" && !Array.isArray(task.employeeCompletions)
    ? task.employeeCompletions
    : {};
  for (const [empId, completion] of Object.entries(comps)) {
    if (!completion || typeof completion !== "object" || Array.isArray(completion)) {
      const fixed = { ...comps };
      delete fixed[empId];
      queueFix(docPath, { employeeCompletions: fixed }, [], `${context}: bad completion for ${empId}`);
      continue;
    }
    if (typeof completion.employeeId !== "string") {
      const fixed = { ...comps, [empId]: { ...completion, employeeId: empId } };
      queueFix(docPath, { employeeCompletions: fixed }, [], `${context}: completion missing employeeId`);
    }
    if (!completion.timestamp) {
      const fixed = { ...comps };
      delete fixed[empId];
      queueFix(docPath, { employeeCompletions: fixed }, [], `${context}: completion missing timestamp for ${empId}`);
    }
  }
}

function auditEmployee(emp, context) {
  const docPath = emp.path;
  if (emp.locationId == null) {
    queueFix(docPath, { locationId: "" }, [], `${context}: locationId null/missing`);
  } else if (typeof emp.locationId !== "string") {
    queueFix(docPath, { locationId: String(emp.locationId) }, [], `${context}: locationId not string`);
  }
  if (emp.currentShiftStatus != null && !VALID_SHIFT.has(emp.currentShiftStatus)) {
    queueFix(docPath, { currentShiftStatus: "clockedOut" }, [], `${context}: bad currentShiftStatus`);
  }
  if (emp.shiftHistory != null && !Array.isArray(emp.shiftHistory)) {
    queueFix(docPath, { shiftHistory: [] }, [], `${context}: shiftHistory not array`);
  }
  if (emp.assignedLocationIds != null && !Array.isArray(emp.assignedLocationIds)) {
    queueFix(docPath, { assignedLocationIds: [] }, [], `${context}: assignedLocationIds not array`);
  }
}

function auditUser(user) {
  const docPath = user.path;
  if (!user.role || !VALID_ROLES.has(user.role)) {
    console.warn("WARN user bad role:", docPath, user.role);
  }
  if (!user.createdAt) {
    queueFix(docPath, { createdAt: new Date().toISOString() }, [], "user: missing createdAt");
  }
}

async function main() {
  console.log(DRY_RUN ? "DRY RUN — no writes" : "LIVE — applying fixes");
  const users = await listCollection("users");
  const managers = users.filter((u) => u.role === "manager");
  console.log(`Found ${users.length} users, ${managers.length} managers`);

  for (const user of users) auditUser(user);

  for (const manager of managers) {
    const mid = manager.id;
    console.log(`\nManager: ${manager.username || manager.organizationName || mid}`);

    const employees = await listCollection(`users/${mid}/employees`);
    for (const emp of employees) auditEmployee(emp, `employee ${emp.id}`);

    const tasks = await listCollection(`users/${mid}/tasks`);
    for (const task of tasks) auditTask(task, `manager-task ${task.id}`);

    const locations = await listCollection(`users/${mid}/locations`);
    for (const loc of locations) {
      const locTasks = await listCollection(`users/${mid}/locations/${loc.id}/tasks`);
      for (const task of locTasks) auditTask(task, `loc-task ${loc.id}/${task.id}`);
    }
  }

  // Dedupe fixes by docPath (merge updates)
  const merged = new Map();
  for (const f of fixes) {
    const prev = merged.get(f.docPath) || { updates: {}, deletes: [], reasons: [] };
    Object.assign(prev.updates, f.updates);
    prev.deletes.push(...f.deletes);
    prev.reasons.push(f.reason);
    merged.set(f.docPath, prev);
  }

  console.log(`\n${merged.size} document(s) need fixes:`);
  for (const [docPath, { updates, deletes, reasons }] of merged) {
    console.log(`- ${docPath}`);
    reasons.forEach((r) => console.log(`    ${r}`));
    await patchDoc(docPath, updates, [...new Set(deletes)]);
  }

  if (merged.size === 0) console.log("No fixable issues found. Bad data may be in shifts/lottery/docs or a field we did not scan.");
  else console.log(DRY_RUN ? "\nRe-run without --dry-run to apply." : "\nDone.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
