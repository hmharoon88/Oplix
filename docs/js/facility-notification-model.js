/**
 * Per-facility notification settings — enable/disable alert types and lead times.
 * Stored on the location document as `notificationSettings`.
 */
(function () {
    const NOTIFICATION_TYPES = [
        {
            id: "clock_out",
            label: "Employee forgot to clock out",
            group: "Shifts & staffing",
            hasLeadDays: false,
        },
        {
            id: "missing_register",
            label: "Register data missing after shift",
            group: "Shifts & staffing",
            hasLeadDays: false,
        },
        {
            id: "schedule_gaps",
            label: "Employee with no shifts this week",
            group: "Shifts & staffing",
            hasLeadDays: false,
        },
        {
            id: "register_variance",
            label: "Register over / short",
            group: "Sales & lottery",
            hasLeadDays: false,
        },
        {
            id: "lottery_not_closed",
            label: "Lottery not closed yesterday",
            group: "Sales & lottery",
            hasLeadDays: false,
        },
        {
            id: "lottery_variance",
            label: "Lottery over / short",
            group: "Sales & lottery",
            hasLeadDays: false,
        },
        {
            id: "payables_overdue",
            label: "Overdue payables",
            group: "Finance",
            hasLeadDays: false,
        },
        {
            id: "receivables_overdue",
            label: "Overdue receivables",
            group: "Finance",
            hasLeadDays: false,
        },
        {
            id: "document_expiry",
            label: "Document expiring soon",
            group: "Compliance",
            hasLeadDays: true,
            defaultLeadDays: 30,
        },
        {
            id: "profile_expiry",
            label: "Lease & license expiry",
            group: "Compliance",
            hasLeadDays: true,
            defaultLeadDays: 60,
        },
        {
            id: "compliance_expiry",
            label: "Compliance licenses & permits",
            group: "Compliance",
            hasLeadDays: true,
            defaultLeadDays: 60,
        },
        {
            id: "tasks_rework",
            label: "Tasks need rework",
            group: "Operations",
            hasLeadDays: false,
        },
    ];

    const TYPE_BY_ID = Object.fromEntries(NOTIFICATION_TYPES.map((t) => [t.id, t]));

    function defaultNotificationItem(type) {
        const item = { enabled: true };
        if (type.hasLeadDays) {
            item.leadDays = type.defaultLeadDays;
        }
        return item;
    }

    function defaultNotificationSettings() {
        const items = {};
        NOTIFICATION_TYPES.forEach((type) => {
            items[type.id] = defaultNotificationItem(type);
        });
        return { version: 1, items };
    }

    function normalizeNotificationItem(typeId, raw) {
        const type = TYPE_BY_ID[typeId];
        if (!type) return { enabled: true };
        const row = raw && typeof raw === "object" ? raw : {};
        const item = { enabled: row.enabled !== false };
        if (type.hasLeadDays) {
            const n = parseInt(row.leadDays, 10);
            item.leadDays = Number.isFinite(n) && n >= 0 ? n : type.defaultLeadDays;
        }
        return item;
    }

    function normalizeNotificationSettings(raw) {
        const base = defaultNotificationSettings();
        const saved = raw && typeof raw === "object" ? raw : {};
        const savedItems = saved.items && typeof saved.items === "object" ? saved.items : {};
        NOTIFICATION_TYPES.forEach((type) => {
            base.items[type.id] = normalizeNotificationItem(type.id, savedItems[type.id]);
        });
        return base;
    }

    function isEnabled(settings, typeId) {
        const item = normalizeNotificationSettings(settings).items[typeId];
        return item?.enabled !== false;
    }

    function leadDays(settings, typeId) {
        const type = TYPE_BY_ID[typeId];
        const item = normalizeNotificationSettings(settings).items[typeId];
        if (!type?.hasLeadDays) return null;
        return item?.leadDays ?? type.defaultLeadDays;
    }

    window.OplixFacilityNotificationModel = {
        NOTIFICATION_TYPES,
        defaultNotificationSettings,
        normalizeNotificationSettings,
        isEnabled,
        leadDays,
    };
})();
