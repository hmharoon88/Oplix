/**
 * Per-day assigned / done / missed breakdown — mirrors TaskAssignmentAudit (Swift).
 */
(function () {
    const TP = () => window.OplixTaskProgress;
    const M = () => window.OplixTasksModel;

    const LOOKBACK_DAYS = 30;

    function startOfDay(d) {
        return TP().startOfDay(d instanceof Date ? d : new Date(d));
    }

    function isSameDay(a, b) {
        const da = startOfDay(a);
        const db = startOfDay(b);
        return da.getTime() === db.getTime();
    }

    function addDays(d, n) {
        const x = new Date(d);
        x.setDate(x.getDate() + n);
        return startOfDay(x);
    }

    function countsAsCompleted(completion) {
        return completion?.isApproved !== false;
    }

    function completionUrls(completion) {
        const urls = completion?.imageURLs;
        if (Array.isArray(urls) && urls.length) return urls.filter(Boolean);
        if (completion?.imageURL) return [completion.imageURL];
        return [];
    }

    function allCompletionsForHistory(task) {
        const entries = [
            ...(Array.isArray(task.completionHistory) ? task.completionHistory : []),
            ...Object.values(task.employeeCompletions || {}),
        ];
        const seen = new Set();
        const result = [];
        entries.forEach((c) => {
            const ts = TP().toDate(c.timestamp);
            if (!ts) return;
            const key = `${c.employeeId}-${Math.floor(ts.getTime() / 1000)}`;
            if (seen.has(key)) return;
            seen.add(key);
            result.push(c);
        });
        return result.sort((a, b) => TP().toDate(b.timestamp) - TP().toDate(a.timestamp));
    }

    function taskExisted(task, dayEnd) {
        const created = TP().toDate(task.createdAt);
        if (!created) return true;
        return startOfDay(created).getTime() < dayEnd.getTime();
    }

    function isLastDayOfWeek(day) {
        const next = addDays(day, 1);
        return day.getDay() !== next.getDay() || next.getDay() === 0;
    }

    function isLastDayOfMonth(day) {
        const next = addDays(day, 1);
        return day.getMonth() !== next.getMonth();
    }

    function weekInterval(dayStart) {
        const d = new Date(dayStart);
        const day = d.getDay();
        const diff = day === 0 ? 6 : day - 1;
        d.setDate(d.getDate() - diff);
        const start = startOfDay(d);
        const end = addDays(start, 7);
        return { start, end };
    }

    function monthInterval(dayStart) {
        const start = new Date(dayStart.getFullYear(), dayStart.getMonth(), 1);
        const end = new Date(dayStart.getFullYear(), dayStart.getMonth() + 1, 1);
        return { start, end };
    }

    function firstQualifyingCompletion(task, employeeId, filterFn) {
        const matches = allCompletionsForHistory(task).filter(
            (c) => c.employeeId === employeeId && countsAsCompleted(c) && filterFn(c)
        );
        if (!matches.length) return null;
        return matches.reduce((best, c) => {
            const ts = TP().toDate(c.timestamp);
            const bestTs = TP().toDate(best.timestamp);
            return ts > bestTs ? c : best;
        });
    }

    function hasQualifyingBefore(task, employeeId, dayEnd) {
        return allCompletionsForHistory(task).some((c) => {
            const ts = TP().toDate(c.timestamp);
            return (
                c.employeeId === employeeId &&
                countsAsCompleted(c) &&
                ts &&
                ts.getTime() < dayEnd.getTime()
            );
        });
    }

    function isExpected(task, employeeId, dayStart, dayEnd, todayStart) {
        if (!taskExisted(task, dayEnd)) return false;
        const freq = task.frequency || "one_time";
        if (freq === "daily") return true;
        if (freq === "weekly") return isLastDayOfWeek(dayStart);
        if (freq === "monthly") return isLastDayOfMonth(dayStart);
        return !hasQualifyingBefore(task, employeeId, dayEnd);
    }

    function qualifyingCompletion(task, employeeId, dayStart) {
        const freq = task.frequency || "one_time";
        if (freq === "daily" || freq === "one_time") {
            return firstQualifyingCompletion(task, employeeId, (c) =>
                isSameDay(TP().toDate(c.timestamp), dayStart)
            );
        }
        if (freq === "weekly") {
            const { start, end } = weekInterval(dayStart);
            return firstQualifyingCompletion(task, employeeId, (c) => {
                const ts = TP().toDate(c.timestamp);
                return ts && ts >= start && ts < end;
            });
        }
        if (freq === "monthly") {
            const { start, end } = monthInterval(dayStart);
            return firstQualifyingCompletion(task, employeeId, (c) => {
                const ts = TP().toDate(c.timestamp);
                return ts && ts >= start && ts < end;
            });
        }
        return null;
    }

    function isMissed(task, employeeId, dayStart) {
        const freq = task.frequency || "one_time";
        if (freq === "daily" || freq === "one_time") {
            return !firstQualifyingCompletion(task, employeeId, (c) =>
                isSameDay(TP().toDate(c.timestamp), dayStart)
            );
        }
        if (freq === "weekly") {
            const { start, end } = weekInterval(dayStart);
            return !firstQualifyingCompletion(task, employeeId, (c) => {
                const ts = TP().toDate(c.timestamp);
                return ts && ts >= start && ts < end;
            });
        }
        if (freq === "monthly") {
            const { start, end } = monthInterval(dayStart);
            return !firstQualifyingCompletion(task, employeeId, (c) => {
                const ts = TP().toDate(c.timestamp);
                return ts && ts >= start && ts < end;
            });
        }
        return false;
    }

    function buildSection(dayStart, tasks, now, todayStart) {
        const dayEnd = addDays(dayStart, 1);
        let assignedCount = 0;
        let doneCount = 0;
        let missedCount = 0;
        const doneEntries = [];
        const missedSlots = [];
        const doneEntryKeys = new Set();

        tasks.forEach((task) => {
            (task.assignedEmployeeIds || []).forEach((employeeId) => {
                if (!isExpected(task, employeeId, dayStart, dayEnd, todayStart)) return;
                assignedCount += 1;
                const completion = qualifyingCompletion(task, employeeId, dayStart);
                if (completion) {
                    doneCount += 1;
                    const entryId = `${task.id}-${completion.employeeId}-${Math.floor(TP().toDate(completion.timestamp).getTime() / 1000)}`;
                    if (!doneEntryKeys.has(entryId)) {
                        doneEntryKeys.add(entryId);
                        doneEntries.push({ task, completion, id: entryId });
                    }
                } else if (isMissed(task, employeeId, dayStart)) {
                    missedCount += 1;
                    missedSlots.push({
                        id: `${task.id}-${employeeId}-${dayStart.getTime()}`,
                        task,
                        employeeId,
                    });
                }
            });

            allCompletionsForHistory(task).forEach((completion) => {
                if (!(task.assignedEmployeeIds || []).includes(completion.employeeId)) return;
                if (!isSameDay(TP().toDate(completion.timestamp), dayStart)) return;
                const entryId = `${task.id}-${completion.employeeId}-${Math.floor(TP().toDate(completion.timestamp).getTime() / 1000)}`;
                if (doneEntryKeys.has(entryId)) return;
                doneEntryKeys.add(entryId);
                doneEntries.push({ task, completion, id: entryId });
                if (countsAsCompleted(completion)) doneCount += 1;
            });
        });

        doneEntries.sort(
            (a, b) => TP().toDate(b.completion.timestamp) - TP().toDate(a.completion.timestamp)
        );
        missedSlots.sort((a, b) =>
            (a.task.description || "").localeCompare(b.task.description || "")
        );

        const hasContent = assignedCount > 0 || doneEntries.length > 0;
        if (!hasContent) return null;

        return {
            id: dayStart.getTime(),
            date: dayStart,
            assignedCount,
            doneCount,
            missedCount,
            doneEntries,
            missedSlots,
        };
    }

    function sections(tasks, now) {
        now = now || new Date();
        const assignedTasks = (tasks || []).filter((t) => (t.assignedEmployeeIds || []).length > 0);
        if (!assignedTasks.length) return [];

        const todayStart = startOfDay(now);
        const rangeStart = addDays(todayStart, -(LOOKBACK_DAYS - 1));
        const dayStarts = [];
        let cursor = rangeStart;
        while (cursor.getTime() <= todayStart.getTime()) {
            dayStarts.push(new Date(cursor));
            cursor = addDays(cursor, 1);
        }

        return dayStarts
            .reverse()
            .map((dayStart) => buildSection(dayStart, assignedTasks, now, todayStart))
            .filter(Boolean);
    }

    window.OplixTaskAssignmentAudit = {
        LOOKBACK_DAYS,
        sections,
        allCompletionsForHistory,
        countsAsCompleted,
        completionUrls,
    };
})();
