/**
 * Task helpers — categories, completions, and scheduling.
 */
(function () {
    const TP = () => window.OplixTaskProgress;

    const CATEGORIES = {
        recurring: {
            id: "recurring",
            title: "Recurring",
            subtitle: "Daily, weekly, or monthly tasks that auto-reset each cycle.",
            icon: "↻",
            cardClass: "loc-category-card--green",
        },
        corrective: {
            id: "corrective",
            title: "Corrective",
            subtitle: "Ad-hoc one-time tasks for fixes and audit findings.",
            icon: "!",
            cardClass: "loc-category-card--orange",
        },
    };

    const FREQ_LABELS = {
        one_time: "One-time",
        daily: "Daily",
        weekly: "Weekly",
        monthly: "Monthly",
    };

    const FREQ_SHORT = {
        one_time: "Once",
        daily: "Daily",
        weekly: "Weekly",
        monthly: "Monthly",
    };

    const RECURRING_FREQUENCIES = ["daily", "weekly", "monthly"];

    function defaultTask(locationId) {
        return {
            id: "",
            description: "",
            assignedEmployeeIds: [],
            locationId: locationId || "",
            assignedLocationIds: locationId ? [locationId] : [],
            employeeCompletions: {},
            frequency: "one_time",
            crossLocationGroupId: null,
            completionHistory: [],
        };
    }

    function normalizeTask(raw, locationId) {
        const base = defaultTask(locationId);
        const t = { ...base, ...(raw || {}) };
        const freq = t.frequency || "one_time";
        const frequency = FREQ_LABELS[freq] ? freq : "one_time";
        const assignedEmployeeIds = Array.isArray(t.assignedEmployeeIds)
            ? t.assignedEmployeeIds.map(String).filter(Boolean)
            : [];
        const locId = locationId || t.locationId || "";
        return {
            id: String(t.id || "").trim(),
            description: String(t.description || "").trim(),
            assignedEmployeeIds,
            locationId: locId,
            assignedLocationIds: locId
                ? Array.from(new Set([...(t.assignedLocationIds || []), locId]))
                : t.assignedLocationIds || [],
            employeeCompletions: t.employeeCompletions || {},
            frequency,
            crossLocationGroupId: t.crossLocationGroupId || null,
            completionHistory: Array.isArray(t.completionHistory) ? t.completionHistory : [],
            createdAt: t.createdAt || null,
        };
    }

    function buildNewTask({ description, locationId, assignedEmployeeIds, frequency, id }) {
        return normalizeTask(
            {
                id,
                description,
                assignedEmployeeIds,
                frequency,
            },
            locationId
        );
    }

    /** Preserve completions and createdAt when editing. */
    function mergeTaskUpdate(existing, updates, locationId) {
        return normalizeTask(
            {
                ...existing,
                description: updates.description,
                assignedEmployeeIds: updates.assignedEmployeeIds,
                frequency: updates.frequency,
                employeeCompletions: existing?.employeeCompletions || {},
                completionHistory: existing?.completionHistory || [],
                crossLocationGroupId: existing?.crossLocationGroupId || null,
                createdAt: existing?.createdAt || null,
            },
            locationId
        );
    }

    const ALL_FREQUENCIES = ["one_time", "daily", "weekly", "monthly"];

    function defaultFrequencyForCategory(categoryId) {
        return categoryId === "recurring" ? "daily" : "one_time";
    }

    function allowedFrequencies(categoryId) {
        return categoryId === "recurring" ? RECURRING_FREQUENCIES : ["one_time"];
    }

    function isRecurring(task) {
        const f = task?.frequency || "one_time";
        return f !== "one_time";
    }

    function inCategory(task, categoryId) {
        if (categoryId === "recurring") return isRecurring(task);
        if (categoryId === "corrective") return !isRecurring(task);
        return false;
    }

    function frequencyLabel(task) {
        return FREQ_LABELS[task?.frequency || "one_time"] || "One-time";
    }

    function frequencyShort(task) {
        return FREQ_SHORT[task?.frequency || "one_time"] || "Once";
    }

    function assigneeText(task, nameById) {
        const ids = task?.assignedEmployeeIds || [];
        if (!ids.length) return "Unassigned";
        const names = ids.map((id) => nameById[id]).filter(Boolean);
        if (!names.length) return `${ids.length} assigned`;
        return names.join(", ");
    }

    function completionStats(task, now) {
        const assigned = task?.assignedEmployeeIds || [];
        const assignedCount = assigned.length;
        const completedCount = assigned.filter((id) =>
            TP().isCompletedBy(task, id, now)
        ).length;
        const isFullyComplete = assignedCount > 0 && completedCount === assignedCount;
        const isPartiallyComplete = completedCount > 0 && completedCount < assignedCount;
        return {
            assignedCount,
            completedCount,
            isFullyComplete,
            isPartiallyComplete,
            isUnassigned: assignedCount === 0,
        };
    }

    function categoryStats(tasks, now) {
        const total = tasks.length;
        const done = tasks.filter((t) => {
            const s = completionStats(t, now);
            return s.assignedCount > 0 && s.isFullyComplete;
        }).length;
        return { total, done, pending: total - done };
    }

    function countsAsCompleted(completion) {
        return completion?.isApproved !== false;
    }

    function currentCycleCompletions(task, now) {
        now = now || new Date();
        const raw = task?.employeeCompletions || {};
        if (!isRecurring(task)) return { ...raw };
        const cycleStart = TP().getTaskCycleStart(task, now);
        const out = {};
        Object.entries(raw).forEach(([id, c]) => {
            const ts = TP().toDate(c.timestamp);
            if (ts && ts >= cycleStart) out[id] = c;
        });
        return out;
    }

    function cyclePeriodLabel(task, now) {
        now = now || new Date();
        const freq = task?.frequency || "one_time";
        if (!isRecurring(task)) return null;
        const fmt = (d) =>
            d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
        if (freq === "daily") return `Today, ${fmt(now)}`;
        const start = TP().getTaskCycleStart(task, now);
        if (freq === "weekly") return `This week (since ${fmt(start)})`;
        if (freq === "monthly") return `This month (since ${fmt(start)})`;
        return null;
    }

    function rowStatus(task, now) {
        const s = completionStats(task, now);
        if (s.isUnassigned) return "unassigned";
        if (s.isFullyComplete) return "done";
        if (s.isPartiallyComplete) return "partial";
        return "pending";
    }

    function statusLabel(task, now) {
        const s = rowStatus(task, now);
        const stats = completionStats(task, now);
        if (s === "unassigned") return "UNASSIGNED";
        if (s === "done") return "DONE";
        if (s === "partial") return `${stats.completedCount}/${stats.assignedCount}`;
        return "PENDING";
    }

    function applyReview(task, { employeeId, completionTimestamp, approved, note, reviewerId }) {
        const updated = normalizeTask({ ...task }, task.locationId);
        const stamp = (c) => {
            const out = {
                ...c,
                isApproved: approved,
                reviewedBy: reviewerId,
                // Firestore Timestamp — ISO strings break iOS Codable decoding.
                reviewedAt: firebase.firestore.Timestamp.now(),
            };
            if (approved) delete out.disapprovalNote;
            else if (note) out.disapprovalNote = note;
            return out;
        };

        if (completionTimestamp) {
            const targetTs = TP().toDate(completionTimestamp)?.getTime();
            const current = updated.employeeCompletions?.[employeeId];
            if (current && Math.abs(TP().toDate(current.timestamp)?.getTime() - targetTs) < 1000) {
                updated.employeeCompletions = {
                    ...updated.employeeCompletions,
                    [employeeId]: stamp(current),
                };
                return updated;
            }
            const hist = [...(updated.completionHistory || [])];
            const idx = hist.findIndex(
                (c) =>
                    c.employeeId === employeeId &&
                    Math.abs(TP().toDate(c.timestamp)?.getTime() - targetTs) < 1000
            );
            if (idx >= 0) {
                hist[idx] = stamp(hist[idx]);
                updated.completionHistory = hist;
                return updated;
            }
            return null;
        }

        const current = updated.employeeCompletions?.[employeeId];
        if (!current) return null;
        updated.employeeCompletions = {
            ...updated.employeeCompletions,
            [employeeId]: stamp(current),
        };
        return updated;
    }

    window.OplixTasksModel = {
        CATEGORIES,
        RECURRING_FREQUENCIES,
        isRecurring,
        inCategory,
        frequencyLabel,
        frequencyShort,
        assigneeText,
        completionStats,
        categoryStats,
        countsAsCompleted,
        currentCycleCompletions,
        cyclePeriodLabel,
        rowStatus,
        statusLabel,
        applyReview,
        defaultTask,
        normalizeTask,
        buildNewTask,
        mergeTaskUpdate,
        defaultFrequencyForCategory,
        allowedFrequencies,
        ALL_FREQUENCIES,
    };
})();
