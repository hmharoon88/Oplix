/**
 * Store books / accounting workbook schema (SAVEWAY-style).
 * Designed for cross-facility and cross-period comparison in Books summary.
 */
(function () {
    const UTILITY_KEYS = [
        { key: "internet", label: "Internet" },
        { key: "water", label: "Water" },
        { key: "electric", label: "Electric" },
        { key: "trash", label: "Trash" },
        { key: "gas", label: "Gas" },
        { key: "alarm", label: "Alarm" },
        { key: "rent", label: "Rent" },
    ];

    const UTILITY_VENDOR_GROUPS = UTILITY_KEYS.map((u) => ({
        id: u.key,
        label: u.label,
        type: "utility",
    }));

    function emptyShiftRegister() {
        return { cardSale: 0, cashSale: 0, overShort: 0 };
    }

    function defaultRegisterUnit() {
        return {
            shift1: emptyShiftRegister(),
            shift2: emptyShiftRegister(),
        };
    }

    function emptyGamingShift() {
        return { cash: 0, overShort: 0 };
    }

    function emptyPulltab() {
        return { cash: 0, winner: 0, overShort: 0 };
    }

    function defaultFuelSale() {
        return { gallons: 0, dollars: 0 };
    }

    function defaultUtilities() {
        const o = {};
        UTILITY_KEYS.forEach((u) => {
            o[u.key] = 0;
        });
        return o;
    }

    function slugUtilityKey(label) {
        const s = String(label || "")
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "_")
            .replace(/^_+|_+$/g, "");
        if (!s) return "custom_utility";
        if (UTILITY_KEYS.some((u) => u.key === s)) return `custom_${s}`;
        return s;
    }

    function isStandardUtilityKey(key) {
        return UTILITY_KEYS.some((u) => u.key === key);
    }

    function labelForUtilityKey(key, providers) {
        const p = (providers || []).find((x) => (x.utilityType || x.id) === key);
        if (p?.customLabel) return p.customLabel;
        const std = UTILITY_KEYS.find((u) => u.key === key);
        if (std) return std.label;
        return String(key || "")
            .replace(/_/g, " ")
            .replace(/\b\w/g, (c) => c.toUpperCase());
    }

    /** Same utility lines as Daily books — standard keys + custom providers + saved month amounts. */
    function mergeUtilityKeys(providers, monthUtilities) {
        const map = new Map();
        UTILITY_KEYS.forEach((u) => {
            map.set(u.key, { key: u.key, label: u.label, isDefault: true });
        });
        (providers || [])
            .filter((p) => p.active !== false)
            .forEach((p) => {
                const key = p.utilityType || p.id;
                if (!key) return;
                map.set(key, {
                    key,
                    label: labelForUtilityKey(key, providers),
                    isDefault: !!p.isDefault || isStandardUtilityKey(key),
                });
            });
        Object.keys(monthUtilities || {}).forEach((key) => {
            if (!map.has(key)) {
                map.set(key, {
                    key,
                    label: labelForUtilityKey(key, providers),
                    isDefault: isStandardUtilityKey(key),
                });
            }
        });
        const order = (a, b) => {
            const ai = UTILITY_KEYS.findIndex((u) => u.key === a.key);
            const bi = UTILITY_KEYS.findIndex((u) => u.key === b.key);
            if (ai >= 0 && bi >= 0) return ai - bi;
            if (ai >= 0) return -1;
            if (bi >= 0) return 1;
            return a.label.localeCompare(b.label);
        };
        return [...map.values()].sort(order);
    }

    function normalizeMonthUtilities(utilities, mergedKeys) {
        const out = { ...(utilities || {}) };
        (mergedKeys || mergeUtilityKeys([], utilities)).forEach((u) => {
            if (out[u.key] === undefined) out[u.key] = 0;
        });
        UTILITY_KEYS.forEach((u) => {
            if (out[u.key] === undefined) out[u.key] = 0;
        });
        return out;
    }

    function utilitiesBreakdownFrom(utilities, providers) {
        const merged = mergeUtilityKeys(providers, utilities);
        return merged.map((u) => ({
            key: u.key,
            label: u.label,
            amount: num((utilities || {})[u.key]),
        }));
    }

    function utilitiesTotalFrom(utilities) {
        return Object.keys(utilities || {}).reduce((s, k) => s + num(utilities[k]), 0);
    }

    function defaultPayroll() {
        return { week1: 0, week2: 0, week3: 0, week4: 0 };
    }

    function defaultPayrollLine() {
        return {
            id: "",
            employeeId: "",
            employeeName: "",
            hours: 0,
            hourlyRate: 0,
            pay: 0,
        };
    }

    function normalizePayrollLine(raw) {
        const base = defaultPayrollLine();
        const line = { ...base, ...(raw || {}) };
        return {
            ...line,
            employeeName: String(line.employeeName || "").trim(),
            hours: num(line.hours),
            hourlyRate: num(line.hourlyRate),
            pay: num(line.pay),
        };
    }

    function payrollTotalFrom(month) {
        const lines = (month?.payrollLines || []).map(normalizePayrollLine);
        const fromLines = lines.reduce((s, l) => s + num(l.pay), 0);
        if (lines.length > 0) return fromLines;
        const payroll = month?.payroll || defaultPayroll();
        return (
            num(payroll.week1) +
            num(payroll.week2) +
            num(payroll.week3) +
            num(payroll.week4)
        );
    }

    function defaultMonthDoc() {
        return {
            utilities: defaultUtilities(),
            payroll: defaultPayroll(),
            payrollLines: [],
            receivables: [],
            salesTax: 0,
            accountant: 0,
            categorySales: {},
            updatedAt: null,
        };
    }

    function defaultDayDoc() {
        return {
            register1: defaultRegisterUnit(),
            register2: defaultRegisterUnit(),
            lottery: {
                shift1: emptyGamingShift(),
                shift2: emptyGamingShift(),
            },
            pulltab: emptyPulltab(),
            fuelSale: defaultFuelSale(),
            merchSale: 0,
            creditCard: 0,
            cashExpenses: [],
            checksAch: [],
            otherExpenses: [],
            updatedAt: null,
        };
    }

    function monthIdFromDate(d) {
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        return `${y}-${m}`;
    }

    function dayIdFromDate(d) {
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }

    function parseMonthId(monthId) {
        const [y, m] = monthId.split("-").map(Number);
        return new Date(y, m - 1, 1);
    }

    function daysInMonth(monthId) {
        const d = parseMonthId(monthId);
        return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    }

    /**
     * Parse amount fields: plain numbers, negatives, and sums like 100+50-25.
     */
    function parseAmountExpression(input) {
        const s = String(input ?? "")
            .trim()
            .replace(/,/g, "");
        if (s === "") return null;
        if (/^[+-]?(?:\d+\.?\d*|\.\d+)$/.test(s)) {
            const n = parseFloat(s);
            return Number.isFinite(n) ? n : NaN;
        }
        if (!/^[\d.\s+\-]+$/.test(s)) return NaN;
        const parts = s.match(/[+-]?(?:\d+\.?\d*|\.\d+)/g);
        if (!parts || !parts.length) return NaN;
        let total = 0;
        for (const p of parts) {
            const n = parseFloat(p);
            if (!Number.isFinite(n)) return NaN;
            total += n;
        }
        return total;
    }

    function num(v) {
        if (v == null || v === "") return 0;
        if (typeof v === "number") return Number.isFinite(v) ? v : 0;
        const fromExpr = parseAmountExpression(v);
        if (fromExpr !== null && Number.isFinite(fromExpr)) return fromExpr;
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 0;
    }

    function formatAmountForInput(v) {
        const n = typeof v === "number" ? v : num(v);
        if (!Number.isFinite(n)) return "";
        const r = Math.round(n * 100) / 100;
        if (Number.isInteger(r)) return String(r);
        return r.toFixed(2).replace(/\.?0+$/, "");
    }

    function sumLines(lines, field) {
        return (lines || []).reduce((s, row) => s + num(row[field]), 0);
    }

    function registerBlockTotal(block) {
        const r = block || defaultRegisterUnit();
        const s1 = r.shift1 || {};
        const s2 = r.shift2 || {};
        return {
            card: num(s1.cardSale) + num(s2.cardSale),
            cash: num(s1.cashSale) + num(s2.cashSale),
            overShort: num(s1.overShort) + num(s2.overShort),
        };
    }

    function registerDayTotal(day) {
        const r1 = registerBlockTotal(day.register1);
        const r2 = registerBlockTotal(day.register2);
        const legacy =
            day.register && !day.register1
                ? registerBlockTotal(day.register)
                : { card: 0, cash: 0, overShort: 0 };
        return {
            card: r1.card + r2.card + legacy.card,
            cash: r1.cash + r2.cash + legacy.cash,
            overShort: r1.overShort + r2.overShort + legacy.overShort,
        };
    }

    function lotteryDayTotal(day) {
        const l = day.lottery || {};
        const s1 = l.shift1 || {};
        const s2 = l.shift2 || {};
        return {
            cash: num(s1.cash) + num(s2.cash),
            overShort: num(s1.overShort) + num(s2.overShort),
        };
    }

    function pulltabDayTotal(day) {
        const p = day.pulltab || {};
        return {
            cash: num(p.cash),
            winner: num(p.winner),
            overShort: num(p.overShort),
        };
    }

    function fuelDayTotal(day) {
        const f = day.fuelSale || defaultFuelSale();
        return {
            gallons: num(f.gallons),
            dollars: num(f.dollars),
        };
    }

    /** Merge saved day doc with defaults (handles older docs missing fuelSale). */
    function normalizeDayDoc(day) {
        if (!day) return defaultDayDoc();
        const base = defaultDayDoc();
        const d = { ...base, ...day };
        const legacyRegister = day.register && !day.register1 ? day.register : null;
        const src1 = day.register1 || legacyRegister || {};
        const src2 = day.register2 || {};
        d.register1 = {
            shift1: { ...emptyShiftRegister(), ...(src1.shift1 || {}) },
            shift2: { ...emptyShiftRegister(), ...(src1.shift2 || {}) },
        };
        d.register2 = {
            shift1: { ...emptyShiftRegister(), ...(src2.shift1 || {}) },
            shift2: { ...emptyShiftRegister(), ...(src2.shift2 || {}) },
        };
        delete d.register;
        d.lottery = {
            shift1: { ...emptyGamingShift(), ...(day.lottery?.shift1 || {}) },
            shift2: { ...emptyGamingShift(), ...(day.lottery?.shift2 || {}) },
        };
        d.pulltab = { ...emptyPulltab(), ...(day.pulltab || {}) };
        d.fuelSale = { ...defaultFuelSale(), ...(day.fuelSale || {}) };
        d.merchSale = num(day.merchSale);
        d.creditCard = num(day.creditCard);
        d.cashExpenses = day.cashExpenses || [];
        d.checksAch = day.checksAch || [];
        d.otherExpenses = day.otherExpenses || [];
        delete d._dayId;
        return d;
    }

    /**
     * C Store: card/cash from registers (total sales).
     * Gas station: register card/cash from detail sheet (merch area); pump credit is separate.
     */
    function cardCashBreakdownFromAggregate(agg) {
        const hasGas = !!(agg && agg.hasGasStation);
        if (hasGas) {
            return {
                card: num(agg.registerCard),
                cash: num(agg.registerCash),
                total: num(agg.registerCard) + num(agg.registerCash),
                slices: [
                    { label: "Register — card", amount: num(agg.registerCard) },
                    { label: "Register — cash", amount: num(agg.registerCash) },
                ],
            };
        }
        return {
            card: num(agg.registerCard),
            cash: num(agg.registerCash),
            total: num(agg.registerCard) + num(agg.registerCash),
            slices: [
                { label: "Register — card", amount: num(agg.registerCard) },
                { label: "Register — cash", amount: num(agg.registerCash) },
            ],
        };
    }

    /** Full gas-station sales drill-down — all tracked revenue lines. */
    function gasSalesDetailBreakdownFromAggregate(agg) {
        return [
            { label: "Merch sale", amount: num(agg.merchSale) },
            { label: "Register — card", amount: num(agg.registerCard) },
            { label: "Register — cash", amount: num(agg.registerCash) },
            { label: "Credit card (pump)", amount: num(agg.creditCard) },
            { label: "Fuel gallons", amount: num(agg.fuelGallons), format: "number" },
            { label: "Fuel sales ($)", amount: num(agg.fuelDollars) },
            { label: "Pulltab", amount: num(agg.pulltabCash) },
            { label: "Lottery", amount: num(agg.lotteryCash) },
        ];
    }

    function salesBreakdownFromAggregate(agg) {
        if (agg.hasGasStation) {
            return gasSalesDetailBreakdownFromAggregate(agg);
        }
        return [
            { label: "Register — card", amount: num(agg.registerCard) },
            { label: "Register — cash", amount: num(agg.registerCash) },
        ];
    }

    /** Gas station chart slices — merch, register card, pump credit, and fuel (separate from total sales). */
    function gasSalesSlicesFromAggregate(agg) {
        return [
            { label: "Merch", amount: num(agg.merchSale) },
            { label: "Register card", amount: num(agg.registerCard) },
            { label: "Pump credit", amount: num(agg.creditCard) },
            { label: "Fuel", amount: num(agg.fuelDollars) },
        ];
    }

    /** Line-level expenses for Books summary drill-down. */
    function buildExpenseDetail(monthDoc, daysById) {
        const month = monthDoc || defaultMonthDoc();
        const lines = [];

        Object.keys(month.utilities || {}).forEach((key) => {
            const amount = num(month.utilities[key]);
            if (amount !== 0) {
                lines.push({
                    category: "Utility",
                    description: labelForUtilityKey(key, []),
                    amount,
                });
            }
        });

        const payroll = month.payroll || defaultPayroll();
        const payrollLines = (month.payrollLines || []).map(normalizePayrollLine);
        if (payrollLines.length) {
            payrollLines.forEach((line) => {
                if (num(line.pay) !== 0 || line.employeeName) {
                    lines.push({
                        category: "Payroll",
                        description: line.employeeName || "Employee",
                        amount: num(line.pay),
                    });
                }
            });
        } else {
            ["week1", "week2", "week3", "week4"].forEach((w, i) => {
                const amount = num(payroll[w]);
                if (amount !== 0) {
                    lines.push({ category: "Payroll", description: `Week ${i + 1}`, amount });
                }
            });
        }

        if (num(month.salesTax) !== 0) {
            lines.push({ category: "Monthly", description: "Sales tax", amount: num(month.salesTax) });
        }
        if (num(month.accountant) !== 0) {
            lines.push({ category: "Monthly", description: "Accountant", amount: num(month.accountant) });
        }

        Object.keys(daysById || {})
            .sort()
            .forEach((dayId) => {
                const day = normalizeDayDoc(daysById[dayId]);
                (day.cashExpenses || []).forEach((row) => {
                    const amount = num(row.amount);
                    if (amount === 0 && !row.description) return;
                    lines.push({
                        category: "Cash expense",
                        dayId,
                        description: row.description || "(no description)",
                        amount,
                    });
                });
                (day.checksAch || []).forEach((row) => {
                    const amount = num(row.amount);
                    const parts = [row.description, row.checkNo ? `#${row.checkNo}` : ""].filter(Boolean);
                    if (amount === 0 && !parts.length) return;
                    lines.push({
                        category: "Check / ACH",
                        dayId,
                        date: row.date || dayId,
                        description: parts.join(" · ") || "(no description)",
                        amount,
                    });
                });
                (day.otherExpenses || []).forEach((row) => {
                    const amount = num(row.amount);
                    if (amount === 0 && !row.description) return;
                    lines.push({
                        category: "Other expense",
                        dayId,
                        description: row.description || "(no description)",
                        amount,
                    });
                });
            });

        return lines.sort((a, b) => b.amount - a.amount);
    }

    /** Daily sales total — merch for gas; register card + cash for C Store. */
    function daySalesForAggregate(day, hasGasStation) {
        if (hasGasStation) {
            return num(day.merchSale);
        }
        const reg = registerDayTotal(day);
        return reg.card + reg.cash;
    }

    /** Aggregate one month (month doc + all days) for Books summary. */
    function aggregateMonth(monthDoc, daysById, options) {
        const month = monthDoc || defaultMonthDoc();
        const days = Object.values(daysById || {});
        const hasGasStation = !!(options && options.hasGasStation);

        let registerCard = 0;
        let registerCash = 0;
        let registerOverShort = 0;
        let lotteryCash = 0;
        let lotteryOverShort = 0;
        let pulltabCash = 0;
        let pulltabWinner = 0;
        let pulltabOverShort = 0;
        let cashExpense = 0;
        let checksAch = 0;
        let otherExpense = 0;
        let fuelGallons = 0;
        let fuelDollars = 0;
        let merchSale = 0;
        let creditCard = 0;

        const dailySeries = [];

        days.forEach((day) => {
            const reg = registerDayTotal(day);
            const lot = lotteryDayTotal(day);
            const pull = pulltabDayTotal(day);
            const fuel = fuelDayTotal(day);
            const dayMerch = num(day.merchSale);
            const dayCredit = num(day.creditCard);
            const dayCash = sumLines(day.cashExpenses, "amount");
            const dayChecks = sumLines(day.checksAch, "amount");
            const dayOther = sumLines(day.otherExpenses, "amount");

            registerCard += reg.card;
            registerCash += reg.cash;
            registerOverShort += reg.overShort;
            lotteryCash += lot.cash;
            lotteryOverShort += lot.overShort;
            pulltabCash += pull.cash;
            pulltabWinner += pull.winner;
            pulltabOverShort += pull.overShort;
            fuelGallons += fuel.gallons;
            fuelDollars += fuel.dollars;
            merchSale += dayMerch;
            creditCard += dayCredit;
            cashExpense += dayCash;
            checksAch += dayChecks;
            otherExpense += dayOther;

            dailySeries.push({
                dayId: day._dayId,
                sales: daySalesForAggregate(day, hasGasStation),
                fuelGallons: fuel.gallons,
                fuelDollars: fuel.dollars,
                merchSale: dayMerch,
                creditCard: dayCredit,
                expenses: dayCash + dayChecks + dayOther,
                overShort: reg.overShort + lot.overShort + pull.overShort,
            });
        });

        const utilities = month.utilities || defaultUtilities();
        const utilitiesTotal = utilitiesTotalFrom(utilities);
        const payroll = month.payroll || defaultPayroll();
        const payrollLines = (month.payrollLines || []).map(normalizePayrollLine);
        const payrollTotal = payrollTotalFrom(month);
        const receivablesTotal = sumLines(month.receivables, "amount");

        const sales = hasGasStation ? merchSale : registerCard + registerCash;
        const totalRevenue = hasGasStation
            ? merchSale + creditCard + fuelDollars + pulltabCash
            : sales;
        const expenses =
            cashExpense +
            checksAch +
            otherExpense +
            utilitiesTotal +
            payrollTotal +
            num(month.salesTax) +
            num(month.accountant);

        const aggCore = {
            hasGasStation,
            sales,
            registerCard,
            registerCash,
            registerOverShort,
            lotteryCash,
            lotteryOverShort,
            pulltabCash,
            pulltabWinner,
            pulltabOverShort,
            fuelGallons,
            fuelDollars,
            merchSale,
            creditCard,
            cashExpense,
            checksAch,
            otherExpense,
            utilities,
            utilitiesTotal,
            utilitiesBreakdown: utilitiesBreakdownFrom(utilities, []),
            payroll,
            payrollLines,
            payrollTotal,
            receivables: month.receivables || [],
            receivablesTotal,
            salesTax: num(month.salesTax),
            accountant: num(month.accountant),
            expenses,
            net: totalRevenue + receivablesTotal - expenses,
            totalRevenue,
            totalOverShort: registerOverShort + lotteryOverShort + pulltabOverShort,
            dailySeries,
            dayCount: days.length,
        };

        return {
            ...aggCore,
            salesBreakdown: salesBreakdownFromAggregate(aggCore),
            expenseDetail: buildExpenseDetail(month, daysById),
        };
    }

    /**
     * Compare two aggregated months (same facility periods or two facilities).
     */
    function compareAggregates(base, compare, labels) {
        const metrics = [
            { key: "sales", label: "Total sales" },
            { key: "fuelDollars", label: "Fuel sales ($)" },
            { key: "fuelGallons", label: "Fuel gallons", format: "number" },
            { key: "merchSale", label: "Merch sale (store)" },
            { key: "registerCard", label: "Register — card" },
            { key: "creditCard", label: "Credit card (pump)" },
            { key: "expenses", label: "Total expenses" },
            { key: "net", label: "Net" },
            { key: "receivablesTotal", label: "Receivables" },
            { key: "utilitiesTotal", label: "Utilities" },
            { key: "payrollTotal", label: "Payroll" },
            { key: "cashExpense", label: "Cash expense" },
            { key: "checksAch", label: "Checks / ACH" },
            { key: "otherExpense", label: "Other expense" },
            { key: "totalOverShort", label: "Over / short" },
        ];

        const rows = metrics.map((m) => {
            const a = num(base[m.key]);
            const b = num(compare[m.key]);
            // Change from compare month → base month (e.g. April → May)
            const diff = a - b;
            const pct = b !== 0 ? (diff / b) * 100 : a !== 0 ? 100 : 0;
            return { ...m, base: a, compare: b, diff, pct, format: m.format };
        });

        const utilityKeySet = new Set();
        UTILITY_KEYS.forEach((u) => utilityKeySet.add(u.key));
        Object.keys(base.utilities || {}).forEach((k) => utilityKeySet.add(k));
        Object.keys(compare.utilities || {}).forEach((k) => utilityKeySet.add(k));
        const utilityRows = [...utilityKeySet].map((key) => {
            const a = num(base.utilities?.[key]);
            const b = num(compare.utilities?.[key]);
            const diff = a - b;
            return {
                key,
                label: labelForUtilityKey(key, []),
                base: a,
                compare: b,
                diff,
                pct: b !== 0 ? (diff / b) * 100 : a !== 0 ? 100 : 0,
            };
        });

        return {
            labels: labels || { base: "Base", compare: "Compare" },
            metrics: rows,
            utilities: utilityRows,
        };
    }

    window.OplixBooksModel = {
        UTILITY_KEYS,
        UTILITY_VENDOR_GROUPS,
        emptyShiftRegister,
        defaultRegisterUnit,
        registerBlockTotal,
        emptyGamingShift,
        emptyPulltab,
        defaultFuelSale,
        fuelDayTotal,
        normalizeDayDoc,
        defaultUtilities,
        defaultPayroll,
        defaultPayrollLine,
        normalizePayrollLine,
        payrollTotalFrom,
        defaultMonthDoc,
        defaultDayDoc,
        monthIdFromDate,
        dayIdFromDate,
        parseMonthId,
        daysInMonth,
        num,
        parseAmountExpression,
        formatAmountForInput,
        slugUtilityKey,
        isStandardUtilityKey,
        labelForUtilityKey,
        mergeUtilityKeys,
        normalizeMonthUtilities,
        utilitiesBreakdownFrom,
        utilitiesTotalFrom,
        sumLines,
        registerDayTotal,
        daySalesForAggregate,
        cardCashBreakdownFromAggregate,
        gasSalesSlicesFromAggregate,
        gasSalesDetailBreakdownFromAggregate,
        salesBreakdownFromAggregate,
        buildExpenseDetail,
        aggregateMonth,
        compareAggregates,
    };
})();
