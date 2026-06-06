/**
 * Task completion scoring — mirrors Oplix/Models/TaskProgress.swift
 */
(function () {
    function toDate(value) {
        if (!value) return null;
        if (value instanceof Date) return value;
        if (typeof value.toDate === "function") return value.toDate();
        if (typeof value === "number") return new Date(value);
        if (typeof value === "string") return new Date(value);
        return null;
    }

    function startOfDay(d) {
        const x = new Date(d);
        x.setHours(0, 0, 0, 0);
        return x;
    }

    function getTaskCycleStart(task, now) {
        const freq = task.frequency || "one_time";
        if (freq === "one_time") return new Date(0);
        if (freq === "daily") return startOfDay(now);
        if (freq === "weekly") {
            const d = new Date(now);
            const day = d.getDay();
            const diff = day === 0 ? 6 : day - 1;
            d.setDate(d.getDate() - diff);
            return startOfDay(d);
        }
        if (freq === "monthly") {
            return new Date(now.getFullYear(), now.getMonth(), 1);
        }
        return startOfDay(now);
    }

    function isCompletedBy(task, employeeId, now) {
        const completions = task.employeeCompletions || {};
        const completion = completions[employeeId];
        if (!completion) return false;
        if (completion.isApproved === false) return false;
        const freq = task.frequency || "one_time";
        if (freq === "one_time") return true;
        const ts = toDate(completion.timestamp);
        if (!ts) return false;
        return ts >= getTaskCycleStart(task, now);
    }

    function makeSegment(numerator, denominator) {
        const pct = denominator > 0 ? Math.min(1, Math.max(0, numerator / denominator)) : 0;
        return {
            numerator,
            denominator,
            percentage: pct,
            displayPercent: Math.round(pct * 100),
        };
    }

    function locationToday(tasks, now) {
        now = now || new Date();
        const assigned = tasks.filter((t) => (t.assignedEmployeeIds || []).length > 0);
        if (!assigned.length) return null;
        const done = assigned.filter((t) =>
            t.assignedEmployeeIds.every((id) => isCompletedBy(t, id, now))
        ).length;
        return makeSegment(done, assigned.length);
    }

    function locationSevenDay(tasks, now) {
        now = now || new Date();
        const assigned = tasks.filter((t) => (t.assignedEmployeeIds || []).length > 0);
        if (!assigned.length) return null;

        const todayStart = startOfDay(now);
        const windowStart = new Date(todayStart);
        windowStart.setDate(windowStart.getDate() - 7);
        const windowEnd = todayStart;

        let actual = 0;
        let expected = 0;

        for (const task of assigned) {
            const assigneeCount = task.assignedEmployeeIds.length;
            const created = toDate(task.createdAt);
            const effectiveStart = created
                ? new Date(Math.max(startOfDay(created).getTime(), windowStart.getTime()))
                : windowStart;
            if (effectiveStart >= windowEnd) continue;

            const daysAlive = Math.floor((windowEnd - effectiveStart) / 86400000);
            const freq = task.frequency || "one_time";
            let cyclesInWindow = 0;
            if (freq === "daily") cyclesInWindow = Math.max(0, Math.min(7, daysAlive));
            else cyclesInWindow = daysAlive > 0 ? 1 : 0;

            expected += cyclesInWindow * assigneeCount;

            const completions = task.employeeCompletions || {};
            Object.values(completions).forEach((c) => {
                const ts = toDate(c.timestamp);
                if (!ts || ts < windowStart || ts >= windowEnd) return;
                if (c.isApproved === false) return;
                actual += 1;
            });
        }

        if (expected <= 0) return null;
        return makeSegment(actual, expected);
    }

    function tasksForLocation(tasks, locationId) {
        return tasks.filter((t) => t.locationId === locationId);
    }

    function employeeToday(tasks, employeeId, now) {
        now = now || new Date();
        const assigned = tasks.filter((t) =>
            (t.assignedEmployeeIds || []).includes(employeeId)
        );
        if (!assigned.length) return null;
        const completed = assigned.filter((t) => isCompletedBy(t, employeeId, now)).length;
        return { completed, assigned: assigned.length };
    }

    window.OplixTaskProgress = {
        locationToday,
        locationSevenDay,
        tasksForLocation,
        employeeToday,
        toDate,
        startOfDay,
        getTaskCycleStart,
        isCompletedBy,
    };
})();
