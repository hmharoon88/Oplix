/**
 * Per-facility licenses, registrations, permits, and renewals (web-first).
 *
 * Firestore: users/{uid}/locations/{locationId}/complianceItems/{id}
 */
(function () {
    const COLLECTION = "complianceItems";

    const EXPIRING_SOON_DAYS = 60;
    const ATTENTION_EXPIRING_DAYS = 60;

    const RECORD_TYPES = [
        { id: "license", label: "License" },
        { id: "registration", label: "Registration" },
        { id: "permit", label: "Permit" },
        { id: "certification", label: "Certification" },
        { id: "insurance", label: "Insurance" },
        { id: "other", label: "Other" },
    ];

    const CATEGORIES = [
        { id: "business", label: "Business / operating" },
        { id: "tobacco", label: "Tobacco" },
        { id: "alcohol", label: "Alcohol" },
        { id: "lottery", label: "Lottery" },
        { id: "fuel", label: "Fuel / petroleum" },
        { id: "food_safety", label: "Food / health" },
        { id: "fire_safety", label: "Fire / safety" },
        { id: "signage", label: "Signage / zoning" },
        { id: "insurance", label: "Insurance" },
        { id: "tax", label: "Tax registration" },
        { id: "employment", label: "Labor / OSHA" },
        { id: "vehicle", label: "Vehicle / fleet" },
        { id: "security", label: "Security / alarm" },
        { id: "other", label: "Other" },
    ];

    const STATUSES = [
        { id: "active", label: "Active" },
        { id: "pending_renewal", label: "Pending renewal" },
        { id: "expired", label: "Expired" },
        { id: "not_applicable", label: "N/A" },
    ];

    const LEGACY_STATUS_MAP = {
        pass: "active",
        fail: "expired",
        pending: "pending_renewal",
        scheduled: "pending_renewal",
        na: "not_applicable",
    };

    const LEGACY_CATEGORY_IDS = new Set([
        "tobacco",
        "alcohol",
        "food_safety",
        "fda",
        "osha",
        "fire_safety",
        "emergency_exits",
        "health_inspection",
        "age_verification",
        "fuel",
        "incident",
        "security",
        "other",
    ]);

    function defaultItem() {
        return {
            recordType: "license",
            category: "business",
            title: "",
            identifier: "",
            issuingAuthority: "",
            issueDate: "",
            expiryDate: "",
            renewalDueDate: "",
            lastRenewedDate: "",
            status: "active",
            notes: "",
            attachmentUrl: "",
            attachmentFileName: "",
            attachmentFileType: "",
            active: true,
        };
    }

    function isImageAttachment(fileType, fileName) {
        const t = String(fileType || "").toLowerCase();
        if (t.startsWith("image/")) return true;
        const ext = String(fileName || "")
            .split(".")
            .pop()
            .toLowerCase();
        return ["jpg", "jpeg", "png", "gif", "webp", "heic"].includes(ext);
    }

    function attachmentLabel(item) {
        if (item?.attachmentFileName) return item.attachmentFileName;
        if (item?.attachmentUrl) return "Attached file";
        return "";
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

    function migrateLegacyFields(raw) {
        const item = { ...(raw || {}) };
        if (!item.expiryDate && item.dueDate) item.expiryDate = String(item.dueDate).trim();
        if (!item.issuingAuthority && item.inspector) {
            item.issuingAuthority = String(item.inspector).trim();
        }
        if (!item.lastRenewedDate && item.completedDate) {
            item.lastRenewedDate = String(item.completedDate).trim();
        }
        if (!item.identifier && item.licenseNumber) {
            item.identifier = String(item.licenseNumber).trim();
        }
        if (LEGACY_STATUS_MAP[item.status]) item.status = LEGACY_STATUS_MAP[item.status];
        if (item.category && !CATEGORIES.some((c) => c.id === item.category)) {
            if (LEGACY_CATEGORY_IDS.has(item.category)) {
                const map = {
                    fda: "food_safety",
                    osha: "employment",
                    emergency_exits: "fire_safety",
                    health_inspection: "food_safety",
                    age_verification: "tobacco",
                    incident: "other",
                };
                item.category = map[item.category] || item.category;
            } else {
                item.category = "other";
            }
        }
        return item;
    }

    function normalizeItem(raw) {
        const base = defaultItem();
        const item = migrateLegacyFields({ ...base, ...(raw || {}) });
        const recordType = RECORD_TYPES.some((r) => r.id === item.recordType)
            ? item.recordType
            : "license";
        const category = CATEGORIES.some((c) => c.id === item.category) ? item.category : "other";
        const status = STATUSES.some((s) => s.id === item.status) ? item.status : "active";
        return {
            ...item,
            recordType,
            category,
            status,
            title: String(item.title || "").trim(),
            identifier: String(item.identifier || "").trim(),
            issuingAuthority: String(item.issuingAuthority || "").trim(),
            issueDate: String(item.issueDate || "").slice(0, 10),
            expiryDate: String(item.expiryDate || "").slice(0, 10),
            renewalDueDate: String(item.renewalDueDate || "").slice(0, 10),
            lastRenewedDate: String(item.lastRenewedDate || "").slice(0, 10),
            notes: String(item.notes || "").trim(),
            attachmentUrl: String(item.attachmentUrl || "").trim(),
            attachmentFileName: String(item.attachmentFileName || "").trim(),
            attachmentFileType: String(item.attachmentFileType || "").trim(),
        };
    }

    function recordTypeLabel(recordTypeId) {
        return RECORD_TYPES.find((r) => r.id === recordTypeId)?.label || "License";
    }

    function categoryLabel(categoryId) {
        return CATEGORIES.find((c) => c.id === categoryId)?.label || "Other";
    }

    function statusLabel(statusId) {
        return STATUSES.find((s) => s.id === statusId)?.label || statusId;
    }

    function daysUntilExpiry(item) {
        const exp = parseISODate(item?.expiryDate);
        if (!exp) return null;
        return daysBetween(todayAtNoon(), exp);
    }

    function isExpired(item) {
        if (!item || item.status === "not_applicable") return false;
        if (item.status === "expired") return true;
        const days = daysUntilExpiry(item);
        return days != null && days < 0;
    }

    function isExpiringSoon(item, withinDays) {
        if (!item || item.status === "not_applicable" || item.status === "expired") return false;
        const days = daysUntilExpiry(item);
        if (days == null) return false;
        const window = withinDays == null ? EXPIRING_SOON_DAYS : withinDays;
        return days >= 0 && days <= window;
    }

    function isRenewalOverdue(item) {
        if (!item || item.status !== "pending_renewal") return false;
        const due = parseISODate(item.renewalDueDate || item.expiryDate);
        if (!due) return false;
        return daysBetween(todayAtNoon(), due) < 0;
    }

    function displayStatus(item) {
        if (!item || item.status === "not_applicable") {
            return { id: "not_applicable", label: "N/A", className: "comp-status--na" };
        }
        if (item.status === "pending_renewal") {
            const overdue = isRenewalOverdue(item);
            return {
                id: "pending_renewal",
                label: overdue ? "Renewal overdue" : "Pending renewal",
                className: overdue ? "comp-status--expired" : "comp-status--pending",
            };
        }
        if (isExpired(item)) {
            return { id: "expired", label: "Expired", className: "comp-status--expired" };
        }
        if (isExpiringSoon(item, EXPIRING_SOON_DAYS)) {
            return { id: "expiring_soon", label: "Expiring soon", className: "comp-status--expiring" };
        }
        return { id: "active", label: "Active", className: "comp-status--active" };
    }

    function expiryHint(item) {
        const days = daysUntilExpiry(item);
        if (days == null) return "";
        if (days < 0) return `Expired ${Math.abs(days)} day${Math.abs(days) === 1 ? "" : "s"} ago`;
        if (days === 0) return "Expires today";
        if (days === 1) return "Expires tomorrow";
        if (days <= EXPIRING_SOON_DAYS) return `${days} days left`;
        return "";
    }

    function needsAttention(item) {
        if (!item || item.active === false) return false;
        const d = displayStatus(item);
        if (d.id === "expired" || d.id === "expiring_soon") return true;
        if (d.id === "pending_renewal" && isRenewalOverdue(item)) return true;
        return false;
    }

    function needsAttentionCount(items) {
        return (items || []).filter(needsAttention).length;
    }

    function summaryCounts(items) {
        const list = (items || []).filter((i) => i.active !== false);
        let active = 0;
        let expiring = 0;
        let expired = 0;
        let pending = 0;
        list.forEach((item) => {
            const d = displayStatus(item);
            if (d.id === "expired") expired += 1;
            else if (d.id === "expiring_soon") expiring += 1;
            else if (d.id === "pending_renewal") pending += 1;
            else if (d.id === "active") active += 1;
        });
        return { total: list.length, active, expiring, expired, pending };
    }

    function sortItems(list) {
        const rank = (item) => {
            const d = displayStatus(item);
            if (d.id === "expired") return 0;
            if (d.id === "pending_renewal" && isRenewalOverdue(item)) return 1;
            if (d.id === "expiring_soon") return 2;
            if (d.id === "pending_renewal") return 3;
            return 4;
        };
        return [...(list || [])].sort((a, b) => {
            const ra = rank(a);
            const rb = rank(b);
            if (ra !== rb) return ra - rb;
            const da = daysUntilExpiry(a);
            const db = daysUntilExpiry(b);
            if (da != null && db != null) return da - db;
            if (da != null) return -1;
            if (db != null) return 1;
            const titleA = a.title || categoryLabel(a.category);
            const titleB = b.title || categoryLabel(b.category);
            return titleA.localeCompare(titleB);
        });
    }

    /** @deprecated use isExpired — kept for any external callers */
    function isOverdue(item) {
        return isExpired(item) || isRenewalOverdue(item);
    }

    window.OplixComplianceModel = {
        COLLECTION,
        RECORD_TYPES,
        CATEGORIES,
        STATUSES,
        EXPIRING_SOON_DAYS,
        ATTENTION_EXPIRING_DAYS,
        defaultItem,
        normalizeItem,
        recordTypeLabel,
        categoryLabel,
        statusLabel,
        parseISODate,
        daysUntilExpiry,
        expiryHint,
        displayStatus,
        isExpired,
        isExpiringSoon,
        isRenewalOverdue,
        isOverdue,
        needsAttention,
        needsAttentionCount,
        summaryCounts,
        sortItems,
        isImageAttachment,
        attachmentLabel,
    };
})();
