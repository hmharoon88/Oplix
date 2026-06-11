/**
 * Organization-level to-dos — manager home checklist, not tied to any facility or employee.
 *
 * Firestore: users/{uid}/orgTodos/{id}
 */
(function () {
    const COLLECTION = "orgTodos";

    function defaultItem() {
        return {
            title: "",
            notes: "",
            dueDate: "",
            isCompleted: false,
            completedAt: null,
        };
    }

    function parseISODate(iso) {
        if (!iso) return null;
        const d = new Date(String(iso).slice(0, 10) + "T12:00:00");
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function todayAtNoon() {
        const t = new Date();
        t.setHours(12, 0, 0, 0);
        return t;
    }

    function daysBetween(from, to) {
        const ms = 24 * 60 * 60 * 1000;
        return Math.round((to.getTime() - from.getTime()) / ms);
    }

    function normalizeItem(raw) {
        const base = defaultItem();
        const item = { ...base, ...(raw || {}) };
        return {
            id: item.id || "",
            title: String(item.title || "").trim(),
            notes: String(item.notes || "").trim(),
            dueDate: item.dueDate ? String(item.dueDate).slice(0, 10) : "",
            isCompleted: !!item.isCompleted,
            completedAt: item.completedAt || null,
            createdAt: item.createdAt || null,
            updatedAt: item.updatedAt || null,
        };
    }

    function daysUntilDue(item) {
        const due = parseISODate(item?.dueDate);
        if (!due) return null;
        return daysBetween(todayAtNoon(), due);
    }

    function isOverdue(item) {
        if (!item || item.isCompleted) return false;
        const days = daysUntilDue(item);
        return days != null && days < 0;
    }

    function isDueToday(item) {
        if (!item || item.isCompleted) return false;
        return daysUntilDue(item) === 0;
    }

    function dueHint(item) {
        if (!item?.dueDate || item.isCompleted) return "";
        const days = daysUntilDue(item);
        if (days == null) return "";
        if (days < 0) return `${Math.abs(days)} day${Math.abs(days) === 1 ? "" : "s"} overdue`;
        if (days === 0) return "Due today";
        if (days === 1) return "Due tomorrow";
        if (days <= 7) return `Due in ${days} days`;
        return "";
    }

    function sortItems(list) {
        return [...(list || [])].sort((a, b) => {
            if (a.isCompleted !== b.isCompleted) return a.isCompleted ? 1 : -1;
            const overdueA = isOverdue(a) ? 0 : 1;
            const overdueB = isOverdue(b) ? 0 : 1;
            if (overdueA !== overdueB) return overdueA - overdueB;
            const da = daysUntilDue(a);
            const db = daysUntilDue(b);
            if (da != null && db != null && da !== db) return da - db;
            if (da != null && db == null) return -1;
            if (da == null && db != null) return 1;
            return (a.title || "").localeCompare(b.title || "");
        });
    }

    function openCount(list) {
        return (list || []).filter((i) => !i.isCompleted).length;
    }

    window.OplixOrgTodosModel = {
        COLLECTION,
        defaultItem,
        normalizeItem,
        sortItems,
        openCount,
        parseISODate,
        daysUntilDue,
        isOverdue,
        isDueToday,
        dueHint,
    };
})();
