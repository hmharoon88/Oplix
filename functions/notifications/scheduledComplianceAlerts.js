/**
 * Cloud Function: daily push for compliance, lease/license, and documents.
 *
 * Respects per-facility `notificationSettings`:
 *   - profile_expiry      — lease & license rows on the facility profile
 *   - compliance_expiry   — complianceItems subcollection
 *   - document_expiry     — uploaded documents with expiry dates
 *
 * User-level gating: notificationPrefs.categories.complianceAlert
 */

const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {sendPushToUser} = require("./sendPush");

const BUILTIN_SLOTS = [
  {id: "lease", label: "Lease"},
  {id: "food_license", label: "Food license"},
  {id: "liquor_license", label: "Liquor license"},
  {id: "cigarette_license", label: "Retail cigarette license"},
  {id: "tobacco_license", label: "Tobacco license"},
  {id: "workers_comp", label: "Bureau of Workers Compensation"},
  {id: "insurance", label: "Insurance"},
];

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value.toDate === "function") return value.toDate();
  if (typeof value === "number") return new Date(value);
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      return new Date(`${trimmed}T12:00:00`);
    }
    return new Date(trimmed);
  }
  return null;
}

function startOfDay(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

function addDays(d, n) {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

function isTypeEnabled(settings, typeId) {
  const items = (settings && settings.items) || {};
  const row = items[typeId];
  return row && typeof row === "object" ? row.enabled !== false : true;
}

function leadDays(settings, typeId, fallback) {
  const items = (settings && settings.items) || {};
  const row = items[typeId];
  const n = parseInt(row && row.leadDays, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

function normalizeProfileEntry(raw) {
  const row = raw || {};
  return {
    expiryDate: String(row.expiryDate || "").trim(),
    notifyOnExpiry: row.notifyOnExpiry !== false,
  };
}

function enabledProfileSlots(slotConfig) {
  const raw = slotConfig && Array.isArray(slotConfig.slots) ? slotConfig.slots : [];
  const builtinById = Object.fromEntries(BUILTIN_SLOTS.map((s) => [s.id, s]));
  const out = [];
  const seen = new Set();

  raw.forEach((s) => {
    if (!s || !s.id || seen.has(s.id)) return;
    seen.add(s.id);
    if (s.custom) {
      if (s.enabled === false) return;
      out.push({id: s.id, label: String(s.label || "Custom item").trim() || "Custom item"});
      return;
    }
    const builtin = builtinById[s.id];
    if (!builtin || s.enabled === false) return;
    out.push({id: s.id, label: builtin.label});
  });

  if (!out.length) {
    BUILTIN_SLOTS.forEach((s) => out.push({id: s.id, label: s.label}));
  }
  return out;
}

function profileNeedsAttention(location, leadDaysOverride) {
  const slots = enabledProfileSlots(location.profileSlotConfig);
  const entries = (location.facilityProfile && typeof location.facilityProfile === "object")
      ? location.facilityProfile
      : {};
  const today = startOfDay(new Date());
  let count = 0;

  slots.forEach((slot) => {
    const entry = normalizeProfileEntry(entries[slot.id]);
    if (!entry.expiryDate || !entry.notifyOnExpiry) return;
    const exp = toDate(entry.expiryDate);
    if (!exp) return;
    const diff = Math.ceil((startOfDay(exp) - today) / (86400000));
    if (diff < 0 || diff <= leadDaysOverride) count += 1;
  });

  return count;
}

function normalizeComplianceItem(raw) {
  const item = raw || {};
  return {
    active: item.active !== false,
    status: String(item.status || "active"),
    expiryDate: String(item.expiryDate || item.dueDate || "").slice(0, 10),
    renewalDueDate: String(item.renewalDueDate || "").slice(0, 10),
  };
}

function complianceNeedsAttention(item, withinDays) {
  const row = normalizeComplianceItem(item);
  if (!row.active || row.status === "not_applicable") return false;

  const today = startOfDay(new Date());
  const exp = toDate(row.expiryDate);
  const daysUntil = exp
      ? Math.round((startOfDay(exp) - today) / 86400000)
      : null;

  if (row.status === "expired") return true;
  if (daysUntil != null && daysUntil < 0) return true;

  if (row.status === "pending_renewal") {
    const due = toDate(row.renewalDueDate || row.expiryDate);
    if (due && startOfDay(due) < today) return true;
  }

  if (daysUntil != null && daysUntil >= 0 && daysUntil <= withinDays) return true;
  return false;
}

function documentsNeedingAttention(documents, leadDays) {
  const now = startOfDay(new Date());
  const cutoff = addDays(now, leadDays);
  let count = 0;

  (documents || []).forEach((doc) => {
    const exp = toDate(doc.expiryDate);
    if (!exp) return;
    const expDay = startOfDay(exp);
    if (expDay <= cutoff) count += 1;
  });

  return count;
}

function buildPushContent(locationName, profileCount, complianceCount, documentCount) {
  const parts = [];
  if (profileCount > 0) {
    const s = profileCount === 1 ? "" : "s";
    parts.push(`${profileCount} lease/license item${s} need attention`);
  }
  if (complianceCount > 0) {
    const s = complianceCount === 1 ? "" : "s";
    parts.push(`${complianceCount} compliance record${s} need attention`);
  }
  if (documentCount > 0) {
    const s = documentCount === 1 ? "" : "s";
    parts.push(`${documentCount} document${s} expiring soon`);
  }
  if (!parts.length) return null;
  return {
    title: locationName || "Facility",
    body: parts.join(" · "),
  };
}

exports.scheduledComplianceAlerts = onSchedule(
    {
      schedule: "15 8 * * *",
      timeZone: "America/New_York",
      region: "us-central1",
    },
    async () => {
      const db = getFirestore();
      const locationsSnap = await db.collectionGroup("locations").get();

      let sent = 0;
      let skipped = 0;

      await Promise.all(locationsSnap.docs.map(async (locDoc) => {
        const parent = locDoc.ref.parent && locDoc.ref.parent.parent;
        const managerId = parent ? parent.id : null;
        if (!managerId) return;

        const location = locDoc.data();
        const locationId = locDoc.id;
        const locationName = location.name || "Facility";
        const settings = location.notificationSettings || {};

        const profileEnabled = isTypeEnabled(settings, "profile_expiry");
        const complianceEnabled = isTypeEnabled(settings, "compliance_expiry");
        const documentsEnabled = isTypeEnabled(settings, "document_expiry");

        if (!profileEnabled && !complianceEnabled && !documentsEnabled) {
          skipped += 1;
          return;
        }

        const profileLead = leadDays(settings, "profile_expiry", 60);
        const complianceLead = leadDays(settings, "compliance_expiry", 60);
        const documentLead = leadDays(settings, "document_expiry", 30);

        const fetches = [];
        if (complianceEnabled) {
          fetches.push(locDoc.ref.collection("complianceItems").get());
        } else {
          fetches.push(Promise.resolve({docs: []}));
        }
        if (documentsEnabled) {
          fetches.push(locDoc.ref.collection("documents").get());
        } else {
          fetches.push(Promise.resolve({docs: []}));
        }

        const [complianceSnap, documentsSnap] = await Promise.all(fetches);

        const profileCount = profileEnabled
            ? profileNeedsAttention(location, profileLead)
            : 0;
        const complianceCount = complianceEnabled
            ? complianceSnap.docs
                .map((d) => d.data())
                .filter((item) => complianceNeedsAttention(item, complianceLead))
                .length
            : 0;
        const documentCount = documentsEnabled
            ? documentsNeedingAttention(
                documentsSnap.docs.map((d) => d.data()),
                documentLead,
            )
            : 0;

        const content = buildPushContent(
            locationName,
            profileCount,
            complianceCount,
            documentCount,
        );
        if (!content) {
          skipped += 1;
          return;
        }

        const result = await sendPushToUser({
          userId: managerId,
          category: "complianceAlert",
          title: content.title,
          body: content.body,
          data: {
            locationId,
            alertKind: "compliance_expiry",
          },
        });

        if (result.sent > 0) sent += 1;
        else skipped += 1;
      }));

      console.log(`scheduledComplianceAlerts: sent=${sent} skipped=${skipped}`);
    },
);
