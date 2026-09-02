/**
 * Location receivables — users/.../locations/.../receivables.
 */
(function () {
    const FREQUENCIES = [
        { id: "none", label: "One-time" },
        { id: "weekly", label: "Weekly" },
        { id: "monthly", label: "Monthly" },
    ];

    function toDate(value) {
        if (!value) return null;
        if (typeof value.toDate === "function") return value.toDate();
        if (value instanceof Date) return value;
        const d = new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function isoDateInput(value) {
        const d = toDate(value);
        if (!d) return "";
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }

    function dueTimestampFromInput(isoDateStr) {
        if (!isoDateStr) return null;
        const d = new Date(isoDateStr + "T12:00:00");
        if (Number.isNaN(d.getTime())) return null;
        return firebase.firestore.Timestamp.fromDate(d);
    }

    function defaultReceivable(locationId) {
        return {
            locationId: locationId || "",
            receiveFrom: "",
            amount: 0,
            dueDate: null,
            notes: "",
            frequency: "none",
            isReceived: false,
            receivedAt: null,
            originalReceivableId: null,
            dueReminder: null,
            dueReminderSentOn: null,
        };
    }

    function normalizeDueReminder(raw) {
        return window.OplixDueDateReminderModel
            ? OplixDueDateReminderModel.normalizeDueReminder(raw)
            : { enabled: false, daysBefore: 0, push: true };
    }

    function normalizeReceivable(raw, locationId) {
        const base = defaultReceivable(locationId);
        const r = { ...base, ...(raw || {}) };
        const freq = FREQUENCIES.some((f) => f.id === r.frequency) ? r.frequency : "none";
        return {
            ...r,
            id: r.id || "",
            locationId: r.locationId || locationId || "",
            receiveFrom: String(r.receiveFrom || "").trim(),
            amount: parseFloat(r.amount) || 0,
            notes: r.notes ? String(r.notes) : "",
            frequency: freq,
            isReceived: !!r.isReceived,
            dueDate: r.dueDate || null,
            receivedAt: r.receivedAt || null,
            createdAt: r.createdAt || null,
            originalReceivableId: r.originalReceivableId || null,
            createdSource: r.createdSource || null,
            dueReminder: r.dueDate ? normalizeDueReminder(r.dueReminder) : null,
            dueReminderSentOn: r.dueReminderSentOn || null,
        };
    }

    function monthBounds(monthId) {
        const [y, m] = monthId.split("-").map(Number);
        const start = new Date(y, m - 1, 1);
        const end = new Date(y, m, 0, 23, 59, 59, 999);
        return { start, end };
    }

    function receivedInMonth(r, monthId) {
        const received = toDate(r.receivedAt);
        if (!received) return false;
        const { start, end } = monthBounds(monthId);
        return received >= start && received <= end;
    }

    function sortReceivables(list) {
        return [...(list || [])].sort((a, b) => {
            if (a.isReceived !== b.isReceived) return a.isReceived ? 1 : -1;
            const da = toDate(a.dueDate)?.getTime() || 0;
            const db = toDate(b.dueDate)?.getTime() || 0;
            if (da && db) return da - db;
            if (da) return -1;
            if (db) return 1;
            return (a.receiveFrom || "").localeCompare(b.receiveFrom || "");
        });
    }

    function openReceivables(list) {
        return sortReceivables(list).filter((r) => !r.isReceived);
    }

    function receivedReceivablesForMonth(list, monthId) {
        return sortReceivables(list).filter((r) => r.isReceived && receivedInMonth(r, monthId));
    }

    function openTotal(list) {
        return openReceivables(list).reduce((s, r) => s + (r.amount || 0), 0);
    }

    function normalizePayerKey(name) {
        return String(name || "")
            .trim()
            .toLowerCase()
            .replace(/\s+/g, " ");
    }

    function endOfMonth(date) {
        const d = toDate(date) || new Date();
        return new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
    }

    /**
     * True if a next-period stub already exists for this payer (amount $0, or due after this month).
     * Other open rows for the same payer (another payment this month) do not count.
     */
    function hasCarryForwardOpen(list, receiveFrom, asOfDate) {
        const key = normalizePayerKey(receiveFrom);
        if (!key) return false;
        const monthEnd = endOfMonth(asOfDate || new Date());
        return openReceivables(list).some((r) => {
            if (normalizePayerKey(r.receiveFrom) !== key) return false;
            if (!(parseFloat(r.amount) > 0)) return true;
            const due = toDate(r.dueDate);
            return !!(due && due > monthEnd);
        });
    }

    /** @deprecated use hasCarryForwardOpen — kept name for older callers */
    function hasOpenForPayer(list, receiveFrom) {
        return hasCarryForwardOpen(list, receiveFrom);
    }

    function addMonths(date, months) {
        const d = new Date(date.getTime());
        const day = d.getDate();
        d.setMonth(d.getMonth() + months);
        if (d.getDate() < day) d.setDate(0);
        return d;
    }

    /**
     * Next open stub for books entry: same payer, amount 0 (fill in later).
     * One-time / books flow only — does not use weekly/monthly recurring.
     */
    function buildNextOpenForBooks(receivedItem, locationId) {
        const r = normalizeReceivable(receivedItem, locationId);
        if (!r.receiveFrom) return null;
        const base = toDate(r.dueDate) || toDate(r.receivedAt) || new Date();
        const nextDue = addMonths(base, 1);
        nextDue.setHours(12, 0, 0, 0);
        return normalizeReceivable(
            {
                ...defaultReceivable(locationId),
                receiveFrom: r.receiveFrom,
                amount: 0,
                notes: r.notes || "",
                frequency: "none",
                isReceived: false,
                dueDate: firebase.firestore.Timestamp.fromDate(nextDue),
                originalReceivableId: r.originalReceivableId || r.id || null,
            },
            locationId
        );
    }

    window.OplixReceivablesModel = {
        FREQUENCIES,
        defaultReceivable,
        normalizeReceivable,
        isoDateInput,
        dueTimestampFromInput,
        toDate,
        sortReceivables,
        openReceivables,
        receivedReceivablesForMonth,
        openTotal,
        normalizePayerKey,
        hasOpenForPayer,
        hasCarryForwardOpen,
        buildNextOpenForBooks,
    };
})();
