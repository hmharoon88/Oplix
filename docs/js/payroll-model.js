/**
 * Manual payroll entries (web-first).
 *
 * Firestore: users/{uid}/locations/{locationId}/payrollEntries/{id}
 */
(function () {
    const COLLECTION = "payrollEntries";

    const PERIOD_MODES = [
        { id: "daily", label: "Daily" },
        { id: "weekly", label: "Weekly" },
        { id: "monthly", label: "Monthly" },
    ];

    function num(v) {
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 0;
    }

    function calcPay(hours, rate) {
        return Math.round(num(hours) * num(rate) * 100) / 100;
    }

    function defaultEntry(locationId) {
        return {
            locationId: locationId || "",
            periodType: "weekly",
            periodKey: "",
            employeeId: "",
            employeeName: "",
            hours: 0,
            hourlyRate: 0,
            pay: 0,
            notes: "",
            active: true,
        };
    }

    function normalizeEntry(raw, locationId) {
        const e = { ...defaultEntry(locationId), ...(raw || {}) };
        const hours = num(e.hours);
        const hourlyRate = num(e.hourlyRate);
        const periodType = PERIOD_MODES.some((p) => p.id === e.periodType) ? e.periodType : "weekly";
        return {
            ...e,
            periodType,
            periodKey: String(e.periodKey || "").trim(),
            employeeId: String(e.employeeId || "").trim(),
            employeeName: String(e.employeeName || "").trim(),
            hours,
            hourlyRate,
            pay: e.pay != null && e.pay !== "" ? num(e.pay) : calcPay(hours, hourlyRate),
            notes: String(e.notes || "").trim(),
        };
    }

    function isoWeekKey(date) {
        const d = new Date(date);
        d.setHours(12, 0, 0, 0);
        const day = d.getDay() || 7;
        d.setDate(d.getDate() + 4 - day);
        const yearStart = new Date(d.getFullYear(), 0, 1);
        const weekNo = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
        return `${d.getFullYear()}-W${String(weekNo).padStart(2, "0")}`;
    }

    function weekKeyToMonday(weekKey) {
        const m = /^(\d{4})-W(\d{2})$/.exec(weekKey || "");
        if (!m) return null;
        const year = parseInt(m[1], 10);
        const week = parseInt(m[2], 10);
        const jan4 = new Date(year, 0, 4, 12, 0, 0, 0);
        const day = jan4.getDay() || 7;
        const monday = new Date(jan4);
        monday.setDate(jan4.getDate() - day + 1 + (week - 1) * 7);
        return monday;
    }

    function weekRangeLabel(weekKey) {
        const monday = weekKeyToMonday(weekKey);
        if (!monday) return weekKey || "";
        const sunday = new Date(monday);
        sunday.setDate(monday.getDate() + 6);
        const fmt = (d) =>
            d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
        return `${fmt(monday)} – ${fmt(sunday)}`;
    }

    /** Calendar month (YYYY-MM) this payroll entry belongs to for books. */
    function entryMonthId(entry, booksModel) {
        const B = booksModel || window.OplixBooksModel;
        const e = normalizeEntry(entry);
        if (!e.periodKey) return "";
        if (e.periodType === "monthly") return e.periodKey.slice(0, 7);
        if (e.periodType === "daily") return e.periodKey.slice(0, 7);
        if (e.periodType === "weekly") {
            const monday = weekKeyToMonday(e.periodKey);
            return monday ? B.monthIdFromDate(monday) : "";
        }
        return "";
    }

    function entryBelongsToMonth(entry, monthId, booksModel) {
        return entryMonthId(entry, booksModel) === monthId;
    }

    function weekOfMonth(dayId) {
        const day = parseInt(String(dayId || "").slice(8, 10), 10);
        if (!Number.isFinite(day) || day < 1) return "week1";
        if (day <= 7) return "week1";
        if (day <= 14) return "week2";
        if (day <= 21) return "week3";
        return "week4";
    }

    function employeeKey(entry) {
        const e = normalizeEntry(entry);
        return e.employeeId || `name:${e.employeeName.toLowerCase()}`;
    }

    /** Sum payroll entries in a books month → employee lines + week buckets. */
    function buildBooksPayrollFromEntries(allEntries, monthId, booksModel) {
        const B = booksModel || window.OplixBooksModel;
        const inMonth = (allEntries || []).filter(
            (e) => e.active !== false && entryBelongsToMonth(e, monthId, B)
        );

        const byEmployee = new Map();
        inMonth.forEach((entry) => {
            const e = normalizeEntry(entry);
            const key = employeeKey(e);
            const existing = byEmployee.get(key) || {
                id: key,
                employeeId: e.employeeId,
                employeeName: e.employeeName || "Employee",
                hours: 0,
                hourlyRate: 0,
                pay: 0,
            };
            existing.hours += num(e.hours);
            existing.pay += num(e.pay);
            if (num(e.hourlyRate) > 0) {
                existing.hourlyRate = num(e.hourlyRate);
            }
            byEmployee.set(key, existing);
        });

        const payrollLines = [...byEmployee.values()]
            .map((line) => ({
                ...line,
                hours: Math.round(line.hours * 100) / 100,
                pay: Math.round(line.pay * 100) / 100,
                hourlyRate:
                    line.hours > 0
                        ? Math.round((line.pay / line.hours) * 100) / 100
                        : line.hourlyRate,
            }))
            .filter((l) => l.pay > 0 || l.hours > 0)
            .sort((a, b) => a.employeeName.localeCompare(b.employeeName));

        const payroll = { week1: 0, week2: 0, week3: 0, week4: 0 };
        inMonth.forEach((entry) => {
            const e = normalizeEntry(entry);
            const pay = num(e.pay);
            if (pay <= 0) return;
            if (e.periodType === "daily") {
                payroll[weekOfMonth(e.periodKey)] += pay;
            } else if (e.periodType === "weekly") {
                const monday = weekKeyToMonday(e.periodKey);
                if (monday) {
                    payroll[weekOfMonth(B.dayIdFromDate(monday))] += pay;
                }
            } else if (e.periodType === "monthly") {
                payroll.week4 += pay;
            }
        });
        Object.keys(payroll).forEach((k) => {
            payroll[k] = Math.round(payroll[k] * 100) / 100;
        });

        return { payrollLines, payroll };
    }

    function affectedMonthIds(allEntries, extraMonthIds) {
        const B = window.OplixBooksModel;
        const set = new Set(extraMonthIds || []);
        (allEntries || []).forEach((e) => {
            if (e.active === false) return;
            const m = entryMonthId(e, B);
            if (m) set.add(m);
        });
        return [...set];
    }

    function periodKeyForMode(mode, state, booksModel) {
        const B = booksModel || window.OplixBooksModel;
        if (mode === "daily") return state.dayId || B.dayIdFromDate(new Date());
        if (mode === "monthly") return state.monthId || B.monthIdFromDate(new Date());
        const anchor = state.weekDate || new Date().toISOString().slice(0, 10);
        return isoWeekKey(new Date(anchor + "T12:00:00"));
    }

    function periodLabel(mode, periodKey, booksModel) {
        const B = booksModel || window.OplixBooksModel;
        if (mode === "daily") {
            const d = new Date(periodKey + "T12:00:00");
            return d.toLocaleDateString("en-US", {
                weekday: "short",
                month: "long",
                day: "numeric",
                year: "numeric",
            });
        }
        if (mode === "monthly") {
            const d = B.parseMonthId(periodKey);
            return d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
        }
        return weekRangeLabel(periodKey);
    }

    function filterEntries(entries, periodType, periodKey) {
        return (entries || []).filter(
            (e) => e.active !== false && e.periodType === periodType && e.periodKey === periodKey
        );
    }

    function totals(entries) {
        const list = entries || [];
        return {
            hours: list.reduce((s, e) => s + num(e.hours), 0),
            pay: list.reduce((s, e) => s + num(e.pay), 0),
            count: list.length,
        };
    }

    window.OplixPayrollModel = {
        COLLECTION,
        PERIOD_MODES,
        defaultEntry,
        normalizeEntry,
        calcPay,
        num,
        isoWeekKey,
        weekRangeLabel,
        periodKeyForMode,
        periodLabel,
        filterEntries,
        totals,
        weekKeyToMonday,
        entryMonthId,
        entryBelongsToMonth,
        buildBooksPayrollFromEntries,
        affectedMonthIds,
    };
})();
