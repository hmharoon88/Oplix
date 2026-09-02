/**
 * Daily push for per-item due-date reminders.
 *
 * Scans payables, receivables, location reminders, org todos, and
 * documents that have `dueReminder.enabled` and fires a push on the
 * configured day (due date minus `daysBefore`).
 */

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {sendPushToUser} = require('./sendPush');

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      return new Date(`${trimmed}T12:00:00`);
    }
    return new Date(trimmed);
  }
  if (typeof value === 'number') return new Date(value);
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

function formatYMD(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function normalizeReminder(raw) {
  const row = raw && typeof raw === 'object' ? raw : {};
  const days = parseInt(row.daysBefore, 10);
  const validDays = new Set([0, 1, 3, 7, 14, 30]);
  return {
    enabled: !!row.enabled,
    daysBefore: validDays.has(days) ? days : 0,
    push: row.push !== false,
  };
}

function reminderTriggerKey(dueDate, daysBefore) {
  const due = startOfDay(dueDate);
  return formatYMD(addDays(due, -daysBefore));
}

function shouldSendToday(dueDate, reminder, sentOn) {
  const cfg = normalizeReminder(reminder);
  if (!cfg.enabled || !cfg.push || !dueDate) return false;
  const todayKey = formatYMD(startOfDay(new Date()));
  const triggerKey = reminderTriggerKey(dueDate, cfg.daysBefore);
  if (todayKey < triggerKey) return false;
  if (sentOn) return false;
  return true;
}

function formatCurrency(amount) {
  return new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD'}).format(amount || 0);
}

async function markSent(ref) {
  try {
    await ref.set({dueReminderSentOn: formatYMD(new Date())}, {merge: true});
  } catch (err) {
    console.warn('⚠️ Failed to mark due reminder sent:', err.message);
  }
}

async function processItem({
  ref,
  recipientId,
  dueDate,
  reminder,
  sentOn,
  title,
  body,
  data,
}) {
  if (!recipientId || !shouldSendToday(dueDate, reminder, sentOn)) {
    return {sent: 0, skipped: 1};
  }
  const result = await sendPushToUser({
    userId: recipientId,
    category: 'dueReminder',
    title,
    body,
    data,
  });
  if (result.sent > 0) {
    await markSent(ref);
    return {sent: 1, skipped: 0};
  }
  return {sent: 0, skipped: 1};
}

function managerIdFromLocationRef(locDoc) {
  const parent = locDoc.ref.parent && locDoc.ref.parent.parent;
  return parent ? parent.id : null;
}

exports.scheduledDueDateReminders = onSchedule(
    {
      schedule: '30 7 * * *',
      timeZone: 'America/New_York',
      region: 'us-central1',
    },
    async () => {
      const db = getFirestore();
      let sent = 0;
      let skipped = 0;

      const locationsSnap = await db.collectionGroup('locations').get();
      await Promise.all(locationsSnap.docs.map(async (locDoc) => {
        const managerId = managerIdFromLocationRef(locDoc);
        if (!managerId) return;
        const locationId = locDoc.id;
        const locationName = locDoc.data().name || 'Facility';

        const [payablesSnap, receivablesSnap, remindersSnap, documentsSnap] = await Promise.all([
          locDoc.ref.collection('payables').get(),
          locDoc.ref.collection('receivables').get(),
          locDoc.ref.collection('reminders').get(),
          locDoc.ref.collection('documents').get(),
        ]);

        for (const doc of payablesSnap.docs) {
          const p = doc.data();
          if (p.isPaid) continue;
          const due = toDate(p.dueDate);
          const label = p.payTo || 'Payable';
          const r = await processItem({
            ref: doc.ref,
            recipientId: managerId,
            dueDate: due,
            reminder: p.dueReminder,
            sentOn: p.dueReminderSentOn,
            title: 'Payable reminder',
            body: `${label} · ${formatCurrency(p.amount)} due ${formatDueLabel(due, p.dueReminder)}`,
            data: {locationId, itemKind: 'payable', itemId: doc.id},
          });
          sent += r.sent;
          skipped += r.skipped;
        }

        for (const doc of receivablesSnap.docs) {
          const r = doc.data();
          if (r.isReceived) continue;
          const due = toDate(r.dueDate);
          const label = r.receiveFrom || 'Receivable';
          const result = await processItem({
            ref: doc.ref,
            recipientId: managerId,
            dueDate: due,
            reminder: r.dueReminder,
            sentOn: r.dueReminderSentOn,
            title: 'Receivable reminder',
            body: `${label} · ${formatCurrency(r.amount)} due ${formatDueLabel(due, r.dueReminder)}`,
            data: {locationId, itemKind: 'receivable', itemId: doc.id},
          });
          sent += result.sent;
          skipped += result.skipped;
        }

        for (const doc of remindersSnap.docs) {
          const item = doc.data();
          if (item.isCompleted) continue;
          const due = toDate(item.dueDate);
          const result = await processItem({
            ref: doc.ref,
            recipientId: managerId,
            dueDate: due,
            reminder: item.dueReminder,
            sentOn: item.dueReminderSentOn,
            title: locationName,
            body: `Reminder: ${item.title || 'Task'} · due ${formatDueLabel(due, item.dueReminder)}`,
            data: {locationId, itemKind: 'reminder', itemId: doc.id},
          });
          sent += result.sent;
          skipped += result.skipped;
        }

        for (const doc of documentsSnap.docs) {
          const item = doc.data();
          const due = toDate(item.expiryDate);
          const result = await processItem({
            ref: doc.ref,
            recipientId: managerId,
            dueDate: due,
            reminder: item.dueReminder,
            sentOn: item.dueReminderSentOn,
            title: locationName,
            body: `Document expiring: ${item.name || 'Document'} · ${formatDueLabel(due, item.dueReminder)}`,
            data: {locationId, itemKind: 'document', itemId: doc.id},
          });
          sent += result.sent;
          skipped += result.skipped;
        }
      }));

      const usersSnap = await db.collection('users').get();
      await Promise.all(usersSnap.docs.map(async (userDoc) => {
        const todosSnap = await userDoc.ref.collection('orgTodos').get();
        for (const doc of todosSnap.docs) {
          const item = doc.data();
          if (item.isCompleted) continue;
          const due = toDate(item.dueDate);
          const result = await processItem({
            ref: doc.ref,
            recipientId: userDoc.id,
            dueDate: due,
            reminder: item.dueReminder,
            sentOn: item.dueReminderSentOn,
            title: 'To-do reminder',
            body: `${item.title || 'To-do'} · due ${formatDueLabel(due, item.dueReminder)}`,
            data: {itemKind: 'orgTodo', itemId: doc.id},
          });
          sent += result.sent;
          skipped += result.skipped;
        }
      }));

      console.log(`scheduledDueDateReminders: sent=${sent} skipped=${skipped}`);
    },
);

function formatDueLabel(dueDate, reminder) {
  if (!dueDate) return 'soon';
  const cfg = normalizeReminder(reminder);
  const dueKey = formatYMD(startOfDay(dueDate));
  const todayKey = formatYMD(startOfDay(new Date()));
  if (dueKey === todayKey) return 'today';
  if (cfg.daysBefore > 0 && reminderTriggerKey(dueDate, cfg.daysBefore) === todayKey) {
    return `in ${cfg.daysBefore} day${cfg.daysBefore === 1 ? '' : 's'}`;
  }
  return dueDate.toLocaleDateString('en-US', {month: 'short', day: 'numeric'});
}

module.exports.__test__ = {shouldSendToday, reminderTriggerKey, normalizeReminder};
