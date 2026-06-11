/**
 * Home layout prefs — localStorage per user.
 */
(function () {
    const DEFAULT_ORDER = [
        "actionCenter",
        "orgTodos",
        "thisWeek",
        "shortcuts",
        "monthToDate",
        "lotteryToday",
    ];

    const SECTIONS = {
        orgTodos: {
            id: "orgTodos",
            title: "To-Do",
            subtitle: "Your personal checklist — not tied to a facility or employee",
        },
        actionCenter: {
            id: "actionCenter",
            title: "Needs Attention",
            subtitle: "Cash variances, overdue items, missing data",
        },
        lotteryToday: {
            id: "lotteryToday",
            title: "Lottery Today",
            subtitle: "Per-location lottery over/short for today",
        },
        thisWeek: {
            id: "thisWeek",
            title: "This Week",
            subtitle: "Receivables and payables due in next 7 days",
        },
        shortcuts: {
            id: "shortcuts",
            title: "Shortcuts",
            subtitle: "Quick links to payroll, tasks, reports, and more",
        },
        monthToDate: {
            id: "monthToDate",
            title: "Month to Date",
            subtitle: "Per-location revenue, payroll, and expenses",
        },
    };

    const ALERT_CATEGORIES = {
        forgotClockOut: {
            id: "forgotClockOut",
            title: "Forgot to clock out",
            subtitle: "Active shifts older than 12 hours",
        },
        missingRegister: {
            id: "missingRegister",
            title: "Register data missing",
            subtitle: "Closed shifts with no register data (last 7 days)",
        },
        cashVariance: {
            id: "cashVariance",
            title: "Cash over / short",
            subtitle: "Register over/short ≥ $5 in last 7 days",
        },
        lotteryNotClosed: {
            id: "lotteryNotClosed",
            title: "Lottery not closed",
            subtitle: "Lottery active but no submission yesterday",
        },
        lotteryVariance: {
            id: "lotteryVariance",
            title: "Lottery over / short",
            subtitle: "Lottery shift over/short ≥ $5 in last 7 days",
        },
        disapprovedTasks: {
            id: "disapprovedTasks",
            title: "Tasks need rework",
            subtitle: "Tasks the manager kicked back to redo",
        },
        overduePayables: {
            id: "overduePayables",
            title: "Overdue payables",
            subtitle: "Unpaid payables past due date",
        },
        expiringDocs: {
            id: "expiringDocs",
            title: "Expiring documents",
            subtitle: "Documents expiring within 30 days",
        },
        scheduleGaps: {
            id: "scheduleGaps",
            title: "Schedule gaps",
            subtitle: "Employees with no shifts this week",
        },
    };

    function storageKey(userId) {
        return `oplix.homeLayout.${userId}`;
    }

    function defaultPrefs() {
        return { order: [...DEFAULT_ORDER], hidden: [], hiddenAlertCategories: [] };
    }

    function spliceMissing(order) {
        const result = order.filter((id) => SECTIONS[id]);
        DEFAULT_ORDER.forEach((id) => {
            if (result.includes(id)) return;
            const defaultIdx = DEFAULT_ORDER.indexOf(id);
            let insertAt = result.length;
            for (let i = 0; i < result.length; i++) {
                const pos = DEFAULT_ORDER.indexOf(result[i]);
                if (pos !== -1 && pos > defaultIdx) {
                    insertAt = i;
                    break;
                }
            }
            result.splice(insertAt, 0, id);
        });
        return result;
    }

    function normalizeHomeOrder(order) {
        let result = (order || []).filter((id) => SECTIONS[id] && id !== "today");
        result = spliceMissing(result);
        const acIdx = result.indexOf("actionCenter");
        const otIdx = result.indexOf("orgTodos");
        if (otIdx >= 0) {
            result.splice(otIdx, 1);
        }
        const insertAt = acIdx >= 0 ? acIdx + 1 : 0;
        result.splice(insertAt, 0, "orgTodos");
        const lotIdx = result.indexOf("lotteryToday");
        if (lotIdx >= 0) {
            result.splice(lotIdx, 1);
            result.push("lotteryToday");
        }
        return result;
    }

    function load(userId) {
        if (!userId) return defaultPrefs();
        try {
            const raw = localStorage.getItem(storageKey(userId));
            if (!raw) return defaultPrefs();
            const parsed = JSON.parse(raw);
            const order = Array.isArray(parsed.order) ? parsed.order : [...DEFAULT_ORDER];
            const hidden = Array.isArray(parsed.hidden) ? parsed.hidden : [];
            const hiddenAlertCategories = Array.isArray(parsed.hiddenAlertCategories)
                ? parsed.hiddenAlertCategories
                : [];
            const normalizedHidden = hidden.filter((id) => id !== "today");
            const normalizedOrder = normalizeHomeOrder(order);
            const prefs = {
                order: normalizedOrder,
                hidden: normalizedHidden,
                hiddenAlertCategories,
            };
            if (
                JSON.stringify(normalizedOrder) !== JSON.stringify(order) ||
                normalizedHidden.length !== hidden.length
            ) {
                save(userId, prefs);
            }
            return prefs;
        } catch {
            return defaultPrefs();
        }
    }

    function save(userId, prefs) {
        localStorage.setItem(storageKey(userId), JSON.stringify(prefs));
    }

    function visibleSectionsInOrder(prefs) {
        const hidden = new Set(prefs.hidden || []);
        const seen = new Set();
        const out = [];
        const canonical = normalizeHomeOrder(prefs.order || DEFAULT_ORDER);
        canonical.forEach((id) => {
            if (!hidden.has(id) && SECTIONS[id] && !seen.has(id)) {
                seen.add(id);
                out.push(id);
            }
        });
        return out;
    }

    function toggleSection(userId, sectionId) {
        const prefs = load(userId);
        const hidden = new Set(prefs.hidden);
        if (hidden.has(sectionId)) hidden.delete(sectionId);
        else hidden.add(sectionId);
        prefs.hidden = [...hidden];
        save(userId, prefs);
        return prefs;
    }

    function moveSection(userId, sectionId, direction) {
        const prefs = load(userId);
        const order = [...prefs.order];
        const idx = order.indexOf(sectionId);
        if (idx < 0) return prefs;
        const swap = direction === "up" ? idx - 1 : idx + 1;
        if (swap < 0 || swap >= order.length) return prefs;
        [order[idx], order[swap]] = [order[swap], order[idx]];
        prefs.order = order;
        save(userId, prefs);
        return prefs;
    }

    function reset(userId) {
        const prefs = defaultPrefs();
        save(userId, prefs);
        return prefs;
    }

    function toggleAlertCategory(userId, categoryId) {
        const prefs = load(userId);
        const hidden = new Set(prefs.hiddenAlertCategories || []);
        if (hidden.has(categoryId)) hidden.delete(categoryId);
        else hidden.add(categoryId);
        prefs.hiddenAlertCategories = [...hidden];
        save(userId, prefs);
        return prefs;
    }

    function resetAlertCategories(userId) {
        const prefs = load(userId);
        prefs.hiddenAlertCategories = [];
        save(userId, prefs);
        return prefs;
    }

    function categoryForAlert(alert) {
        const id = String(alert?.id || "");
        if (id.startsWith("clockout_")) return "forgotClockOut";
        if (id.startsWith("noregister_")) return "missingRegister";
        if (id.startsWith("regvar_")) return "cashVariance";
        if (id.startsWith("lotteryclose_")) return "lotteryNotClosed";
        if (id.startsWith("lotvar_")) return "lotteryVariance";
        if (id.startsWith("disapp_")) return "disapprovedTasks";
        if (id.startsWith("payable_")) return "overduePayables";
        if (id.startsWith("doc_")) return "expiringDocs";
        if (id.startsWith("schedgap_")) return "scheduleGaps";
        return alert.category || null;
    }

    function filterAlerts(alerts, prefs) {
        const hidden = new Set(prefs?.hiddenAlertCategories || []);
        return (alerts || []).filter((a) => {
            const cat = categoryForAlert(a);
            return !cat || !hidden.has(cat);
        });
    }

    window.OplixHomeLayoutStore = {
        SECTIONS,
        ALERT_CATEGORIES,
        DEFAULT_ORDER,
        load,
        save,
        visibleSectionsInOrder,
        toggleSection,
        moveSection,
        reset,
        toggleAlertCategory,
        resetAlertCategories,
        categoryForAlert,
        filterAlerts,
    };
})();
