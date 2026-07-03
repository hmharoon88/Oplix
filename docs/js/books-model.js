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
        return {
            cardSale: 0,
            cashSale: 0,
            overShort: 0,
            cashPayOut: 0,
            cashPayOutExpense: false,
        };
    }

    function normalizeShiftRegister(raw) {
        const r = raw || {};
        let cashPayOutExpense = false;
        if (r.cashPayOutExpense === true || r.cashPayOutExpense === "expense") {
            cashPayOutExpense = true;
        } else if (r.cashPayOutExpense === false || r.cashPayOutExpense === "track_only") {
            cashPayOutExpense = false;
        }
        return {
            cardSale: num(r.cardSale),
            cashSale: num(r.cashSale),
            overShort: num(r.overShort),
            cashPayOut: num(r.cashPayOut),
            cashPayOutExpense,
        };
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

    function emptyPulltabEntry() {
        return { ticketNumber: "", cash: 0, winner: 0, overShort: 0 };
    }

    function normalizePulltabEntry(raw, fallbackId) {
        const row = raw || {};
        return {
            id: row.id || fallbackId || `pt_${Date.now()}`,
            ticketNumber: String(row.ticketNumber ?? ""),
            cash: num(row.cash),
            winner: num(row.winner),
            overShort: num(row.overShort),
        };
    }

    /** Multiple pulltab machines per day; migrates legacy single `pulltab` object. */
    function normalizePulltabs(pulltabs, legacyPulltab) {
        if (Array.isArray(pulltabs) && pulltabs.length > 0) {
            return pulltabs.map((row, i) => normalizePulltabEntry(row, `pt_${i}`));
        }
        const leg = legacyPulltab || {};
        if (
            num(leg.cash) !== 0 ||
            num(leg.winner) !== 0 ||
            num(leg.overShort) !== 0 ||
            String(leg.ticketNumber ?? "").trim()
        ) {
            return [normalizePulltabEntry(leg, "pt_legacy")];
        }
        return [normalizePulltabEntry({}, "pt_0")];
    }

    function emptyWindStationEntry() {
        return { station: "", cash: 0 };
    }

    function normalizeWindStationEntry(raw, fallbackId, index) {
        const row = raw || {};
        const stationDefault =
            index != null && index >= 0 ? String(index + 1) : "";
        return {
            id: row.id || fallbackId || `ws_${Date.now()}`,
            station: String(row.station ?? stationDefault),
            cash: num(row.cash),
        };
    }

    /** Up to 3 wind stations per day — cash collected at each station. */
    function normalizeWindStations(windStations) {
        if (Array.isArray(windStations) && windStations.length > 0) {
            return windStations
                .slice(0, 3)
                .map((row, i) => normalizeWindStationEntry(row, `ws_${i}`, i));
        }
        return [normalizeWindStationEntry({ station: "1" }, "ws_0", 0)];
    }

    function emptyKenoStationEntry() {
        return { station: "", cash: 0 };
    }

    function normalizeKenoStationEntry(raw, fallbackId, index) {
        const row = raw || {};
        const stationDefault =
            index != null && index >= 0 ? String(index + 1) : "";
        return {
            id: row.id || fallbackId || `ks_${Date.now()}`,
            station: String(row.station ?? stationDefault),
            cash: num(row.cash),
        };
    }

    /** Up to 3 keno stations per day — cash collected at each station. */
    function normalizeKenoStations(kenoStations) {
        if (Array.isArray(kenoStations) && kenoStations.length > 0) {
            return kenoStations
                .slice(0, 3)
                .map((row, i) => normalizeKenoStationEntry(row, `ks_${i}`, i));
        }
        return [normalizeKenoStationEntry({ station: "1" }, "ks_0", 0)];
    }

    function normalizeFuelSale(raw) {
        const f = raw || {};
        const regular = num(f.regular);
        const midGrade = num(f.midGrade);
        const premium = num(f.premium);
        const diesel = num(f.diesel);
        const gradeSum = regular + midGrade + premium + diesel;
        return {
            gallons: gradeSum > 0 ? gradeSum : num(f.gallons),
            dollars: num(f.dollars),
            regular,
            midGrade,
            premium,
            diesel,
        };
    }

    function sumFuelGradeGallons(fuelSale) {
        const f = fuelSale || {};
        return num(f.regular) + num(f.midGrade) + num(f.premium) + num(f.diesel);
    }

    function defaultFuelSale() {
        return normalizeFuelSale({});
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
            customAmounts: {},
            monthAdjustments: [],
            closeNotes: "",
            closed: false,
            closedAt: null,
            closedBy: null,
            updatedAt: null,
        };
    }

    function isMonthClosed(month) {
        return !!(month && month.closed);
    }

    function normalizeMonthAdjustment(row) {
        return {
            id: row.id || "",
            description: row.description || "",
            amount: num(row.amount),
            kind: row.kind === "credit" ? "credit" : "expense",
        };
    }

    function monthAdjustmentsTotals(adjustments) {
        const rows = (adjustments || []).map(normalizeMonthAdjustment);
        let expense = 0;
        let credit = 0;
        rows.forEach((r) => {
            if (r.kind === "credit") credit += r.amount;
            else expense += r.amount;
        });
        return { rows, expense, credit };
    }

    function normalizeMonthDoc(month) {
        const base = defaultMonthDoc();
        const m = { ...base, ...(month || {}) };
        m.utilities = m.utilities || defaultUtilities();
        m.payroll = m.payroll || defaultPayroll();
        m.payrollLines = (m.payrollLines || []).map(normalizePayrollLine);
        m.receivables = m.receivables || [];
        m.customAmounts = normalizeCustomAmounts(m.customAmounts);
        m.monthAdjustments = (m.monthAdjustments || []).map(normalizeMonthAdjustment);
        m.closeNotes = m.closeNotes || "";
        m.closed = !!m.closed;
        m.closedAt = m.closedAt || null;
        m.closedBy = m.closedBy || null;
        m.salesTax = num(m.salesTax);
        m.accountant = num(m.accountant);
        return m;
    }

    function defaultDayDoc() {
        return {
            register1: defaultRegisterUnit(),
            register2: defaultRegisterUnit(),
            lottery: {
                shift1: emptyGamingShift(),
                shift2: emptyGamingShift(),
            },
            pulltabs: [],
            windStations: [],
            kenoStations: [],
            fuelSale: defaultFuelSale(),
            merchSale: 0,
            creditCard: 0,
            inHouseAccount: 0,
            waynePass: 0,
            lotteryPayOut: 0,
            pullTabPayout: 0,
            otherCashPayOut: 0,
            cashExpenses: [],
            checksAch: [],
            otherExpenses: [],
            customAmounts: {},
            cashReconciliation: defaultCashReconciliation(),
            closed: false,
            closedAt: null,
            closedBy: null,
            updatedAt: null,
        };
    }

    function isDayClosed(day) {
        return !!(day && day.closed);
    }

    function dayHasEntryData(rawDay, options) {
        if (!rawDay) return false;
        const hasGasStation = !!(options && options.hasGasStation);
        const dayId = rawDay._dayId || "2000-01-01";
        return dailySalesExpenseRow(dayId, rawDay, { hasGasStation }).hasData;
    }

    /** First open day for entry: today in month, else latest unclosed day, else day 1. */
    function defaultEntryDayId(monthId, daysById) {
        const map = daysById || {};
        const today = dayIdFromDate(new Date());
        if (today.startsWith(`${monthId}-`)) {
            if (!isDayClosed(map[today])) return today;
        }
        const n = daysInMonth(monthId);
        const anchor = parseMonthId(monthId);
        for (let d = n; d >= 1; d--) {
            const dt = new Date(anchor.getFullYear(), anchor.getMonth(), d);
            const id = dayIdFromDate(dt);
            if (!isDayClosed(map[id])) return id;
        }
        if (today.startsWith(`${monthId}-`)) return today;
        return `${monthId}-01`;
    }

    /** Closed days in calendar order for tile strip. */
    function listClosedDayIds(monthId, daysById) {
        const map = daysById || {};
        const n = daysInMonth(monthId);
        const anchor = parseMonthId(monthId);
        const ids = [];
        for (let d = 1; d <= n; d++) {
            const dt = new Date(anchor.getFullYear(), anchor.getMonth(), d);
            const id = dayIdFromDate(dt);
            if (isDayClosed(map[id])) ids.push(id);
        }
        return ids;
    }

    /** Month entry status for health strip / dashboards. */
    function booksHealthSummary(monthId, daysById, month, options) {
        const hasGasStation = !!(options && options.hasGasStation);
        const { rows } = dailySalesExpenseRows(monthId, daysById, { hasGasStation });
        const closedIds = new Set(listClosedDayIds(monthId, daysById));
        let daysWithData = 0;
        let unclosedWithData = 0;
        rows.forEach((row) => {
            if (!row.hasData) return;
            daysWithData += 1;
            if (!closedIds.has(row.dayId)) unclosedWithData += 1;
        });
        const receivables = (month && month.receivables) || [];
        return {
            daysInMonth: rows.length,
            daysWithData,
            daysClosed: closedIds.size,
            unclosedWithData,
            monthReceivablesLines: receivables.length,
            linkedReceivables: receivables.filter((r) => r.linkedReceivableId).length,
            manualReceivables: receivables.filter((r) => !r.linkedReceivableId).length,
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
        const entries = normalizePulltabs(day?.pulltabs, day?.pulltab);
        return entries.reduce(
            (acc, p) => ({
                cash: acc.cash + num(p.cash),
                winner: acc.winner + num(p.winner),
                overShort: acc.overShort + num(p.overShort),
            }),
            { cash: 0, winner: 0, overShort: 0 }
        );
    }

    function windStationDayTotal(day) {
        const entries = normalizeWindStations(day?.windStations);
        return entries.reduce((sum, row) => sum + num(row.cash), 0);
    }

    function kenoStationDayTotal(day) {
        const entries = normalizeKenoStations(day?.kenoStations);
        return entries.reduce((sum, row) => sum + num(row.cash), 0);
    }

    function fuelDayTotal(day) {
        const f = day.fuelSale || defaultFuelSale();
        return {
            gallons: num(f.gallons),
            dollars: num(f.dollars),
        };
    }

    function normalizeCustomAmounts(raw) {
        const out = {};
        if (!raw || typeof raw !== "object") return out;
        Object.keys(raw).forEach((key) => {
            out[key] = num(raw[key]);
        });
        return out;
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
            shift1: normalizeShiftRegister(src1.shift1),
            shift2: normalizeShiftRegister(src1.shift2),
        };
        d.register2 = {
            shift1: normalizeShiftRegister(src2.shift1),
            shift2: normalizeShiftRegister(src2.shift2),
        };
        delete d.register;
        d.lottery = {
            shift1: { ...emptyGamingShift(), ...(day.lottery?.shift1 || {}) },
            shift2: { ...emptyGamingShift(), ...(day.lottery?.shift2 || {}) },
        };
        d.pulltabs = normalizePulltabs(day.pulltabs, day.pulltab);
        delete d.pulltab;
        d.windStations = normalizeWindStations(day.windStations);
        d.kenoStations = normalizeKenoStations(day.kenoStations);
        d.fuelSale = normalizeFuelSale(day.fuelSale);
        d.merchSale = num(day.merchSale);
        d.creditCard = num(day.creditCard);
        d.inHouseAccount = num(day.inHouseAccount);
        d.waynePass = num(day.waynePass);
        d.lotteryPayOut = num(day.lotteryPayOut);
        if (num(day.waynePassLotteryPayOut) !== 0 && d.waynePass === 0 && d.lotteryPayOut === 0) {
            d.lotteryPayOut = num(day.waynePassLotteryPayOut);
        }
        d.pullTabPayout = num(day.pullTabPayout);
        d.otherCashPayOut = num(day.otherCashPayOut);
        d.cashExpenses = day.cashExpenses || [];
        d.checksAch = day.checksAch || [];
        d.otherExpenses = day.otherExpenses || [];
        d.customAmounts = normalizeCustomAmounts(day.customAmounts);
        d.cashReconciliation = normalizeCashReconciliation(day.cashReconciliation, d);
        d.closed = !!day.closed;
        d.closedAt = day.closedAt || null;
        d.closedBy = day.closedBy || null;
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
            { fieldId: "merchSale", label: "Merch sale", amount: num(agg.merchSale) },
            { fieldId: "registers", label: "Register — card", amount: num(agg.registerCard) },
            { fieldId: "registers", label: "Register — cash", amount: num(agg.registerCash) },
            { fieldId: "creditCard", label: "Credit card", amount: num(agg.creditCard) },
            { fieldId: "waynePass", label: "Wayne Pass", amount: num(agg.waynePass) },
            { fieldId: "fuel", label: "Fuel gallons", amount: num(agg.fuelGallons), format: "number" },
            ...(num(agg.fuelRegular) !== 0
                ? [{ fieldId: "fuel", label: "Fuel — regular (gal)", amount: num(agg.fuelRegular), format: "number" }]
                : []),
            ...(num(agg.fuelMidGrade) !== 0
                ? [{ fieldId: "fuel", label: "Fuel — mid grade (gal)", amount: num(agg.fuelMidGrade), format: "number" }]
                : []),
            ...(num(agg.fuelPremium) !== 0
                ? [{ fieldId: "fuel", label: "Fuel — premium (gal)", amount: num(agg.fuelPremium), format: "number" }]
                : []),
            ...(num(agg.fuelDiesel) !== 0
                ? [{ fieldId: "fuel", label: "Fuel — diesel (gal)", amount: num(agg.fuelDiesel), format: "number" }]
                : []),
            { fieldId: "fuel", label: "Fuel sales ($)", amount: num(agg.fuelDollars) },
            { fieldId: "pulltabs", label: "Pulltab", amount: num(agg.pulltabCash) },
            { fieldId: "windStations", label: "Wind station", amount: num(agg.windStationCash) },
            { fieldId: "kenoStations", label: "Keno station", amount: num(agg.kenoStationCash) },
            { fieldId: "lottery", label: "Lottery", amount: num(agg.lotteryCash) },
            { fieldId: "registerPayouts", label: "In house account", amount: num(agg.inHouseAccount) },
            { fieldId: "registerPayouts", label: "Lottery pay out", amount: num(agg.lotteryPayOut) },
            { fieldId: "registerPayouts", label: "Pull tab payout", amount: num(agg.pullTabPayout) },
            { fieldId: "registerPayouts", label: "Other cash pay out", amount: num(agg.otherCashPayOut) },
        ];
    }

    function salesBreakdownFromAggregate(agg) {
        const FC = window.OplixBooksFieldConfig;
        const config = agg?.booksFieldConfig;
        const hasGas = !!agg?.hasGasStation;
        let lines;
        if (agg.hasGasStation) {
            lines = gasSalesDetailBreakdownFromAggregate(agg);
        } else {
            lines = [
                { fieldId: "registers", label: "Register — card", amount: num(agg.registerCard) },
                { fieldId: "registers", label: "Register — cash", amount: num(agg.registerCash) },
                ...(num(agg.windStationCash) !== 0
                    ? [{ fieldId: "windStations", label: "Wind station", amount: num(agg.windStationCash) }]
                    : []),
                ...(num(agg.kenoStationCash) !== 0
                    ? [{ fieldId: "kenoStations", label: "Keno station", amount: num(agg.kenoStationCash) }]
                    : []),
            ];
        }
        lines = appendCustomBreakdownLines(lines, agg);
        return FC && config ? FC.filterBreakdownLines(lines, config, hasGas) : lines;
    }

    function appendCustomBreakdownLines(lines, agg) {
        const config = agg?.booksFieldConfig;
        if (!config?.customFields?.length) return lines;
        const totals = agg.customDailyTotals || {};
        config.customFields.forEach((cf) => {
            if (cf.group !== "daily" || cf.enabled === false) return;
            if (cf.category !== "sales" && cf.category !== "none") return;
            const amount = num(totals[cf.id]);
            if (amount === 0) return;
            lines.push({
                fieldId: cf.id,
                label: cf.label,
                amount,
                custom: true,
            });
        });
        return lines;
    }

    function appendCustomExpenseLines(lines, agg, month) {
        const config = agg?.booksFieldConfig;
        if (!config?.customFields?.length) return lines;
        const dayTotals = agg.customDailyTotals || {};
        const monthAmounts = normalizeCustomAmounts(month?.customAmounts);
        config.customFields.forEach((cf) => {
            if (cf.enabled === false || cf.category !== "expense") return;
            const amount =
                cf.group === "month" ? num(monthAmounts[cf.id]) : num(dayTotals[cf.id]);
            if (amount === 0) return;
            lines.push({
                category: cf.group === "month" ? "Monthly" : "Daily",
                description: cf.label,
                amount,
                custom: true,
            });
        });
        return lines;
    }

    /** Gas station chart slices — merch, register card, pump credit, and fuel (separate from total sales). */
    function gasSalesSlicesFromAggregate(agg) {
        return [
            { label: "Merch", amount: num(agg.merchSale) },
            { label: "Register card", amount: num(agg.registerCard) },
            { label: "Credit card", amount: num(agg.creditCard) },
            { label: "Fuel", amount: num(agg.fuelDollars) },
        ];
    }

    /** Line-level expenses for Books summary drill-down. */
    function buildExpenseDetail(monthDoc, daysById, agg) {
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

        (month.monthAdjustments || []).forEach((row) => {
            const adj = normalizeMonthAdjustment(row);
            if (adj.amount === 0 && !adj.description) return;
            lines.push({
                category: adj.kind === "credit" ? "Month credit" : "Month adjustment",
                description: adj.description || "(no description)",
                amount: adj.kind === "credit" ? -adj.amount : adj.amount,
            });
        });

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

        return appendCustomExpenseLines(lines, agg || {}, month).sort((a, b) => b.amount - a.amount);
    }

    /** Daily sales total — merch for gas; register card + cash for C Store. */
    function daySalesForAggregate(day, hasGasStation) {
        if (hasGasStation) {
            return num(day.merchSale);
        }
        const reg = registerDayTotal(day);
        return reg.card + reg.cash;
    }

    /** Status label for one day's cash reconciliation row. */
    function cashReconciliationDayStatus(summary) {
        if (summary.matched) return { label: "Reconciled", tone: "ok" };
        if (summary.countedTotal === 0 && summary.expectedTotal > 0) {
            return { label: "Not reconciled", tone: "unreconciled" };
        }
        if (
            Math.abs(summary.variance) < 0.005 &&
            summary.countedTotal > 0 &&
            !summary.allVerified
        ) {
            return { label: "Pending verification", tone: "pending" };
        }
        if (summary.deposit != null && !summary.depositMatch) {
            return { label: "Deposit variance", tone: "bad" };
        }
        if (Math.abs(summary.variance) >= 0.005) {
            return { label: "Variance", tone: "bad" };
        }
        return { label: "Variance", tone: "bad" };
    }

    function toSubmittedDate(v) {
        if (!v) return null;
        if (v instanceof Date) return v;
        if (typeof v.toDate === "function") return v.toDate();
        const d = new Date(v);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    /** Actual cash enclosed from a lottery shift close (Facilities → Lottery). */
    function lotteryFormCashEnclosed(form) {
        const s = form?.shiftSummary;
        if (!s) return 0;
        const raw = form.formData?.cashInHand;
        if (raw != null && String(raw).trim() !== "") return num(raw);
        if (s.overShort != null) return num(s.cashInBagNet) + num(s.overShort);
        return num(s.cashInBagNet);
    }

    /** Sum cash enclosed by day (`YYYY-MM-DD`) for forms in a month. */
    function lotteryFormsCashByDay(forms, monthId) {
        const prefix = `${monthId}-`;
        const byDay = {};
        (forms || []).forEach((form) => {
            const enclosed = lotteryFormCashEnclosed(form);
            if (enclosed === 0) return;
            const d = toSubmittedDate(form.submittedAt);
            if (!d) return;
            const dayId = dayIdFromDate(d);
            if (!dayId.startsWith(prefix)) return;
            byDay[dayId] = (byDay[dayId] || 0) + enclosed;
        });
        return byDay;
    }

    function lotteryReconSectionFromForms(existingSection, byDay) {
        const existingByDay = Object.fromEntries(
            (existingSection?.dailyRows || []).map((r) => [r.dayId, r])
        );
        const allDayIds = new Set([...Object.keys(byDay), ...Object.keys(existingByDay)]);
        if (!allDayIds.size) return existingSection || { dailyRows: [] };

        const dailyRows = [];
        let daysWithExpected = 0;
        let daysReconciled = 0;
        let daysNeedingAttention = 0;
        let totalExpected = 0;
        let totalCounted = 0;
        let totalVariance = 0;
        let totalExpectedDeposit = 0;
        let totalDeposit = 0;
        let totalDepositVariance = 0;

        [...allDayIds].sort().forEach((dayId) => {
            const formCash = num(byDay[dayId]);
            const existing = existingByDay[dayId];
            let section;

            if (formCash > 0) {
                const booksExpected = num(existing?.expectedTotal);
                const expectedTotal = booksExpected > 0 ? booksExpected : formCash;
                const countedTotal = formCash;
                const variance = countedTotal - expectedTotal;
                const expectedDeposit = formCash;
                const deposit = existing?.deposit ?? null;
                const depositVariance = deposit == null ? 0 : deposit - expectedDeposit;
                const totalsMatch = Math.abs(variance) < 0.005;
                const depositMatch = deposit == null || Math.abs(depositVariance) < 0.005;
                section = {
                    applicable: true,
                    expectedTotal,
                    countedTotal,
                    variance,
                    cashExpensesTotal: 0,
                    expectedDeposit,
                    deposit,
                    depositVariance,
                    depositMatch,
                    verifiedCount: existing?.verifiedCount || 0,
                    shiftCount: existing?.shiftCount || 1,
                    allVerified: existing?.allVerified ?? true,
                    totalsMatch,
                    matched: totalsMatch && depositMatch,
                    fromLotteryForm: true,
                };
            } else if (existing) {
                section = {
                    applicable: existing.applicable !== false,
                    expectedTotal: num(existing.expectedTotal),
                    countedTotal: num(existing.countedTotal),
                    variance: num(existing.variance),
                    cashExpensesTotal: num(existing.cashExpensesTotal),
                    expectedDeposit: num(existing.expectedDeposit),
                    deposit: existing.deposit ?? null,
                    depositVariance: num(existing.depositVariance),
                    depositMatch: existing.depositMatch !== false,
                    verifiedCount: existing.verifiedCount || 0,
                    shiftCount: existing.shiftCount || 0,
                    allVerified: existing.allVerified !== false,
                    totalsMatch: existing.totalsMatch !== false,
                    matched: existing.matched === true,
                };
            } else {
                return;
            }

            const status = cashReconciliationDayStatus(section);
            if (section.expectedTotal > 0 || section.countedTotal > 0) daysWithExpected += 1;
            if (section.matched) daysReconciled += 1;
            else daysNeedingAttention += 1;

            totalExpected += section.expectedTotal;
            totalCounted += section.countedTotal;
            totalVariance += section.variance;
            totalExpectedDeposit += section.expectedDeposit;
            if (section.deposit != null) {
                totalDeposit += section.deposit;
                totalDepositVariance += section.depositVariance;
            }

            dailyRows.push({ dayId, ...section, status });
        });

        return {
            dailyRows,
            daysWithExpected,
            daysReconciled,
            daysNeedingAttention,
            totalExpected,
            totalCounted,
            totalVariance,
            totalCashExpenses: 0,
            totalExpectedDeposit,
            totalDeposit,
            totalDepositVariance,
        };
    }

    /**
     * Merge lottery shift closes (cash enclosed) into Summary aggregate.
     * Prefers Facilities → Lottery forms over Daily sheet lottery cash when forms exist.
     */
    function enrichAggregateWithLotteryForms(aggregate, forms, monthId) {
        const byDay = lotteryFormsCashByDay(forms, monthId);
        const formMonthTotal = Object.values(byDay).reduce((s, v) => s + v, 0);
        if (formMonthTotal <= 0) return aggregate;

        const cr = aggregate.cashReconciliation || aggregateCashReconciliation({});
        const lottery = lotteryReconSectionFromForms(cr.lottery, byDay);

        return {
            ...aggregate,
            lotteryCash: formMonthTotal,
            lotteryCashFromForms: true,
            cashReconciliation: {
                ...cr,
                lottery,
            },
        };
    }

    /** Gas station total revenue (all streams) — for display only. */
    function gasTotalRevenue(merchSale, creditCard, fuelDollars, pulltabCash) {
        return num(merchSale) + num(creditCard) + num(fuelDollars) + num(pulltabCash);
    }

    /** Gas station revenue counted toward net — merch + pulltab only; pump credit and fuel excluded. */
    function gasRevenueForNet(merchSale, pulltabCash) {
        return num(merchSale) + num(pulltabCash);
    }

    /** One calendar day's sales and expenses from Daily books. */
    function dailySalesExpenseRow(dayId, rawDay, hasGasStation) {
        const empty = {
            dayId,
            sales: 0,
            totalRevenue: 0,
            expenses: 0,
            net: 0,
            cashExpense: 0,
            checksAch: 0,
            otherExpense: 0,
            fuelDollars: 0,
            fuelGallons: 0,
            merchSale: 0,
            creditCard: 0,
            registerCard: 0,
            registerCash: 0,
            hasData: false,
        };
        if (!rawDay) return empty;

        const day = normalizeDayDoc({ ...rawDay, _dayId: dayId });
        const reg = registerDayTotal(day);
        const fuel = fuelDayTotal(day);
        const pull = pulltabDayTotal(day);
        const dayMerch = num(day.merchSale);
        const dayCredit = num(day.creditCard);
        const dayCash = sumLines(day.cashExpenses, "amount") + registerShiftPayoutsExpenseTotal(day);
        const dayChecks = sumLines(day.checksAch, "amount");
        const dayOther = sumLines(day.otherExpenses, "amount");
        const expenses = dayCash + dayChecks + dayOther;

        let sales;
        let totalRevenue;
        let netRevenue;
        if (hasGasStation) {
            sales = dayMerch;
            totalRevenue = gasTotalRevenue(dayMerch, dayCredit, fuel.dollars, pull.cash);
            netRevenue = gasRevenueForNet(dayMerch, pull.cash);
        } else {
            sales = reg.card + reg.cash;
            totalRevenue = sales;
            netRevenue = sales;
        }

        const hasData =
            totalRevenue !== 0 ||
            expenses !== 0 ||
            fuel.gallons !== 0 ||
            reg.overShort !== 0 ||
            num(day.inHouseAccount) !== 0 ||
            num(day.waynePass) !== 0 ||
            num(day.lotteryPayOut) !== 0 ||
            num(day.pullTabPayout) !== 0 ||
            num(day.otherCashPayOut) !== 0 ||
            registerShiftPayoutsTotal(day) !== 0;

        return {
            dayId,
            sales,
            totalRevenue,
            netRevenue,
            expenses,
            net: netRevenue - expenses,
            cashExpense: dayCash,
            checksAch: dayChecks,
            otherExpense: dayOther,
            fuelDollars: fuel.dollars,
            fuelGallons: fuel.gallons,
            merchSale: dayMerch,
            creditCard: dayCredit,
            registerCard: reg.card,
            registerCash: reg.cash,
            hasData,
        };
    }

    /** Every calendar day in a month with daily sales and expense totals. */
    function dailySalesExpenseRows(monthId, daysById, options) {
        const hasGasStation = !!(options && options.hasGasStation);
        const count = daysInMonth(monthId);
        const anchor = parseMonthId(monthId);
        const rows = [];

        for (let d = 1; d <= count; d++) {
            const dayId = dayIdFromDate(new Date(anchor.getFullYear(), anchor.getMonth(), d));
            rows.push(dailySalesExpenseRow(dayId, daysById?.[dayId], hasGasStation));
        }

        const totals = rows.reduce(
            (acc, row) => {
                if (!row.hasData) return acc;
                acc.daysWithData += 1;
                acc.sales += row.sales;
                acc.totalRevenue += row.totalRevenue;
                acc.expenses += row.expenses;
                acc.net += row.net;
                acc.cashExpense += row.cashExpense;
                acc.checksAch += row.checksAch;
                acc.otherExpense += row.otherExpense;
                acc.fuelDollars += row.fuelDollars;
                acc.fuelGallons += row.fuelGallons;
                acc.merchSale += row.merchSale;
                acc.creditCard += row.creditCard;
                return acc;
            },
            {
                daysWithData: 0,
                sales: 0,
                totalRevenue: 0,
                expenses: 0,
                net: 0,
                cashExpense: 0,
                checksAch: 0,
                otherExpense: 0,
                fuelDollars: 0,
                fuelGallons: 0,
                merchSale: 0,
                creditCard: 0,
            }
        );

        return { rows, totals };
    }

    /** Aggregate one month (month doc + all days) for Books summary. */
    function aggregateMonth(monthDoc, daysById, options) {
        const month = monthDoc || defaultMonthDoc();
        const days = Object.values(daysById || {});
        const hasGasStation = !!(options && options.hasGasStation);
        const booksFieldConfig = options?.booksFieldConfig || null;

        let registerCard = 0;
        let registerCash = 0;
        let registerOverShort = 0;
        let lotteryCash = 0;
        let lotteryOverShort = 0;
        let pulltabCash = 0;
        let pulltabWinner = 0;
        let pulltabOverShort = 0;
        let windStationCash = 0;
        let kenoStationCash = 0;
        let cashExpense = 0;
        let checksAch = 0;
        let otherExpense = 0;
        let fuelGallons = 0;
        let fuelDollars = 0;
        let fuelRegular = 0;
        let fuelMidGrade = 0;
        let fuelPremium = 0;
        let fuelDiesel = 0;
        let merchSale = 0;
        let creditCard = 0;
        let inHouseAccount = 0;
        let waynePass = 0;
        let lotteryPayOut = 0;
        let pullTabPayout = 0;
        let otherCashPayOut = 0;

        const dailySeries = [];

        const customDailyTotals = {};

        days.forEach((day) => {
            const normalized = normalizeDayDoc(day);
            const reg = registerDayTotal(normalized);
            const lot = lotteryDayTotal(normalized);
            const pull = pulltabDayTotal(normalized);
            const wind = windStationDayTotal(normalized);
            const keno = kenoStationDayTotal(normalized);
            const fuel = fuelDayTotal(normalized);
            const dayMerch = num(normalized.merchSale);
            const dayCredit = num(normalized.creditCard);
            const dayCash = sumLines(normalized.cashExpenses, "amount");
            const dayShiftPayOutExpense = registerShiftPayoutsExpenseTotal(normalized);
            const dayChecks = sumLines(normalized.checksAch, "amount");
            const dayOther = sumLines(normalized.otherExpenses, "amount");

            registerCard += reg.card;
            registerCash += reg.cash;
            registerOverShort += reg.overShort;
            lotteryCash += lot.cash;
            lotteryOverShort += lot.overShort;
            pulltabCash += pull.cash;
            pulltabWinner += pull.winner;
            pulltabOverShort += pull.overShort;
            windStationCash += wind;
            kenoStationCash += keno;
            fuelGallons += fuel.gallons;
            fuelDollars += fuel.dollars;
            const fuelSale = normalized.fuelSale || defaultFuelSale();
            fuelRegular += num(fuelSale.regular);
            fuelMidGrade += num(fuelSale.midGrade);
            fuelPremium += num(fuelSale.premium);
            fuelDiesel += num(fuelSale.diesel);
            merchSale += dayMerch;
            creditCard += dayCredit;
            inHouseAccount += num(normalized.inHouseAccount);
            waynePass += num(normalized.waynePass);
            lotteryPayOut += num(normalized.lotteryPayOut);
            pullTabPayout += num(normalized.pullTabPayout);
            otherCashPayOut += num(normalized.otherCashPayOut);
            cashExpense += dayCash + dayShiftPayOutExpense;
            checksAch += dayChecks;
            otherExpense += dayOther;

            (booksFieldConfig?.customFields || []).forEach((cf) => {
                if (cf.group !== "daily" || cf.enabled === false) return;
                const amt = num(normalized.customAmounts?.[cf.id]);
                customDailyTotals[cf.id] = (customDailyTotals[cf.id] || 0) + amt;
            });

            dailySeries.push({
                dayId: normalized._dayId || day._dayId,
                sales: daySalesForAggregate(normalized, hasGasStation),
                fuelGallons: fuel.gallons,
                fuelDollars: fuel.dollars,
                merchSale: dayMerch,
                creditCard: dayCredit,
                expenses: dayCash + dayChecks + dayOther,
                overShort: reg.overShort + lot.overShort + pull.overShort,
            });
        });

        const monthCustomAmounts = normalizeCustomAmounts(month.customAmounts);
        let customExpenseTotal = 0;
        (booksFieldConfig?.customFields || []).forEach((cf) => {
            if (cf.enabled === false || cf.category !== "expense") return;
            if (cf.group === "month") {
                customExpenseTotal += num(monthCustomAmounts[cf.id]);
            } else {
                customExpenseTotal += num(customDailyTotals[cf.id]);
            }
        });

        const utilities = month.utilities || defaultUtilities();
        const utilitiesTotal = utilitiesTotalFrom(utilities);
        const payroll = month.payroll || defaultPayroll();
        const payrollLines = (month.payrollLines || []).map(normalizePayrollLine);
        const payrollTotal = payrollTotalFrom(month);
        const receivablesTotal = sumLines(month.receivables, "amount");
        const monthAdj = monthAdjustmentsTotals(month.monthAdjustments);

        const sales = hasGasStation ? merchSale : registerCard + registerCash;
        const totalRevenue = hasGasStation
            ? gasTotalRevenue(merchSale, creditCard, fuelDollars, pulltabCash)
            : sales;
        const netRevenue = hasGasStation
            ? gasRevenueForNet(merchSale, pulltabCash)
            : sales;
        const expenses =
            cashExpense +
            checksAch +
            otherExpense +
            utilitiesTotal +
            payrollTotal +
            num(month.salesTax) +
            num(month.accountant) +
            customExpenseTotal +
            monthAdj.expense;

        const aggCore = {
            hasGasStation,
            booksFieldConfig,
            customDailyTotals,
            sales,
            registerCard,
            registerCash,
            registerOverShort,
            lotteryCash,
            lotteryOverShort,
            pulltabCash,
            pulltabWinner,
            pulltabOverShort,
            windStationCash,
            kenoStationCash,
            fuelGallons,
            fuelDollars,
            fuelRegular,
            fuelMidGrade,
            fuelPremium,
            fuelDiesel,
            merchSale,
            creditCard,
            inHouseAccount,
            waynePass,
            lotteryPayOut,
            pullTabPayout,
            otherCashPayOut,
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
            monthAdjustments: monthAdj.rows,
            monthAdjustmentsExpense: monthAdj.expense,
            monthAdjustmentsCredit: monthAdj.credit,
            salesTax: num(month.salesTax),
            accountant: num(month.accountant),
            expenses,
            net: netRevenue + receivablesTotal + monthAdj.credit - expenses,
            totalRevenue,
            netRevenue,
            totalOverShort: registerOverShort + lotteryOverShort + pulltabOverShort,
            dailySeries,
            dayCount: days.length,
        };

        return {
            ...aggCore,
            salesBreakdown: salesBreakdownFromAggregate(aggCore),
            expenseDetail: buildExpenseDetail(month, daysById, aggCore),
            cashReconciliation: aggregateCashReconciliation(daysById),
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
            { key: "creditCard", label: "Credit card" },
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

    function emptyPayOutLine(id) {
        return { id: id || "", description: "", amount: 0 };
    }

    function normalizePayOuts(raw, legacyPayOut) {
        let lines;
        if (Array.isArray(raw)) {
            lines = raw
                .map((line) => ({
                    id: String(line?.id || ""),
                    description: String(line?.description || ""),
                    amount: num(line?.amount),
                }))
                .filter((line) => line.id);
        } else {
            const legacy = num(legacyPayOut);
            lines = legacy !== 0 ? [{ id: "legacy", description: "", amount: legacy }] : [];
        }
        return lines.filter(
            (line) => num(line.amount) !== 0 || String(line.description || "").trim() !== ""
        );
    }

    function pruneEmptyPayOuts(payOuts) {
        return (payOuts || []).filter(
            (line) => num(line.amount) !== 0 || String(line.description || "").trim() !== ""
        );
    }

    function sumPayOuts(payOuts) {
        return (payOuts || []).reduce((total, line) => total + num(line.amount), 0);
    }

    function payOutsHaveActivity(payOuts) {
        return (payOuts || []).some(
            (line) => num(line.amount) !== 0 || String(line.description || "").trim() !== ""
        );
    }

    function emptyCashReconShift() {
        return { countedCash: 0, payOuts: [], verified: false, note: "" };
    }

    function normalizeReconEntry(raw) {
        const src = raw || {};
        return {
            countedCash: num(src.countedCash),
            payOuts: normalizePayOuts(src.payOuts, src.payOut),
            verified: src.verified === true,
            note: src.note || "",
        };
    }

    function defaultCashReconRegisterUnit() {
        return {
            shift1: emptyCashReconShift(),
            shift2: emptyCashReconShift(),
        };
    }

    function defaultCashReconciliation() {
        return {
            register1: defaultCashReconRegisterUnit(),
            register2: defaultCashReconRegisterUnit(),
            lottery: defaultCashReconRegisterUnit(),
            pulltabs: {},
            windStations: {},
            kenoStations: {},
            dayDeposit: null,
            lotteryDeposit: null,
            pulltabDeposit: null,
            windDeposit: null,
            kenoDeposit: null,
            note: "",
        };
    }

    function normalizeCashReconciliation(raw, day) {
        const base = defaultCashReconciliation();
        if (!raw) raw = {};
        ["register1", "register2"].forEach((regKey) => {
            ["shift1", "shift2"].forEach((sh) => {
                base[regKey][sh] = normalizeReconEntry(raw[regKey]?.[sh]);
            });
        });
        ["shift1", "shift2"].forEach((sh) => {
            base.lottery[sh] = normalizeReconEntry(raw.lottery?.[sh]);
        });
        const pulltabs = day ? normalizePulltabs(day.pulltabs, day.pulltab) : [];
        pulltabs.forEach((pt) => {
            base.pulltabs[pt.id] = normalizeReconEntry(raw.pulltabs?.[pt.id]);
        });
        const windRows = day ? normalizeWindStations(day.windStations) : [];
        windRows.forEach((ws) => {
            base.windStations[ws.id] = normalizeReconEntry(raw.windStations?.[ws.id]);
        });
        const kenoRows = day ? normalizeKenoStations(day.kenoStations) : [];
        kenoRows.forEach((ks) => {
            base.kenoStations[ks.id] = normalizeReconEntry(raw.kenoStations?.[ks.id]);
        });
        const depositFields = [
            "dayDeposit",
            "lotteryDeposit",
            "pulltabDeposit",
            "windDeposit",
            "kenoDeposit",
        ];
        depositFields.forEach((f) => {
            base[f] = raw[f] == null || raw[f] === "" ? null : num(raw[f]);
        });
        base.note = raw.note || "";
        return base;
    }

    /** Total cash paid from registers on a day (Daily sheet → Cash expense lines). */
    function dayManualCashExpensesTotal(day) {
        return sumLines(normalizeDayDoc(day).cashExpenses, "amount");
    }

    /** Per-shift register payouts marked as store expense (Daily sheet → register shifts). */
    function registerShiftPayoutsExpenseTotal(day) {
        let total = 0;
        const normalized = normalizeDayDoc(day);
        ["register1", "register2"].forEach((regKey) => {
            ["shift1", "shift2"].forEach((sh) => {
                const shift = normalized[regKey]?.[sh] || {};
                if (shift.cashPayOutExpense) total += num(shift.cashPayOut);
            });
        });
        return total;
    }

    /** All per-shift register payouts on the Daily sheet. */
    function registerShiftPayoutsTotal(day) {
        let total = 0;
        const normalized = normalizeDayDoc(day);
        ["register1", "register2"].forEach((regKey) => {
            ["shift1", "shift2"].forEach((sh) => {
                total += num(normalized[regKey]?.[sh]?.cashPayOut);
            });
        });
        return total;
    }

    function dayCashExpensesTotal(day) {
        return dayManualCashExpensesTotal(day) + registerShiftPayoutsExpenseTotal(day);
    }

    /** Track-only register payouts — recorded on Daily sheet but do not reduce expected cash on reconciliation. */
    function dayRegisterPayoutsTrackOnlyTotal(day) {
        const d = normalizeDayDoc(day);
        return (
            num(d.inHouseAccount) +
            num(d.lotteryPayOut) +
            num(d.pullTabPayout)
        );
    }

    /** Register payouts that reduce expected deposit (other cash pay out only). */
    function dayRegisterPayoutsReconTotal(day) {
        return num(normalizeDayDoc(day).otherCashPayOut);
    }

    /** All register payout lines on the Daily sheet (track-only + recon). */
    function dayRegisterPayoutsTotal(day) {
        return dayRegisterPayoutsTrackOnlyTotal(day) + dayRegisterPayoutsReconTotal(day);
    }

    /** Expected register cash for one shift — cash sale minus pay out from Daily sheet. */
    function expectedRegisterCash(day, regKey, shiftKey) {
        const sh = normalizeShiftRegister(day?.[regKey]?.[shiftKey]);
        return Math.max(0, num(sh.cashSale) - num(sh.cashPayOut));
    }

    function registerShiftGrossCash(day, regKey, shiftKey) {
        const sh = day?.[regKey]?.[shiftKey] || {};
        return num(sh.cashSale);
    }

    function expectedLotteryCash(day, shiftKey) {
        return num(day?.lottery?.[shiftKey]?.cash);
    }

    function expectedPulltabCash(pt) {
        return num(pt.cash);
    }

    /**
     * Register recon: expected deposit is register cash only.
     * Per-shift pay outs are already in each row's expected (cash sale − pay out).
     * Day-level gas register payouts (in house, lottery, pull tab, other) also reduce deposit.
     * Office cash expense lines are P&L only — they do not reduce register expected deposit.
     */
    function finalizeRegisterReconSection(
        section,
        grossCash,
        cashExpensesTotal,
        dailyRegisterPayoutsRecon,
        dailyRegisterPayoutsTrackOnly
    ) {
        const allRegisterPayouts = dailyRegisterPayoutsRecon + dailyRegisterPayoutsTrackOnly;
        // cashExpensesTotal is office cash (separate pot) — not subtracted from register deposit.
        const expectedNet = grossCash - allRegisterPayouts;
        section.expectedGross = grossCash;
        section.expectedNetCash = expectedNet;
        section.cashExpensesTotal = 0;
        section.officeCashExpensesTotal = cashExpensesTotal || 0;
        section.dailyRegisterPayouts = dailyRegisterPayoutsRecon;
        section.dailyRegisterPayoutsTrackOnly = dailyRegisterPayoutsTrackOnly;
        section.dailyRegisterPayoutsAll = allRegisterPayouts;
        section.expectedDeposit = expectedNet;

        const deposit = section.deposit;
        section.depositVariance = deposit == null ? 0 : deposit - expectedNet;
        section.depositMatch = deposit == null || Math.abs(section.depositVariance) < 0.005;

        const netVariance = section.receivedTotal - expectedNet;
        section.netVariance = netVariance;
        section.rowTotalsMatch = section.totalsMatch;
        section.variance = deposit != null ? section.depositVariance : netVariance;

        section.matched =
            section.applicable &&
            section.allVerified &&
            (deposit != null
                ? section.depositMatch
                : Math.abs(netVariance) < 0.005);

        return section;
    }

    /** True when Daily sheet has register shift data worth reconciling. */
    function registerShiftHasBooksData(day, regKey, shiftKey) {
        const sh = day?.[regKey]?.[shiftKey] || {};
        return num(sh.cashSale) !== 0 || num(sh.overShort) !== 0 || num(sh.cashPayOut) !== 0;
    }

    function lotteryShiftHasBooksData(day, shiftKey) {
        const sh = day?.lottery?.[shiftKey] || {};
        return num(sh.cash) !== 0 || num(sh.overShort) !== 0;
    }

    function pulltabRowHasBooksData(pt) {
        return (
            String(pt.ticketNumber || "").trim() !== "" ||
            num(pt.cash) !== 0 ||
            num(pt.winner) !== 0 ||
            num(pt.overShort) !== 0
        );
    }

    function windRowHasBooksData(ws) {
        return num(ws.cash) !== 0;
    }

    function kenoRowHasBooksData(ks) {
        return num(ks.cash) !== 0;
    }

    /** Keep rows with Daily sheet data, or in-progress reconciliation entries. */
    function filterReconRows(rows, hasBooksData) {
        return (rows || []).filter((row) => {
            const booksEntered = hasBooksData(row);
            const hasReconActivity =
                num(row.counted) !== 0 ||
                payOutsHaveActivity(row.payOuts) ||
                row.verified ||
                String(row.note || "").trim() !== "";
            return booksEntered || hasReconActivity;
        });
    }

    function summarizeReconSection(rows, depositAmount, expectedDeposit, cashExpensesTotal) {
        let expectedTotal = 0;
        let receivedTotal = 0;
        let payOutTotal = 0;
        let countedTotal = 0;
        let verifiedCount = 0;
        const rowCount = rows.length;

        rows.forEach((row) => {
            const received = num(row.counted);
            const isRegister = row.kind === "register";
            const payOut = isRegister ? num(row.payOut) : sumPayOuts(row.payOuts);
            expectedTotal += num(row.expected);
            receivedTotal += received;
            payOutTotal += payOut;
            countedTotal += isRegister ? received : received + payOut;
            if (row.verified) verifiedCount += 1;
        });

        const variance = countedTotal - expectedTotal;
        const totalsMatch = Math.abs(variance) < 0.005;
        const deposit = depositAmount == null ? null : num(depositAmount);
        const depositVariance = deposit == null ? 0 : deposit - expectedDeposit;
        const depositMatch = deposit == null || Math.abs(depositVariance) < 0.005;
        const allVerified = rowCount === 0 || verifiedCount === rowCount;
        const applicable =
            rowCount > 0 &&
            (expectedTotal > 0 ||
                countedTotal > 0 ||
                deposit != null ||
                verifiedCount > 0 ||
                rows.some((r) => r.note));
        const matched =
            !applicable || (totalsMatch && depositMatch && allVerified);

        return {
            rows,
            expectedTotal,
            receivedTotal,
            payOutTotal,
            countedTotal,
            variance,
            cashExpensesTotal: cashExpensesTotal || 0,
            expectedDeposit,
            deposit,
            depositVariance,
            depositMatch,
            verifiedCount,
            shiftCount: rowCount,
            allVerified,
            totalsMatch,
            applicable,
            matched,
        };
    }

    /** Cash reconciliation totals for a day — register, lottery, pulltab, and wind. */
    function cashReconciliationSummary(day) {
        const normalized = normalizeDayDoc(day);
        const recon = normalized.cashReconciliation;

        const registerRowsAll = [];
        ["register1", "register2"].forEach((regKey, regIdx) => {
            ["shift1", "shift2"].forEach((sh, shIdx) => {
                const shift = normalized[regKey][sh];
                const expectedGross = registerShiftGrossCash(normalized, regKey, sh);
                const payOut = num(shift.cashPayOut);
                const expected = expectedRegisterCash(normalized, regKey, sh);
                const entry = recon[regKey][sh];
                const counted = num(entry.countedCash);
                registerRowsAll.push({
                    kind: "register",
                    regKey,
                    shiftKey: sh,
                    rowLabel: `Register ${regIdx + 1}`,
                    shiftLabel: `Shift ${shIdx + 1}`,
                    namePrefix: `cr_${regKey}_${sh}`,
                    expectedGross,
                    expected,
                    counted,
                    payOuts: entry.payOuts || [],
                    payOut,
                    cashPayOutExpense: !!shift.cashPayOutExpense,
                    variance: counted - expected,
                    verified: entry.verified === true,
                    note: entry.note || "",
                });
            });
        });
        const registerRows = filterReconRows(registerRowsAll, (row) =>
            registerShiftHasBooksData(normalized, row.regKey, row.shiftKey)
        );

        const lotteryRowsAll = [];
        ["shift1", "shift2"].forEach((sh, shIdx) => {
            const expected = expectedLotteryCash(normalized, sh);
            const entry = recon.lottery[sh];
            const counted = num(entry.countedCash);
            const payOuts = entry.payOuts || [];
            const payOut = sumPayOuts(payOuts);
            lotteryRowsAll.push({
                kind: "lottery",
                shiftKey: sh,
                rowLabel: "Lottery",
                shiftLabel: `Shift ${shIdx + 1}`,
                namePrefix: `cr_lottery_${sh}`,
                expected,
                counted,
                payOuts,
                payOut,
                variance: counted + payOut - expected,
                verified: entry.verified === true,
                note: entry.note || "",
            });
        });
        const lotteryRows = filterReconRows(lotteryRowsAll, (row) =>
            lotteryShiftHasBooksData(normalized, row.shiftKey)
        );

        const pulltabRowsAll = normalized.pulltabs.map((pt, idx) => {
            const entry = recon.pulltabs[pt.id] || emptyCashReconShift();
            const expected = expectedPulltabCash(pt);
            const counted = num(entry.countedCash);
            const payOuts = entry.payOuts || [];
            const payOut = sumPayOuts(payOuts);
            const ticket = String(pt.ticketNumber || "").trim();
            return {
                kind: "pulltab",
                rowId: pt.id,
                rowLabel: `Machine ${idx + 1}`,
                shiftLabel: ticket ? `#${ticket}` : "—",
                namePrefix: `cr_pt_${pt.id}`,
                expected,
                counted,
                payOuts,
                payOut,
                variance: counted + payOut - expected,
                verified: entry.verified === true,
                note: entry.note || "",
            };
        });
        const pulltabRows = filterReconRows(pulltabRowsAll, (row) => {
            const pt = normalized.pulltabs.find((p) => p.id === row.rowId);
            return pt ? pulltabRowHasBooksData(pt) : false;
        });

        const windRowsAll = normalized.windStations.map((ws, idx) => {
            const entry = recon.windStations[ws.id] || emptyCashReconShift();
            const expected = num(ws.cash);
            const counted = num(entry.countedCash);
            const payOuts = entry.payOuts || [];
            const payOut = sumPayOuts(payOuts);
            const station = String(ws.station || "").trim() || String(idx + 1);
            return {
                kind: "wind",
                rowId: ws.id,
                rowLabel: `Station ${station}`,
                shiftLabel: "Cash",
                namePrefix: `cr_ws_${ws.id}`,
                expected,
                counted,
                payOuts,
                payOut,
                variance: counted + payOut - expected,
                verified: entry.verified === true,
                note: entry.note || "",
            };
        });
        const windRows = filterReconRows(windRowsAll, (row) => {
            const ws = normalized.windStations.find((w) => w.id === row.rowId);
            return ws ? windRowHasBooksData(ws) : false;
        });

        const kenoRowsAll = normalized.kenoStations.map((ks, idx) => {
            const entry = recon.kenoStations[ks.id] || emptyCashReconShift();
            const expected = num(ks.cash);
            const counted = num(entry.countedCash);
            const payOuts = entry.payOuts || [];
            const payOut = sumPayOuts(payOuts);
            const station = String(ks.station || "").trim() || String(idx + 1);
            return {
                kind: "keno",
                rowId: ks.id,
                rowLabel: `Station ${station}`,
                shiftLabel: "Cash",
                namePrefix: `cr_ks_${ks.id}`,
                expected,
                counted,
                payOuts,
                payOut,
                variance: counted + payOut - expected,
                verified: entry.verified === true,
                note: entry.note || "",
            };
        });
        const kenoRows = filterReconRows(kenoRowsAll, (row) => {
            const ks = normalized.kenoStations.find((k) => k.id === row.rowId);
            return ks ? kenoRowHasBooksData(ks) : false;
        });

        const officeCashExpenses = dayManualCashExpensesTotal(normalized);
        const dailyRegisterPayoutsRecon = dayRegisterPayoutsReconTotal(normalized);
        const dailyRegisterPayoutsTrackOnly = dayRegisterPayoutsTrackOnlyTotal(normalized);
        const registerGrossCash = registerRows.reduce((s, r) => s + num(r.expectedGross), 0);
        const registerNetExpected = registerRows.reduce((s, r) => s + r.expected, 0);
        // Office cash expense lines are a separate pot — P&L only, not register deposit.
        const registerExpectedNet =
            registerRows.length > 0
                ? registerNetExpected - dailyRegisterPayoutsRecon - dailyRegisterPayoutsTrackOnly
                : 0;

        const register = finalizeRegisterReconSection(
            summarizeReconSection(
                registerRows,
                registerRows.length > 0 ? recon.dayDeposit : null,
                registerExpectedNet,
                0
            ),
            registerGrossCash,
            officeCashExpenses,
            dailyRegisterPayoutsRecon,
            dailyRegisterPayoutsTrackOnly
        );
        const lotteryExpected = lotteryRows.reduce((s, r) => s + r.expected, 0);
        const lottery = summarizeReconSection(
            lotteryRows,
            lotteryRows.length > 0 ? recon.lotteryDeposit : null,
            lotteryExpected,
            0
        );
        const pulltabExpected = pulltabRows.reduce((s, r) => s + r.expected, 0);
        const pulltab = summarizeReconSection(
            pulltabRows,
            pulltabRows.length > 0 ? recon.pulltabDeposit : null,
            pulltabExpected,
            0
        );
        const windExpected = windRows.reduce((s, r) => s + r.expected, 0);
        const wind = summarizeReconSection(
            windRows,
            windRows.length > 0 ? recon.windDeposit : null,
            windExpected,
            0
        );
        const kenoExpected = kenoRows.reduce((s, r) => s + r.expected, 0);
        const keno = summarizeReconSection(
            kenoRows,
            kenoRows.length > 0 ? recon.kenoDeposit : null,
            kenoExpected,
            0
        );

        const applicableSections = [register, lottery, pulltab, wind, keno].filter(
            (s) => s.applicable
        );
        const matched =
            applicableSections.length === 0 || applicableSections.every((s) => s.matched);

        return {
            register,
            lottery,
            pulltab,
            wind,
            keno,
            matched,
            // Legacy register aliases
            rows: registerRows,
            expectedTotal: register.expectedTotal,
            countedTotal: register.countedTotal,
            variance: register.variance,
            cashExpensesTotal: register.cashExpensesTotal,
            expectedDeposit: register.expectedDeposit,
            deposit: register.deposit,
            depositVariance: register.depositVariance,
            depositMatch: register.depositMatch,
            verifiedCount: register.verifiedCount,
            shiftCount: register.shiftCount,
            allVerified: register.allVerified,
        };
    }

    function aggregateReconCategory(daysById, pickSection) {
        const dailyRows = [];
        let daysWithExpected = 0;
        let daysReconciled = 0;
        let daysNeedingAttention = 0;
        let totalExpected = 0;
        let totalCounted = 0;
        let totalVariance = 0;
        let totalCashExpenses = 0;
        let totalExpectedDeposit = 0;
        let totalDeposit = 0;
        let totalDepositVariance = 0;

        Object.entries(daysById || {})
            .sort(([a], [b]) => a.localeCompare(b))
            .forEach(([dayId, rawDay]) => {
                const day = normalizeDayDoc({ ...rawDay, _dayId: dayId });
                const section = pickSection(cashReconciliationSummary(day));
                if (!section.applicable) return;

                const hasExpected = section.expectedTotal > 0;
                const hasActivity =
                    section.countedTotal > 0 ||
                    section.deposit != null ||
                    section.verifiedCount > 0;

                if (!hasExpected && !hasActivity) return;

                const status = cashReconciliationDayStatus(section);
                if (hasExpected) daysWithExpected += 1;
                if (section.matched) daysReconciled += 1;
                else daysNeedingAttention += 1;

                totalExpected += section.expectedTotal;
                totalCounted += section.countedTotal;
                totalVariance += section.variance;
                totalCashExpenses += section.cashExpensesTotal || 0;
                totalExpectedDeposit += section.expectedDeposit;
                if (section.deposit != null) {
                    totalDeposit += section.deposit;
                    totalDepositVariance += section.depositVariance;
                }

                dailyRows.push({
                    dayId,
                    ...section,
                    status,
                });
            });

        return {
            dailyRows,
            daysWithExpected,
            daysReconciled,
            daysNeedingAttention,
            totalExpected,
            totalCounted,
            totalVariance,
            totalCashExpenses,
            totalExpectedDeposit,
            totalDeposit,
            totalDepositVariance,
        };
    }

    /** Month-level cash reconciliation rollup from daily books entries. */
    function aggregateCashReconciliation(daysById) {
        const register = aggregateReconCategory(daysById, (s) => s.register);
        const lottery = aggregateReconCategory(daysById, (s) => s.lottery);
        const pulltab = aggregateReconCategory(daysById, (s) => s.pulltab);
        const wind = aggregateReconCategory(daysById, (s) => s.wind);
        const keno = aggregateReconCategory(daysById, (s) => s.keno);

        return {
            register,
            lottery,
            pulltab,
            wind,
            keno,
            // Legacy register aliases
            dailyRows: register.dailyRows,
            daysWithBooksCash: register.daysWithExpected,
            daysReconciled: register.daysReconciled,
            daysNeedingAttention: register.daysNeedingAttention,
            totalExpected: register.totalExpected,
            totalCounted: register.totalCounted,
            totalVariance: register.totalVariance,
            totalCashExpenses: register.totalCashExpenses,
            totalExpectedDeposit: register.totalExpectedDeposit,
            totalDeposit: register.totalDeposit,
            totalDepositVariance: register.totalDepositVariance,
        };
    }

    window.OplixBooksModel = {
        UTILITY_KEYS,
        UTILITY_VENDOR_GROUPS,
        emptyShiftRegister,
        defaultRegisterUnit,
        registerBlockTotal,
        emptyGamingShift,
        emptyPulltabEntry,
        normalizePulltabs,
        emptyWindStationEntry,
        normalizeWindStations,
        emptyKenoStationEntry,
        normalizeKenoStations,
        defaultFuelSale,
        normalizeFuelSale,
        sumFuelGradeGallons,
        fuelDayTotal,
        normalizeDayDoc,
        defaultUtilities,
        defaultPayroll,
        defaultPayrollLine,
        normalizePayrollLine,
        payrollTotalFrom,
        defaultMonthDoc,
        normalizeMonthDoc,
        isMonthClosed,
        normalizeMonthAdjustment,
        monthAdjustmentsTotals,
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
        pulltabDayTotal,
        windStationDayTotal,
        kenoStationDayTotal,
        lotteryDayTotal,
        daySalesForAggregate,
        cardCashBreakdownFromAggregate,
        gasSalesSlicesFromAggregate,
        gasSalesDetailBreakdownFromAggregate,
        salesBreakdownFromAggregate,
        buildExpenseDetail,
        aggregateMonth,
        compareAggregates,
        dayCashExpensesTotal,
        dayManualCashExpensesTotal,
        registerShiftPayoutsTotal,
        registerShiftPayoutsExpenseTotal,
        dayRegisterPayoutsTotal,
        dayRegisterPayoutsReconTotal,
        dayRegisterPayoutsTrackOnlyTotal,
        defaultCashReconciliation,
        normalizeCashReconciliation,
        expectedRegisterCash,
        registerShiftGrossCash,
        normalizeShiftRegister,
        expectedPulltabCash,
        finalizeRegisterReconSection,
        cashReconciliationSummary,
        cashReconciliationDayStatus,
        sumPayOuts,
        pruneEmptyPayOuts,
        emptyCashReconShift,
        aggregateCashReconciliation,
        enrichAggregateWithLotteryForms,
        lotteryFormCashEnclosed,
        lotteryFormsCashByDay,
        dailySalesExpenseRow,
        dailySalesExpenseRows,
        isDayClosed,
        dayHasEntryData,
        defaultEntryDayId,
        listClosedDayIds,
        booksHealthSummary,
    };
})();
