/**
 * Per-facility compliance records (web-first).
 *
 * Firestore: users/{uid}/locations/{locationId}/complianceItems/{id}
 */
(function () {
    const COLLECTION = "complianceItems";

    const CATEGORIES = [
        { id: "tobacco", label: "Tobacco" },
        { id: "alcohol", label: "Alcohol" },
        { id: "food_safety", label: "Food safety" },
        { id: "fda", label: "FDA" },
        { id: "osha", label: "OSHA" },
        { id: "fire_safety", label: "Fire safety" },
        { id: "emergency_exits", label: "Emergency exits" },
        { id: "health_inspection", label: "Health inspection" },
        { id: "age_verification", label: "Age verification" },
        { id: "fuel", label: "Fuel compliance" },
        { id: "incident", label: "Incident reporting" },
        { id: "security", label: "Security" },
        { id: "other", label: "Other" },
    ];

    const STATUSES = [
        { id: "pending", label: "Pending" },
        { id: "scheduled", label: "Scheduled" },
        { id: "pass", label: "Pass" },
        { id: "fail", label: "Fail" },
        { id: "na", label: "N/A" },
    ];

    function defaultItem() {
        return {
            category: "other",
            title: "",
            status: "pending",
            dueDate: "",
            completedDate: "",
            inspector: "",
            notes: "",
            active: true,
        };
    }

    function normalizeItem(raw) {
        const base = defaultItem();
        const item = { ...base, ...(raw || {}) };
        const cat = CATEGORIES.some((c) => c.id === item.category) ? item.category : "other";
        const status = STATUSES.some((s) => s.id === item.status) ? item.status : "pending";
        return {
            ...item,
            category: cat,
            status,
            title: String(item.title || "").trim(),
            dueDate: String(item.dueDate || "").trim(),
            completedDate: String(item.completedDate || "").trim(),
            inspector: String(item.inspector || "").trim(),
            notes: String(item.notes || "").trim(),
        };
    }

    function categoryLabel(categoryId) {
        return CATEGORIES.find((c) => c.id === categoryId)?.label || "Other";
    }

    function statusLabel(statusId) {
        return STATUSES.find((s) => s.id === statusId)?.label || statusId;
    }

    function parseISODate(iso) {
        if (!iso) return null;
        const d = new Date(iso + "T12:00:00");
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function isOverdue(item) {
        if (!item || item.status === "pass" || item.status === "na") return false;
        const due = parseISODate(item.dueDate);
        if (!due) return false;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        due.setHours(0, 0, 0, 0);
        return due < today;
    }

    function needsAttentionCount(items) {
        return (items || []).filter((i) => {
            if (i.active === false) return false;
            if (i.status === "fail") return true;
            if (i.status === "pending" || i.status === "scheduled") return isOverdue(i);
            return false;
        }).length;
    }

    function sortItems(list) {
        const rank = (item) => {
            if (item.status === "fail") return 0;
            if (isOverdue(item)) return 1;
            if (item.status === "pending") return 2;
            if (item.status === "scheduled") return 3;
            return 4;
        };
        return [...(list || [])].sort((a, b) => {
            const ra = rank(a);
            const rb = rank(b);
            if (ra !== rb) return ra - rb;
            const da = parseISODate(a.dueDate)?.getTime() || 0;
            const db = parseISODate(b.dueDate)?.getTime() || 0;
            if (da && db) return da - db;
            return (a.title || categoryLabel(a.category)).localeCompare(
                b.title || categoryLabel(b.category)
            );
        });
    }

    window.OplixComplianceModel = {
        COLLECTION,
        CATEGORIES,
        STATUSES,
        defaultItem,
        normalizeItem,
        categoryLabel,
        statusLabel,
        isOverdue,
        needsAttentionCount,
        sortItems,
    };
})();
