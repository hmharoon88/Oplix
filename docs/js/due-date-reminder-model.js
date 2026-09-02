/**
 * Per-item due-date reminder settings — iOS parity (`DueDateReminder.swift`).
 *
 * Firestore shape on any dated item:
 *   dueReminder: { enabled, daysBefore, push }
 *   dueReminderSentOn: "YYYY-MM-DD" — set by Cloud Functions after a push fires
 */
(function () {
    const DAYS_BEFORE_OPTIONS = [
        { value: 0, label: "On due date" },
        { value: 1, label: "1 day before" },
        { value: 3, label: "3 days before" },
        { value: 7, label: "7 days before" },
        { value: 14, label: "14 days before" },
        { value: 30, label: "30 days before" },
    ];

    const VALID_DAYS = new Set(DAYS_BEFORE_OPTIONS.map((o) => o.value));

    function defaultDueReminder() {
        return { enabled: false, daysBefore: 0, push: true };
    }

    function normalizeDueReminder(raw) {
        const base = defaultDueReminder();
        const row = raw && typeof raw === "object" ? raw : {};
        const days = parseInt(row.daysBefore, 10);
        return {
            enabled: !!row.enabled,
            daysBefore: VALID_DAYS.has(days) ? days : base.daysBefore,
            push: row.push !== false,
        };
    }

    function shouldClearSentFlag(oldDue, newDue, oldReminder, newReminder) {
        const a = oldDue ? String(oldDue).slice(0, 10) : "";
        const b = newDue ? String(newDue).slice(0, 10) : "";
        if (a !== b) return true;
        const o = normalizeDueReminder(oldReminder);
        const n = normalizeDueReminder(newReminder);
        return JSON.stringify(o) !== JSON.stringify(n);
    }

    function renderDueReminderFields(reminder, namePrefix) {
        const p = namePrefix || "dueReminder";
        const r = normalizeDueReminder(reminder);
        const opts = DAYS_BEFORE_OPTIONS.map(
            (o) =>
                `<option value="${o.value}"${o.value === r.daysBefore ? " selected" : ""}>${o.label}</option>`
        ).join("");
        return `
            <fieldset class="books-fieldset due-reminder-fieldset">
                <legend class="books-label">Reminder</legend>
                <label class="settings-toggle-row">
                    <span class="settings-toggle-text">Remind me</span>
                    <input type="checkbox" name="${p}.enabled"${r.enabled ? " checked" : ""}>
                </label>
                <label class="books-label due-reminder-when"${r.enabled ? "" : " hidden"}>
                    When
                    <select class="books-select" name="${p}.daysBefore">${opts}</select>
                </label>
                <label class="settings-toggle-row due-reminder-push"${r.enabled ? "" : " hidden"}>
                    <span class="settings-toggle-text">Push notification</span>
                    <input type="checkbox" name="${p}.push"${r.push ? " checked" : ""}>
                </label>
                <p class="books-hint due-reminder-hint"${r.enabled ? "" : " hidden"}>Push fires on the selected day when notifications are enabled in Settings.</p>
            </fieldset>`;
    }

    function readDueReminderFromForm(form, namePrefix) {
        const p = namePrefix || "dueReminder";
        const enabled = !!form.querySelector(`[name="${p}.enabled"]`)?.checked;
        const days = parseInt(form.querySelector(`[name="${p}.daysBefore"]`)?.value, 10);
        const push = form.querySelector(`[name="${p}.push"]`)?.checked !== false;
        return normalizeDueReminder({ enabled, daysBefore: days, push });
    }

    function wireDueReminderForm(form) {
        const enabled = form.querySelector('[name="dueReminder.enabled"]');
        if (!enabled) return;
        const sync = () => {
            const on = enabled.checked;
            form.querySelectorAll(".due-reminder-when, .due-reminder-push, .due-reminder-hint").forEach((el) => {
                el.hidden = !on;
            });
        };
        enabled.addEventListener("change", sync);
        sync();
    }

    window.OplixDueDateReminderModel = {
        DAYS_BEFORE_OPTIONS,
        defaultDueReminder,
        normalizeDueReminder,
        shouldClearSentFlag,
        renderDueReminderFields,
        readDueReminderFromForm,
        wireDueReminderForm,
    };
})();
