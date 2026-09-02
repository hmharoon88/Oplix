/**
 * Cloud Function: daily push for overdue payables and receivables.
 *
 * Runs once per morning (America/New_York). For each facility, reads
 * `notificationSettings` on the location doc and sends a push to the
 * owning manager when overdue items exist and the matching facility
 * toggle is on.
 *
 * User-level gating uses `notificationPrefs.categories.financeAlert`
 * (defaults to on). Transport gating uses `channels.push`.
 *
 * Only payables/receivables with `createdSource: "ios"` (or no source on
 * legacy rows) are included — web-created rows are excluded from push.
 */

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {sendPushToUser} = require('./sendPush');

const NOTIFICATION_DEFAULTS = {
  payables_overdue: true,
  receivables_overdue: true,
};

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'number') return new Date(value);
  if (typeof value === 'string') return new Date(value);
  return null;
}

function startOfDay(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

function formatCurrency(amount) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount || 0);
}

function normalizeNotificationSettings(raw) {
  const items = (raw && raw.items && typeof raw.items === 'object') ? raw.items : {};
  const out = {};
  for (const [typeId, fallback] of Object.entries(NOTIFICATION_DEFAULTS)) {
    const row = items[typeId];
    out[typeId] = row && typeof row === 'object' ? row.enabled !== false : fallback;
  }
  return out;
}

function isEnabled(settings, typeId) {
  const normalized = normalizeNotificationSettings(settings);
  return normalized[typeId] !== false;
}

/** Push finance alerts for app-created rows only (not web books flow). */
function isAppCreated(item) {
  const source = item && item.createdSource;
  if (source === 'web') return false;
  return true;
}

function overduePayables(payables, todayStart) {
  return (payables || []).filter((p) => {
    if (!isAppCreated(p)) return false;
    if (p.isPaid) return false;
    const due = toDate(p.dueDate);
    return due && startOfDay(due) < todayStart;
  });
}

function overdueReceivables(receivables, todayStart) {
  return (receivables || []).filter((r) => {
    if (!isAppCreated(r)) return false;
    if (r.isReceived) return false;
    const due = toDate(r.dueDate);
    return due && startOfDay(due) < todayStart;
  });
}

function buildPushContent(locationName, overdueP, overdueR) {
  const parts = [];
  if (overdueP.length) {
    const total = overdueP.reduce((s, p) => s + (p.amount || 0), 0);
    const s = overdueP.length === 1 ? '' : 's';
    parts.push(`${overdueP.length} payable${s} overdue · ${formatCurrency(total)}`);
  }
  if (overdueR.length) {
    const total = overdueR.reduce((s, r) => s + (r.amount || 0), 0);
    const s = overdueR.length === 1 ? '' : 's';
    parts.push(`${overdueR.length} receivable${s} overdue · ${formatCurrency(total)}`);
  }
  if (!parts.length) return null;
  return {
    title: locationName || 'Facility',
    body: parts.join(' · '),
  };
}

exports.scheduledFinanceAlerts = onSchedule(
    {
      schedule: '0 8 * * *',
      timeZone: 'America/New_York',
      region: 'us-central1',
    },
    async () => {
      const db = getFirestore();
      const todayStart = startOfDay(new Date());
      const locationsSnap = await db.collectionGroup('locations').get();

      let sent = 0;
      let skipped = 0;

      await Promise.all(locationsSnap.docs.map(async (locDoc) => {
        const parent = locDoc.ref.parent && locDoc.ref.parent.parent;
        const managerId = parent ? parent.id : null;
        if (!managerId) return;

        const location = locDoc.data();
        const locationId = locDoc.id;
        const locationName = location.name || 'Facility';
        const settings = location.notificationSettings;

        const payablesEnabled = isEnabled(settings, 'payables_overdue');
        const receivablesEnabled = isEnabled(settings, 'receivables_overdue');
        if (!payablesEnabled && !receivablesEnabled) {
          skipped += 1;
          return;
        }

        const [payablesSnap, receivablesSnap] = await Promise.all([
          locDoc.ref.collection('payables').get(),
          locDoc.ref.collection('receivables').get(),
        ]);

        const payables = payablesSnap.docs.map((d) => d.data());
        const receivables = receivablesSnap.docs.map((d) => d.data());

        const overdueP = payablesEnabled ? overduePayables(payables, todayStart) : [];
        const overdueR = receivablesEnabled ? overdueReceivables(receivables, todayStart) : [];

        const content = buildPushContent(locationName, overdueP, overdueR);
        if (!content) {
          skipped += 1;
          return;
        }

        const result = await sendPushToUser({
          userId: managerId,
          category: 'financeAlert',
          title: content.title,
          body: content.body,
          data: {
            locationId,
            alertKind: 'finance_overdue',
          },
        });

        if (result.sent > 0) sent += 1;
        else skipped += 1;
      }));

      console.log(`scheduledFinanceAlerts: sent=${sent} skipped=${skipped}`);
    },
);
