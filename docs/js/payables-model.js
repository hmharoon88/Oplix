/**
 * Location payables — same Firestore shape as iOS (users/.../locations/.../payables).
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

    function defaultPayable(locationId) {
        return {
            locationId: locationId || "",
            payTo: "",
            amount: 0,
            dueDate: null,
            notes: "",
            frequency: "none",
            isPaid: false,
            paidAt: null,
            originalPayableId: null,
        };
    }

    function normalizePayable(raw, locationId) {
        const base = defaultPayable(locationId);
        const p = { ...base, ...(raw || {}) };
        const freq = FREQUENCIES.some((f) => f.id === p.frequency) ? p.frequency : "none";
        return {
            ...p,
            id: p.id || "",
            locationId: p.locationId || locationId || "",
            payTo: String(p.payTo || "").trim(),
            amount: parseFloat(p.amount) || 0,
            notes: p.notes ? String(p.notes) : "",
            frequency: freq,
            isPaid: !!p.isPaid,
            dueDate: p.dueDate || null,
            paidAt: p.paidAt || null,
            createdAt: p.createdAt || null,
            originalPayableId: p.originalPayableId || null,
        };
    }

    function monthBounds(monthId) {
        const [y, m] = monthId.split("-").map(Number);
        const start = new Date(y, m - 1, 1);
        const end = new Date(y, m, 0, 23, 59, 59, 999);
        return { start, end };
    }

    function paidInMonth(p, monthId) {
        const paid = toDate(p.paidAt);
        if (!paid) return false;
        const { start, end } = monthBounds(monthId);
        return paid >= start && paid <= end;
    }

    function dueInMonth(p, monthId) {
        const due = toDate(p.dueDate);
        if (!due) return false;
        const { start, end } = monthBounds(monthId);
        return due >= start && due <= end;
    }

    function sortPayables(list) {
        return [...(list || [])].sort((a, b) => {
            if (a.isPaid !== b.isPaid) return a.isPaid ? 1 : -1;
            const da = toDate(a.dueDate)?.getTime() || 0;
            const db = toDate(b.dueDate)?.getTime() || 0;
            if (da && db) return da - db;
            if (da) return -1;
            if (db) return 1;
            return (a.payTo || "").localeCompare(b.payTo || "");
        });
    }

    function openPayablesForMonth(list, monthId) {
        return sortPayables(list).filter((p) => !p.isPaid);
    }

    function paidPayablesForMonth(list, monthId) {
        return sortPayables(list).filter((p) => p.isPaid && paidInMonth(p, monthId));
    }

    function openTotal(list) {
        return openPayablesForMonth(list).reduce((s, p) => s + (p.amount || 0), 0);
    }

    window.OplixPayablesModel = {
        FREQUENCIES,
        defaultPayable,
        normalizePayable,
        isoDateInput,
        dueTimestampFromInput,
        toDate,
        openPayablesForMonth,
        paidPayablesForMonth,
        openTotal,
        dueInMonth,
    };
})();
