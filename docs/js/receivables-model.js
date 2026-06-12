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
        };
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
    };
})();
