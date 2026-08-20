/**
 * Web reports — builders for books, compliance, and shift/lottery exports.
 */
(function () {
    const MAX_SPAN_DAYS = 366;

    function formatAddress(value) {
        return String(value || "")
            .trim()
            .replace(/\s*\n+\s*/g, ", ");
    }

    function facilityLabel(name, address) {
        const label = String(name || "Facility").trim();
        const addr = formatAddress(address);
        return addr ? `${label} — ${addr}` : label;
    }

    function locationReportExtras(meta) {
        const locationAddress = formatAddress(meta?.locationAddress);
        return locationAddress ? { locationAddress } : {};
    }

    const REPORT_TYPES = [
        {
            id: "monthly_books",
            label: "Monthly books",
            desc: "Sales, expenses, and net from Daily books for one facility and month.",
            needsMonth: true,
            needsLocation: true,
        },
        {
            id: "all_locations_books",
            label: "All locations — books",
            desc: "Side-by-side monthly totals for every facility.",
            needsMonth: true,
            needsLocation: false,
        },
        {
            id: "all_locations_detail",
            label: "All locations — detail",
            desc: "Monthly breakdown and day-by-day sales & expenses for every facility.",
            needsMonth: true,
            needsLocation: false,
        },
        {
            id: "all_locations_compare",
            label: "All locations — compare",
            desc: "Side-by-side expenses and utilities — see what each facility pays.",
            needsMonth: true,
            needsLocation: false,
        },
        {
            id: "cash_reconciliation",
            label: "Cash reconciliation",
            desc: "Expected deposit, received/deposited, and variance by day for one facility.",
            needsMonth: true,
            needsLocation: true,
        },
        {
            id: "all_locations_cash_recon",
            label: "All locations — cash reconciliation",
            desc: "Register cash reconciliation rollup for every facility.",
            needsMonth: true,
            needsLocation: false,
        },
        {
            id: "payables_receivables",
            label: "Payables & receivables",
            desc: "Open bills and amounts owed to you — one or all facilities.",
            needsMonth: false,
            needsLocation: true,
            locationAllOption: true,
        },
        {
            id: "books_payroll_payouts",
            label: "Books payroll & payouts",
            desc: "Payroll from Daily books and register payout totals by facility.",
            needsMonth: true,
            needsLocation: true,
            locationAllOption: true,
        },
        {
            id: "vendor_expenses",
            label: "Vendor expenses",
            desc: "Daily books expenses for one vendor or all vendors — one facility or all facilities.",
            needsMonth: true,
            needsLocation: true,
            locationAllOption: true,
            needsVendor: true,
        },
        {
            id: "compliance",
            label: "Licenses & renewals",
            desc: "Registrations with expiry dates and status for one or all facilities.",
            needsMonth: false,
            needsLocation: true,
            locationAllOption: true,
        },
        {
            id: "lottery",
            label: "Lottery",
            desc: "Lottery closes — sales, expected vs actual cash, over/short.",
            needsRange: true,
            needsLocation: true,
        },
        {
            id: "payroll",
            label: "Payroll",
            desc: "Hours and pay by employee from completed shifts.",
            needsRange: true,
            needsLocation: true,
        },
        {
            id: "register",
            label: "Sales & expenses",
            desc: "Register shift sales, expenses, and over/short.",
            needsRange: true,
            needsLocation: true,
        },
    ];

    const PERIOD_PRESETS = [
        { id: "today", label: "Today" },
        { id: "week", label: "This week" },
        { id: "month", label: "This month" },
        { id: "monthToDate", label: "Month to date" },
        { id: "year", label: "Year to date" },
        { id: "custom", label: "Custom range" },
    ];

    function num(v) {
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 0;
    }

    function prevMonthIdFrom(monthId) {
        const M = window.OplixBooksModel;
        if (!M || !monthId) return "";
        const d = M.parseMonthId(monthId);
        return M.monthIdFromDate(new Date(d.getFullYear(), d.getMonth() - 1, 1));
    }

    function allLocationsRowFromAggregate(aggregate) {
        const a = aggregate || {};
        return {
            sales: a.sales,
            registerCard: a.registerCard,
            registerCash: a.registerCash,
            creditCard: a.creditCard,
            fuel: a.fuelDollars,
            fuelGallons: a.fuelGallons,
            expenses: a.expenses,
            net: a.net,
        };
    }

    function sumAllLocationsRows(rows) {
        return (rows || []).reduce(
            (t, r) => ({
                sales: t.sales + num(r.sales),
                registerCard: t.registerCard + num(r.registerCard),
                registerCash: t.registerCash + num(r.registerCash),
                creditCard: t.creditCard + num(r.creditCard),
                fuel: t.fuel + num(r.fuel),
                fuelGallons: t.fuelGallons + num(r.fuelGallons),
                expenses: t.expenses + num(r.expenses),
                net: t.net + num(r.net),
            }),
            {
                sales: 0,
                registerCard: 0,
                registerCash: 0,
                creditCard: 0,
                fuel: 0,
                fuelGallons: 0,
                expenses: 0,
                net: 0,
            }
        );
    }

    const RECON_CATEGORY_DEFS = [
        {
            key: "register",
            title: "Register cash",
            subtitle: "Register cash minus cash expenses and payouts = expected deposit.",
        },
        {
            key: "lottery",
            title: "Lottery cash",
            subtitle: "Lottery cash per shift from the Daily sheet or lottery closes.",
        },
        {
            key: "pulltab",
            title: "Pulltab cash",
            subtitle: "Pulltab machine cash from the Daily sheet.",
        },
        {
            key: "wind",
            title: "Wind station cash",
            subtitle: "Wind station cash from the Daily sheet.",
        },
        {
            key: "keno",
            title: "Keno station cash",
            subtitle: "Keno station cash from the Daily sheet.",
        },
    ];

    function cashReconCategoriesFromAgg(agg) {
        const cr = agg?.cashReconciliation || {};
        return RECON_CATEGORY_DEFS.map((def) => ({
            ...def,
            data: cr[def.key] || null,
        })).filter((c) => (c.data?.dailyRows || []).length > 0);
    }

    function registerPayoutRows(agg) {
        return [
            { label: "In house account", amount: num(agg?.inHouseAccount), trackOnly: true },
            { label: "Lottery pay out", amount: num(agg?.lotteryPayOut), trackOnly: true },
            // Pull tab payout is the same as Pull Tab winners — shown once in track-only breakdown.
            { label: "Other cash pay out", amount: num(agg?.otherCashPayOut), trackOnly: false },
        ].filter((r) => r.amount !== 0);
    }

    function booksPayrollRows(agg) {
        const M = window.OplixBooksModel;
        const lines = (agg?.payrollLines || []).map((l) => M.normalizePayrollLine(l));
        if (lines.length) {
            return lines
                .filter((l) => l.pay > 0 || l.hours > 0 || l.employeeName)
                .map((l) => ({
                    label: l.employeeName || "Employee",
                    hours: l.hours,
                    rate: l.hourlyRate,
                    amount: l.pay,
                }));
        }
        const p = agg?.payroll || {};
        return ["week1", "week2", "week3", "week4"]
            .map((w, i) => ({
                label: `Week ${i + 1}`,
                amount: num(p[w]),
            }))
            .filter((r) => r.amount !== 0);
    }

    function buildBooksSupplement(agg) {
        return {
            registerPayouts: registerPayoutRows(agg),
            booksPayroll: booksPayrollRows(agg),
            cashReconCategories: cashReconCategoriesFromAgg(agg),
        };
    }

    function reconRollupFromRegister(reg) {
        const rows = reg?.dailyRows || [];
        let worstDay = null;
        let worstVariance = 0;
        rows.forEach((row) => {
            const v = Math.abs(
                row.deposit != null ? num(row.depositVariance) : num(row.variance)
            );
            if (v > worstVariance) {
                worstVariance = v;
                worstDay = row.dayId;
            }
        });
        return {
            daysWithExpected: reg?.daysWithExpected || 0,
            daysReconciled: reg?.daysReconciled || 0,
            daysNeedingAttention: reg?.daysNeedingAttention || 0,
            totalExpectedDeposit: num(reg?.totalExpectedDeposit),
            totalDeposit: num(reg?.totalDeposit),
            totalDepositVariance: num(reg?.totalDepositVariance),
            totalVariance: num(reg?.totalVariance),
            worstDay,
            worstVariance,
        };
    }

    function startOfToday() {
        const d = new Date();
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function formatIsoDate(value, model) {
        if (!value) return "—";
        if (model?.isoDateInput) return model.isoDateInput(value) || "—";
        const d = toDate(value);
        return d ? d.toLocaleDateString("en-US") : "—";
    }

    function buildPayablesReceivablesReport(packs, meta) {
        const PM = window.OplixPayablesModel;
        const RM = window.OplixReceivablesModel;
        const today = startOfToday();

        const payablesOpen = [];
        const payablesPaid = [];
        const receivablesOpen = [];
        const receivablesReceived = [];

        (packs || []).forEach((pack) => {
            const loc = facilityLabel(pack.locationName, pack.locationAddress);
            (pack.payables || []).forEach((raw) => {
                const p = PM ? PM.normalizePayable(raw, pack.locationId) : raw;
                const due = PM ? PM.toDate(p.dueDate) : toDate(p.dueDate);
                const row = {
                    location: loc,
                    name: p.payTo || "—",
                    amount: num(p.amount),
                    dueDate: formatIsoDate(p.dueDate, PM),
                    overdue: !p.isPaid && due && due < today,
                    notes: p.notes || "",
                };
                if (p.isPaid) payablesPaid.push(row);
                else payablesOpen.push(row);
            });
            (pack.receivables || []).forEach((raw) => {
                const r = RM ? RM.normalizeReceivable(raw, pack.locationId) : raw;
                const due = RM ? RM.toDate(r.dueDate) : toDate(r.dueDate);
                const row = {
                    location: loc,
                    name: r.receiveFrom || "—",
                    amount: num(r.amount),
                    dueDate: formatIsoDate(r.dueDate, RM),
                    overdue: !r.isReceived && due && due < today,
                    notes: r.notes || "",
                };
                if (r.isReceived) receivablesReceived.push(row);
                else receivablesOpen.push(row);
            });
        });

        const openPayablesTotal = payablesOpen.reduce((s, r) => s + r.amount, 0);
        const openReceivablesTotal = receivablesOpen.reduce((s, r) => s + r.amount, 0);
        const overduePayables = payablesOpen.filter((r) => r.overdue).length;
        const overdueReceivables = receivablesOpen.filter((r) => r.overdue).length;

        return {
            type: "payables_receivables",
            title: "Payables & receivables",
            meta,
            headline: meta.allLocations ? "All facilities" : meta.locationName,
            subhead: `Open items · ${new Date().toLocaleDateString("en-US")}`,
            ...locationReportExtras(meta),
            summary: [
                { label: "Open payables", value: openPayablesTotal },
                { label: "Open receivables", value: openReceivablesTotal },
                { label: "Overdue payables", value: overduePayables, format: "number" },
                { label: "Overdue receivables", value: overdueReceivables, format: "number" },
            ],
            payablesOpen,
            payablesPaid,
            receivablesOpen,
            receivablesReceived,
            csvRows: [
                ["Payables — open"],
                ["Facility", "Pay to", "Amount", "Due", "Overdue"],
                ...payablesOpen.map((r) => [r.location, r.name, r.amount, r.dueDate, r.overdue ? "Yes" : ""]),
                [],
                ["Receivables — open"],
                ["Facility", "Receive from", "Amount", "Due", "Overdue"],
                ...receivablesOpen.map((r) => [r.location, r.name, r.amount, r.dueDate, r.overdue ? "Yes" : ""]),
            ],
        };
    }

    function buildCashReconciliationReport(agg, meta) {
        const categories = cashReconCategoriesFromAgg(agg);
        const reg = agg?.cashReconciliation?.register || {};
        const rollup = reconRollupFromRegister(reg);
        return {
            type: "cash_reconciliation",
            title: "Cash reconciliation report",
            meta,
            headline: meta.locationName,
            subhead: meta.monthLabel,
            ...locationReportExtras(meta),
            summary: [
                { label: "Days reconciled", value: `${rollup.daysReconciled} / ${rollup.daysWithExpected}`, format: "text" },
                { label: "Deposit variance", value: rollup.totalDepositVariance },
                { label: "Need attention", value: rollup.daysNeedingAttention, format: "number" },
            ],
            categories,
            supplement: buildBooksSupplement(agg),
            csvRows: [
                ["Day", "Received", "Expected deposit", "Deposited", "Variance", "Status"],
                ...(reg.dailyRows || []).flatMap((row) => [
                    [
                        row.dayId,
                        num(row.countedTotal),
                        num(row.expectedDeposit),
                        row.deposit == null ? "" : num(row.deposit),
                        row.deposit != null ? num(row.depositVariance) : num(row.variance),
                        row.status?.label || "",
                    ],
                ]),
            ],
        };
    }

    function buildAllLocationsCashReconReport(packs, meta) {
        const tableRows = (packs || []).map((p) => {
            const reg = p.aggregate?.cashReconciliation?.register || {};
            const rollup = reconRollupFromRegister(reg);
            return {
                location: facilityLabel(p.locationName, p.locationAddress),
                ...rollup,
            };
        });
        const totals = tableRows.reduce(
            (t, r) => ({
                daysWithExpected: t.daysWithExpected + r.daysWithExpected,
                daysReconciled: t.daysReconciled + r.daysReconciled,
                daysNeedingAttention: t.daysNeedingAttention + r.daysNeedingAttention,
                totalExpectedDeposit: t.totalExpectedDeposit + r.totalExpectedDeposit,
                totalDeposit: t.totalDeposit + r.totalDeposit,
                totalDepositVariance: t.totalDepositVariance + r.totalDepositVariance,
            }),
            {
                daysWithExpected: 0,
                daysReconciled: 0,
                daysNeedingAttention: 0,
                totalExpectedDeposit: 0,
                totalDeposit: 0,
                totalDepositVariance: 0,
            }
        );

        return {
            type: "all_locations_cash_recon",
            title: "All locations — cash reconciliation",
            meta,
            headline: "All facilities",
            subhead: meta.monthLabel,
            summary: [
                { label: "Locations", value: tableRows.length, format: "number" },
                { label: "Days needing attention", value: totals.daysNeedingAttention, format: "number" },
                { label: "Total deposit variance", value: totals.totalDepositVariance },
            ],
            tableRows,
            totals,
            csvRows: [
                [
                    "Facility",
                    "Days w/ expected",
                    "Days reconciled",
                    "Need attention",
                    "Expected deposit",
                    "Deposited",
                    "Deposit variance",
                    "Worst day",
                    "Worst variance",
                ],
                ...tableRows.map((r) => [
                    r.location,
                    r.daysWithExpected,
                    r.daysReconciled,
                    r.daysNeedingAttention,
                    r.totalExpectedDeposit,
                    r.totalDeposit,
                    r.totalDepositVariance,
                    r.worstDay || "",
                    r.worstVariance,
                ]),
            ],
        };
    }

    function buildBooksPayrollPayoutsReport(packs, meta) {
        const sections = (packs || []).map((p) => ({
            locationName: p.locationName,
            locationAddress: formatAddress(p.locationAddress),
            registerPayouts: registerPayoutRows(p.aggregate),
            booksPayroll: booksPayrollRows(p.aggregate),
            payrollTotal: num(p.aggregate?.payrollTotal),
            payoutTotal: registerPayoutRows(p.aggregate).reduce((s, r) => s + r.amount, 0),
        }));

        const totals = sections.reduce(
            (t, s) => ({
                payroll: t.payroll + s.payrollTotal,
                payouts: t.payouts + s.payoutTotal,
            }),
            { payroll: 0, payouts: 0 }
        );

        return {
            type: "books_payroll_payouts",
            title: "Books payroll & payouts",
            meta,
            headline: meta.allLocations ? "All facilities" : meta.locationName,
            subhead: meta.monthLabel,
            ...locationReportExtras(meta),
            summary: [
                { label: "Locations", value: sections.length, format: "number" },
                { label: "Payroll total", value: totals.payroll },
                { label: "Payouts total", value: totals.payouts },
            ],
            sections,
            csvRows: [
                ["Facility", "Line", "Hours", "Rate", "Amount", "Track only"],
                ...sections.flatMap((s) => {
                    const locLabel = facilityLabel(s.locationName, s.locationAddress);
                    const rows = [];
                    s.booksPayroll.forEach((l) => {
                        rows.push([
                            locLabel,
                            l.label,
                            l.hours ?? "",
                            l.rate ?? "",
                            l.amount,
                            "",
                        ]);
                    });
                    s.registerPayouts.forEach((p) => {
                        rows.push([locLabel, p.label, "", "", p.amount, p.trackOnly ? "Yes" : ""]);
                    });
                    return rows;
                }),
            ],
        };
    }

    function toDate(v) {
        if (!v) return null;
        if (v instanceof Date) return v;
        if (typeof v.toDate === "function") return v.toDate();
        if (typeof v === "number") return new Date(v);
        const d = new Date(v);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function startOfDay(d) {
        const x = new Date(d);
        x.setHours(0, 0, 0, 0);
        return x;
    }

    function endOfDay(d) {
        const x = startOfDay(d);
        x.setHours(23, 59, 59, 999);
        return x;
    }

    function intervalFromPreset(preset, customStart, customEnd) {
        const now = new Date();
        switch (preset) {
            case "today": {
                const s = startOfDay(now);
                return { start: s, end: endOfDay(s) };
            }
            case "week": {
                const s = startOfDay(now);
                const day = s.getDay();
                const diff = day === 0 ? 6 : day - 1;
                s.setDate(s.getDate() - diff);
                return { start: s, end: now };
            }
            case "month": {
                const s = new Date(now.getFullYear(), now.getMonth(), 1);
                const e = new Date(now.getFullYear(), now.getMonth() + 1, 0);
                return { start: startOfDay(s), end: endOfDay(e) };
            }
            case "monthToDate": {
                const s = new Date(now.getFullYear(), now.getMonth(), 1);
                return { start: startOfDay(s), end: now };
            }
            case "year": {
                const s = new Date(now.getFullYear(), 0, 1);
                return { start: startOfDay(s), end: now };
            }
            default: {
                const s = startOfDay(customStart || now);
                const e = endOfDay(customEnd || now);
                return { start: s, end: e };
            }
        }
    }

    function spanDays(interval) {
        return Math.round((interval.end - interval.start) / (24 * 60 * 60 * 1000));
    }

    function spanExceedsLimit(interval) {
        return spanDays(interval) > MAX_SPAN_DAYS;
    }

    function formatRange(interval) {
        const fmt = (d) =>
            d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
        if (interval.start.toDateString() === interval.end.toDateString()) return fmt(interval.start);
        return `${fmt(interval.start)} – ${fmt(interval.end)}`;
    }

    function inRange(date, interval) {
        const d = toDate(date);
        if (!d) return false;
        return d >= interval.start && d <= interval.end;
    }

    function shiftHoursWorked(shift) {
        const clockIn = toDate(shift.clockInTime);
        if (!clockIn) return null;
        let endTime;
        if (shift.isAutoClockedOut && shift.scheduledEndTime) {
            endTime = toDate(shift.scheduledEndTime);
        } else if (shift.clockOutTime) {
            endTime = toDate(shift.clockOutTime);
        } else return null;
        if (!endTime) return null;
        const hours = (endTime - clockIn) / 3600000;
        return hours > 0 ? hours : null;
    }

    function shiftHasRegisterData(shift) {
        const regs = shift.registers || [];
        return (
            regs.length > 0 ||
            shift.cashSale != null ||
            shift.cashInHand != null ||
            shift.overShort != null ||
            shift.creditCard != null
        );
    }

    function receivableReportLines(agg, monthId) {
        const fromBooks = (agg.receivables || [])
            .map((r) => ({
                description: String(r.description || "").trim() || "Receivable",
                amount: num(r.amount),
            }))
            .filter((r) => r.amount !== 0);

        if (fromBooks.length) return fromBooks;

        const RM = window.OplixReceivablesModel;
        const facility = agg.facilityReceivables || [];
        if (!RM || !monthId || !facility.length) return [];

        return RM.receivedReceivablesForMonth(facility, monthId)
            .map((r) => {
                const n = RM.normalizeReceivable(r, r.locationId);
                return {
                    description: n.receiveFrom || "Receivable",
                    amount: num(n.amount),
                };
            })
            .filter((r) => r.amount !== 0);
    }

    function openReceivableReportLines(agg) {
        const RM = window.OplixReceivablesModel;
        const facility = agg.facilityReceivables || [];
        if (!RM || !facility.length) return [];
        return RM.openReceivables(facility)
            .map((r) => {
                const n = RM.normalizeReceivable(r, r.locationId);
                return {
                    description: n.receiveFrom || "Receivable",
                    amount: num(n.amount),
                    dueDate: RM.isoDateInput(n.dueDate) || "",
                };
            })
            .filter((r) => r.amount !== 0);
    }

    function buildMonthlyBooksReport(agg, meta) {
        const M = window.OplixBooksModel;
        const rows = [];
        const add = (label, value, fmt, subRow) =>
            rows.push({ label, value, fmt, subRow: !!subRow });

        if (agg.hasGasStation) {
            add("Total sales (merch)", agg.sales);
            (agg.salesBreakdown || M.salesBreakdownFromAggregate(agg)).forEach((r) => {
                if (r.label === "Merch sale") return;
                if (num(r.amount) !== 0) add(r.label, r.amount, r.format);
            });
        } else {
            add("Total sales", agg.sales);
            (agg.salesBreakdown || M.salesBreakdownFromAggregate(agg)).forEach((r) => {
                if (num(r.amount) !== 0) add(r.label, r.amount);
            });
        }

        const receivableLines = receivableReportLines(agg, meta.monthId);
        const receivablesTotal =
            receivableLines.length > 0
                ? receivableLines.reduce((s, r) => s + r.amount, 0)
                : num(agg.receivablesTotal);

        if (receivableLines.length) {
            rows.push({ label: "Checks Received", value: null, section: true });
            receivableLines.forEach((r) => add(r.description, r.amount, null, true));
            add("Checks Received total", receivablesTotal);
        } else if (receivablesTotal !== 0) {
            add("Checks Received", receivablesTotal);
        }

        const openReceivableLines = openReceivableReportLines(agg);
        if (openReceivableLines.length) {
            rows.push({ label: "Open receivables (not in Net yet)", value: null, section: true });
            openReceivableLines.forEach((r) => {
                const due = r.dueDate ? ` · due ${r.dueDate}` : "";
                add(`${r.description}${due}`, r.amount, null, true);
            });
            add(
                "Open receivables total",
                openReceivableLines.reduce((s, r) => s + r.amount, 0)
            );
        }

        const trackOnly = agg.trackOnlyBreakdown || M.trackOnlyBreakdownFromAggregate?.(agg) || [];
        if (trackOnly.length) {
            rows.push({ label: "Track only", value: null, section: true });
            trackOnly.forEach((r) => {
                if (num(r.amount) !== 0) add(`${r.label} (track only)`, r.amount, r.format);
            });
        }
        rows.push({ label: "—", value: null, section: true });
        add("Cash expense", agg.cashExpense);
        add("Checks / ACH", agg.checksAch);
        add("Other expense", agg.otherExpense);

        const utilRows = (
            agg.utilitiesBreakdown || M.utilitiesBreakdownFrom(agg.utilities || {}, [])
        ).filter((u) => num(u.amount) !== 0);
        if (utilRows.length) {
            utilRows.forEach((u) => add(u.label, u.amount, null, true));
            add("Utilities total", agg.utilitiesTotal);
        } else {
            add("Utilities", agg.utilitiesTotal);
        }

        add("Payroll", agg.payrollTotal);
        add("Sales tax", agg.salesTax);
        add("Accountant", agg.accountant);
        add("Total expenses", agg.expenses);
        rows.push({ label: "—", value: null, section: true });
        add("Net", agg.net);

        return {
            type: "monthly_books",
            title: "Monthly books report",
            meta,
            headline: meta.locationName,
            subhead: meta.monthLabel,
            ...locationReportExtras(meta),
            summary: [
                { label: agg.hasGasStation ? "Merch sales" : "Total sales", value: agg.sales },
                { label: "Expenses", value: agg.expenses },
                { label: "Net", value: agg.net },
            ],
            rows,
            receivableLines,
            openReceivableLines,
            expenseDetail: agg.expenseDetail || [],
            totalExpenses: agg.expenses,
            supplement: buildBooksSupplement(agg),
            payrollTotal: agg.payrollTotal,
            csvRows: [
                ...rows
                    .filter((r) => !r.section)
                    .map((r) => [r.label, r.fmt === "number" ? num(r.value) : num(r.value)]),
                [],
                ["Expense detail"],
                ["Category", "Day", "Description", "Amount"],
                ...(agg.expenseDetail || []).map((line) => [
                    line.category,
                    line.dayId || "",
                    line.description,
                    num(line.amount),
                ]),
            ],
        };
    }

    function buildAllLocationsBooksReport(packs, meta, prevPacks) {
        const M = window.OplixBooksModel;
        const prevByLocId = {};
        (prevPacks || []).forEach((p) => {
            prevByLocId[p.locationId] = allLocationsRowFromAggregate(p.aggregate);
        });
        const tableRows = packs.map((p) => {
            const a = p.aggregate;
            return {
                locationId: p.locationId,
                location: facilityLabel(p.locationName, p.locationAddress),
                hasGas: a.hasGasStation,
                sales: a.sales,
                registerCard: a.registerCard,
                registerCash: a.registerCash,
                creditCard: a.creditCard,
                fuel: a.fuelDollars,
                fuelGallons: a.fuelGallons,
                expenses: a.expenses,
                net: a.net,
                prev: prevByLocId[p.locationId] || null,
            };
        });
        const totals = sumAllLocationsRows(tableRows);
        const prevTotals = sumAllLocationsRows(
            (prevPacks || []).map((p) => allLocationsRowFromAggregate(p.aggregate))
        );
        const anyGas = tableRows.some((r) => r.hasGas);
        const salesHeader = anyGas ? "Merch / sales" : "Sales";
        const detailHeaders = [
            "Facility",
            salesHeader,
            "Card",
            "Cash",
            anyGas ? "Network Card" : "Credit card",
            "Fuel ($)",
            "Gallons",
            "Expenses",
            "Net",
        ];

        return {
            type: "all_locations_books",
            title: "All locations — monthly books",
            meta,
            headline: "All facilities",
            subhead: meta.monthLabel,
            summary: [
                { label: "Locations", value: tableRows.length, format: "number" },
                { label: "Total expenses", value: totals.expenses },
                { label: "Total net", value: totals.net },
            ],
            tableRows,
            totals,
            prevTotals: prevPacks?.length ? prevTotals : null,
            prevMonthLabel: meta.prevMonthLabel || null,
            anyGas,
            salesHeader,
            csvRows: [
                detailHeaders,
                ...tableRows.map((r) => [
                    r.location,
                    r.sales,
                    r.registerCard,
                    r.registerCash,
                    r.creditCard,
                    r.fuel,
                    r.fuelGallons,
                    r.expenses,
                    r.net,
                ]),
                [
                    "Total",
                    totals.sales,
                    totals.registerCard,
                    totals.registerCash,
                    totals.creditCard,
                    totals.fuel,
                    totals.fuelGallons,
                    totals.expenses,
                    totals.net,
                ],
            ],
        };
    }

    const COMPARE_GROUP_LABELS = {
        sales: "Sales & revenue",
        daily: "Daily expenses (from Daily sheet)",
        utilities: "Utilities",
        monthly: "Monthly fees",
        totals: "Totals",
    };

    function compareLineDefs(packs) {
        const M = window.OplixBooksModel;
        const anyGas = packs.some((p) => p.aggregate?.hasGasStation);
        const lines = [];

        if (anyGas) {
            lines.push({ label: "Merch sale", get: (a) => a.merchSale, group: "sales" });
            lines.push({ label: "Card", get: (a) => a.registerCard, group: "sales" });
            lines.push({ label: "Cash", get: (a) => a.registerCash, group: "sales" });
            lines.push({ label: "Network Card", get: (a) => a.creditCard, group: "sales" });
            lines.push({ label: "Fuel ($)", get: (a) => a.fuelDollars, group: "sales" });
            lines.push({ label: "Pulltab (track only)", get: (a) => a.pulltabCash, group: "track" });
            lines.push({ label: "Lottery (track only)", get: (a) => a.lotteryCash, group: "track" });
            lines.push({ label: "Wind station (track only)", get: (a) => a.windStationCash, group: "track" });
            lines.push({ label: "Keno station (track only)", get: (a) => a.kenoStationCash, group: "track" });
        } else {
            lines.push({ label: "Card", get: (a) => a.registerCard, group: "sales" });
            lines.push({ label: "Cash", get: (a) => a.registerCash, group: "sales" });
            lines.push({ label: "Lottery (track only)", get: (a) => a.lotteryCash, group: "track" });
            lines.push({ label: "Pulltab (track only)", get: (a) => a.pulltabCash, group: "track" });
            lines.push({ label: "Wind station (track only)", get: (a) => a.windStationCash, group: "track" });
            lines.push({ label: "Keno station (track only)", get: (a) => a.kenoStationCash, group: "track" });
            lines.push({ label: "Total sales", get: (a) => a.sales, group: "sales" });
        }
        lines.push({ label: "Total revenue", get: (a) => a.totalRevenue ?? a.sales, group: "sales" });

        const receivableDescs = new Set();
        packs.forEach((p) => {
            (p.aggregate?.receivables || []).forEach((r) => {
                if (num(r.amount) === 0) return;
                const label = String(r.description || "").trim() || "Receivable";
                receivableDescs.add(label);
            });
        });
        [...receivableDescs]
            .sort((a, b) => a.localeCompare(b))
            .forEach((label) => {
                lines.push({
                    label,
                    get: (a) =>
                        (a.receivables || [])
                            .filter((r) => (String(r.description || "").trim() || "Receivable") === label)
                            .reduce((s, r) => s + num(r.amount), 0),
                    group: "sales",
                });
            });
        lines.push({
            label: "Checks Received total",
            get: (a) => a.receivablesTotal,
            group: "sales",
            emphasis: true,
        });

        lines.push({ label: "Cash expense", get: (a) => a.cashExpense, group: "daily" });
        lines.push({ label: "Checks / ACH", get: (a) => a.checksAch, group: "daily" });
        lines.push({ label: "Other expense", get: (a) => a.otherExpense, group: "daily" });

        const utilityKeys = new Set();
        M.UTILITY_KEYS.forEach((u) => utilityKeys.add(u.key));
        packs.forEach((p) => {
            Object.keys(p.aggregate?.utilities || {}).forEach((k) => utilityKeys.add(k));
        });
        [...utilityKeys]
            .sort((a, b) => M.labelForUtilityKey(a, []).localeCompare(M.labelForUtilityKey(b, [])))
            .forEach((key) => {
                lines.push({
                    label: M.labelForUtilityKey(key, []),
                    get: (a) => num(a.utilities?.[key]),
                    group: "utilities",
                });
            });

        lines.push({ label: "Payroll", get: (a) => a.payrollTotal, group: "monthly" });
        lines.push({ label: "Sales tax", get: (a) => a.salesTax, group: "monthly" });
        lines.push({ label: "Accountant", get: (a) => a.accountant, group: "monthly" });
        lines.push({ label: "Total expenses", get: (a) => a.expenses, group: "totals", emphasis: true });
        lines.push({ label: "Net", get: (a) => a.net, group: "totals", emphasis: true });

        return lines.filter(
            (line) =>
                line.emphasis ||
                packs.some((p) => num(line.get(p.aggregate)) !== 0)
        );
    }

    function buildAllLocationsCompareReport(packs, meta) {
        const locations = packs.map((p) => ({
            id: p.locationId,
            name: p.locationName,
            address: formatAddress(p.locationAddress),
            aggregate: p.aggregate,
        }));
        const lineDefs = compareLineDefs(packs);
        let lastGroup = null;
        const tableRows = lineDefs.map((def) => {
            const values = locations.map((loc) => ({
                locationId: loc.id,
                locationName: loc.name,
                value: num(def.get(loc.aggregate)),
            }));
            const total = values.reduce((s, v) => s + v.value, 0);
            const groupHeader = def.group !== lastGroup ? def.group : null;
            lastGroup = def.group;
            return {
                label: def.label,
                values,
                total,
                emphasis: !!def.emphasis,
                group: def.group,
                groupHeader,
            };
        });

        const totals = locations.reduce(
            (t, loc) => ({
                expenses: t.expenses + num(loc.aggregate.expenses),
                net: t.net + num(loc.aggregate.net),
            }),
            { expenses: 0, net: 0 }
        );

        const csvRows = [
            ["Line item", ...locations.map((l) => facilityLabel(l.name, l.address)), "Total"],
            ...tableRows.map((r) => [
                r.groupHeader ? `${COMPARE_GROUP_LABELS[r.group] || r.group}: ${r.label}` : r.label,
                ...r.values.map((v) => v.value),
                r.total,
            ]),
        ];

        return {
            type: "all_locations_compare",
            title: "All locations — expense compare",
            meta,
            headline: "All facilities",
            subhead: meta.monthLabel,
            summary: [
                { label: "Locations", value: locations.length, format: "number" },
                { label: "Total expenses", value: totals.expenses },
                { label: "Total net", value: totals.net },
            ],
            locations: locations.map((l) => ({ id: l.id, name: l.name, address: l.address })),
            tableRows,
            groupLabels: COMPARE_GROUP_LABELS,
            csvRows,
        };
    }

    function buildAllLocationsDetailReport(packs, meta) {
        const M = window.OplixBooksModel;
        const locationSections = packs.map((p) => {
            const agg = p.aggregate;
            const monthly = buildMonthlyBooksReport(agg, {
                locationName: p.locationName,
                locationAddress: formatAddress(p.locationAddress),
                monthLabel: meta.monthLabel,
                monthId: meta.monthId,
            });
            const { rows: dailyRows, totals: dailyTotals } = M.dailySalesExpenseRows(
                meta.monthId,
                p.daysById,
                { hasGasStation: agg.hasGasStation }
            );
            return {
                locationName: p.locationName,
                locationAddress: formatAddress(p.locationAddress),
                hasGas: agg.hasGasStation,
                monthlyRows: monthly.rows,
                monthlySummary: monthly.summary,
                expenseDetail: agg.expenseDetail || [],
                totalExpenses: agg.expenses,
                totalNet: agg.net,
                dailyRows,
                dailyTotals,
                supplement: buildBooksSupplement(agg),
                payrollTotal: agg.payrollTotal,
            };
        });

        const totals = locationSections.reduce(
            (t, s) => ({
                expenses: t.expenses + s.totalExpenses,
                net: t.net + s.totalNet,
            }),
            { expenses: 0, net: 0 }
        );

        const csvRows = [["Monthly breakdown"]];
        locationSections.forEach((s) => {
            const locLabel = facilityLabel(s.locationName, s.locationAddress);
            csvRows.push([locLabel]);
            s.monthlyRows
                .filter((r) => !r.section)
                .forEach((r) => {
                    csvRows.push(["", r.label, num(r.value)]);
                });
            csvRows.push([]);
        });
        csvRows.push(["Expense detail"]);
        csvRows.push(["Facility", "Category", "Day", "Description", "Amount"]);
        locationSections.forEach((s) => {
            s.expenseDetail.forEach((line) => {
                csvRows.push([
                    facilityLabel(s.locationName, s.locationAddress),
                    line.category,
                    line.dayId || "",
                    line.description,
                    num(line.amount),
                ]);
            });
        });
        csvRows.push([]);
        csvRows.push(["Daily sales & expenses"]);
        const anyGas = locationSections.some((s) => s.hasGas);
        if (anyGas) {
            csvRows.push([
                "Facility",
                "Day",
                "Merch",
                "Fuel (gal)",
                "Fuel ($)",
                "Network Card",
                "Cash exp.",
                "Check Exp",
                "Other",
                "Total exp.",
                "Net",
            ]);
            locationSections.forEach((s) => {
                s.dailyRows.forEach((row) => {
                    if (!row.hasData) return;
                    csvRows.push([
                        facilityLabel(s.locationName, s.locationAddress),
                        row.dayId,
                        s.hasGas ? row.merchSale : "",
                        s.hasGas ? row.fuelGallons : "",
                        s.hasGas ? row.fuelDollars : "",
                        s.hasGas ? row.creditCard : "",
                        row.cashExpense,
                        row.checksAch,
                        row.otherExpense,
                        row.expenses,
                        row.net,
                    ]);
                });
            });
        } else {
            csvRows.push([
                "Facility",
                "Day",
                "Sales",
                "Cash exp.",
                "Check Exp",
                "Other",
                "Total exp.",
                "Net",
            ]);
            locationSections.forEach((s) => {
                s.dailyRows.forEach((row) => {
                    if (!row.hasData) return;
                    csvRows.push([
                        facilityLabel(s.locationName, s.locationAddress),
                        row.dayId,
                        row.sales,
                        row.cashExpense,
                        row.checksAch,
                        row.otherExpense,
                        row.expenses,
                        row.net,
                    ]);
                });
            });
        }

        return {
            type: "all_locations_detail",
            title: "All locations — detailed books",
            meta,
            headline: "All facilities",
            subhead: meta.monthLabel,
            summary: [
                { label: "Locations", value: locationSections.length, format: "number" },
                { label: "Total expenses", value: totals.expenses },
                { label: "Total net", value: totals.net },
            ],
            locationSections,
            anyGas,
            csvRows,
        };
    }

    function buildComplianceReport(items, meta) {
        const C = window.OplixComplianceModel;
        const sorted = C.sortItems(items.filter((i) => i.active !== false));
        const tableRows = sorted.map((item) => {
            const disp = C.displayStatus(item);
            return {
                facility: facilityLabel(item._locationName, item._locationAddress) || meta.locationName || "—",
                type: C.recordTypeLabel(item.recordType),
                name: item.title || C.categoryLabel(item.category),
                category: C.categoryLabel(item.category),
                identifier: item.identifier || "—",
                expiry: item.expiryDate || "—",
                hint: C.expiryHint(item),
                status: disp.label,
                statusClass: disp.className,
            };
        });
        const attention = C.needsAttentionCount(sorted);

        return {
            type: "compliance",
            title: "Licenses & renewals report",
            meta,
            headline: meta.locationName || "All facilities",
            subhead: `Generated ${new Date().toLocaleDateString("en-US")}`,
            ...locationReportExtras(meta),
            summary: [
                { label: "Total records", value: tableRows.length, format: "number" },
                { label: "Need attention", value: attention, format: "number" },
            ],
            tableRows,
            csvRows: [
                ["Facility", "Type", "Name", "Category", "ID #", "Expires", "Status"],
                ...tableRows.map((r) => [
                    r.facility,
                    r.type,
                    r.name,
                    r.category,
                    r.identifier,
                    r.expiry,
                    r.status,
                ]),
            ],
        };
    }

    function buildLotteryReport(forms, shifts, employees, interval, meta) {
        const shiftById = Object.fromEntries(shifts.map((s) => [s.id, s]));
        const empById = Object.fromEntries(employees.map((e) => [e.id, e]));

        const filtered = forms
            .filter((f) => f.shiftSummary && inRange(f.submittedAt, interval))
            .sort((a, b) => toDate(b.submittedAt) - toDate(a.submittedAt));

        let totalSold = 0;
        let totalExpected = 0;
        let totalActual = 0;
        let netOS = 0;

        const tableRows = filtered.map((form) => {
            const s = form.shiftSummary;
            const shift = shiftById[form.shiftId];
            const employeeName = shift ? empById[shift.employeeId]?.name || "—" : "—";
            const sold = num(s.totalSoldAmount);
            const expected = num(s.cashInBagNet);
            const actual =
                s.overShort != null ? num(s.cashInBagNet) + num(s.overShort) : null;
            const os = s.overShort != null ? num(s.overShort) : null;
            totalSold += sold;
            totalExpected += expected;
            if (actual != null) totalActual += actual;
            if (os != null) netOS += os;
            const term = (form.terminalNumber || 1) > 1 ? `Terminal ${form.terminalNumber}` : "Terminal 1";
            return {
                date: toDate(form.submittedAt)?.toLocaleString("en-US") || "—",
                terminal: term,
                employee: employeeName,
                sold,
                expected,
                actual,
                overShort: os,
            };
        });

        return {
            type: "lottery",
            title: "Lottery report",
            meta,
            headline: meta.locationName,
            subhead: formatRange(interval),
            ...locationReportExtras(meta),
            summary: [
                { label: "Closes", value: tableRows.length, format: "number" },
                { label: "Total sold", value: totalSold },
                { label: "Net over/short", value: netOS },
            ],
            tableRows,
            csvRows: [
                ["Date", "Terminal", "Employee", "Sold", "Expected enclosed", "Actual enclosed", "Over/short"],
                ...tableRows.map((r) => [
                    r.date,
                    r.terminal,
                    r.employee,
                    r.sold,
                    r.expected,
                    r.actual ?? "",
                    r.overShort ?? "",
                ]),
            ],
        };
    }

    function buildPayrollReport(shifts, employees, interval, meta) {
        const empById = Object.fromEntries(employees.map((e) => [e.id, e]));
        const filtered = shifts.filter((s) => s.clockOutTime && inRange(s.clockOutTime, interval));
        const grouped = {};
        filtered.forEach((s) => {
            if (!grouped[s.employeeId]) grouped[s.employeeId] = [];
            grouped[s.employeeId].push(s);
        });

        const tableRows = [];
        Object.keys(grouped).forEach((empId) => {
            const employee = empById[empId];
            const rate = num(employee?.hourlyRate);
            if (!employee || rate <= 0) return;
            const empShifts = grouped[empId];
            const hours = empShifts.reduce((sum, s) => sum + (shiftHoursWorked(s) || 0), 0);
            const pay = hours * rate;
            tableRows.push({
                employee: employee.name || employee.username || "Employee",
                rate,
                hours,
                pay,
                shifts: empShifts.length,
            });
        });
        tableRows.sort((a, b) => b.pay - a.pay);

        const totalHours = tableRows.reduce((s, r) => s + r.hours, 0);
        const totalPay = tableRows.reduce((s, r) => s + r.pay, 0);

        return {
            type: "payroll",
            title: "Payroll report",
            meta,
            headline: meta.locationName,
            subhead: formatRange(interval),
            ...locationReportExtras(meta),
            summary: [
                { label: "Employees", value: tableRows.length, format: "number" },
                { label: "Total hours", value: totalHours, format: "number" },
                { label: "Total pay", value: totalPay },
            ],
            tableRows,
            csvRows: [
                ["Employee", "Hourly rate", "Hours", "Pay", "Shifts"],
                ...tableRows.map((r) => [r.employee, r.rate, r.hours.toFixed(2), r.pay, r.shifts]),
            ],
        };
    }

    function buildRegisterReport(shifts, employees, interval, meta) {
        const empById = Object.fromEntries(employees.map((e) => [e.id, e]));
        const filtered = shifts.filter(
            (s) =>
                s.clockOutTime &&
                shiftHasRegisterData(s) &&
                inRange(s.clockOutTime, interval)
        );

        let totalSales = 0;
        let totalExpenses = 0;
        let totalOS = 0;

        const tableRows = filtered
            .sort((a, b) => toDate(b.clockOutTime) - toDate(a.clockOutTime))
            .map((shift) => {
                const sales = num(shift.cashSale) + num(shift.creditCard);
                const expenses = (shift.expenses || []).reduce((s, e) => s + num(e.amount), 0);
                const os = shift.overShort != null ? num(shift.overShort) : null;
                totalSales += sales;
                totalExpenses += expenses;
                if (os != null) totalOS += os;
                return {
                    date: toDate(shift.clockOutTime)?.toLocaleString("en-US") || "—",
                    employee: empById[shift.employeeId]?.name || "—",
                    sales,
                    expenses,
                    overShort: os,
                };
            });

        return {
            type: "register",
            title: "Sales & expenses report",
            meta,
            headline: meta.locationName,
            subhead: formatRange(interval),
            ...locationReportExtras(meta),
            summary: [
                { label: "Shifts", value: tableRows.length, format: "number" },
                { label: "Total sales", value: totalSales },
                { label: "Net (sales − expenses)", value: totalSales - totalExpenses },
            ],
            tableRows,
            csvRows: [
                ["Clock out", "Employee", "Sales", "Expenses", "Over/short"],
                ...tableRows.map((r) => [r.date, r.employee, r.sales, r.expenses, r.overShort ?? ""]),
            ],
        };
    }

    const ALL_VENDORS = "__all__";

    function vendorKey(name) {
        return String(name || "")
            .trim()
            .toLowerCase()
            .replace(/\s+/g, " ");
    }

    function isAllVendors(name) {
        return name === ALL_VENDORS;
    }

    function uniqueVendorNames(lines) {
        const seen = new Map();
        (lines || []).forEach((line) => {
            const desc = String(
                typeof line === "string" ? line : line?.description || ""
            ).trim();
            const key = vendorKey(desc);
            if (!key) return;
            if (!seen.has(key)) seen.set(key, desc);
        });
        return [...seen.values()].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
    }

    function buildVendorExpenseReport(lines, meta) {
        const allVendors = isAllVendors(meta.vendorName);
        const vendor = allVendors ? "" : vendorKey(meta.vendorName);
        const allLocations = !!meta.allLocations;
        const matched = (lines || [])
            .filter((line) => {
                const key = vendorKey(line.description);
                if (!key) return false;
                return allVendors || key === vendor;
            })
            .sort((a, b) => {
                const name = String(a.description || "").localeCompare(String(b.description || ""), undefined, {
                    sensitivity: "base",
                });
                if (name) return name;
                const day = String(a.dayId || "").localeCompare(String(b.dayId || ""));
                if (day) return day;
                return String(a.locationName || "").localeCompare(String(b.locationName || ""));
            });
        const total = matched.reduce((s, r) => s + num(r.amount), 0);
        const byLoc = new Map();
        const byVendor = new Map();
        matched.forEach((r) => {
            const locId = r.locationId || r.locationName || "";
            const locPrev = byLoc.get(locId) || {
                locationId: r.locationId,
                locationName: r.locationName || "Facility",
                locationAddress: formatAddress(r.locationAddress),
                entries: 0,
                amount: 0,
            };
            locPrev.entries += 1;
            locPrev.amount += num(r.amount);
            byLoc.set(locId, locPrev);

            const vKey = vendorKey(r.description);
            const vPrev = byVendor.get(vKey) || {
                name: r.description,
                locationIds: new Set(),
                entries: 0,
                amount: 0,
            };
            vPrev.entries += 1;
            vPrev.amount += num(r.amount);
            if (r.locationId || r.locationName) vPrev.locationIds.add(r.locationId || r.locationName);
            if (!vPrev.name && r.description) vPrev.name = r.description;
            byVendor.set(vKey, vPrev);
        });
        const locationTotals = [...byLoc.values()]
            .map((r) => ({
                ...r,
                locationLabel: facilityLabel(r.locationName, r.locationAddress),
            }))
            .sort((a, b) => String(a.locationName).localeCompare(String(b.locationName)));
        const vendorTotals = [...byVendor.values()]
            .map((v) => ({
                name: v.name,
                facilities: v.locationIds.size,
                entries: v.entries,
                amount: v.amount,
            }))
            .sort((a, b) => String(a.name).localeCompare(String(b.name), undefined, { sensitivity: "base" }));
        const locCount = locationTotals.length;
        const tableRows = matched.map((r) => ({
            location: facilityLabel(r.locationName, r.locationAddress),
            date: r.dayId,
            category: r.category,
            description: r.description,
            checkNo: r.checkNo || "",
            amount: num(r.amount),
        }));
        const csvHeader = allLocations
            ? ["Facility", "Date", "Category", "Description", "Check #", "Amount"]
            : ["Date", "Category", "Description", "Check #", "Amount"];
        const csvBody = tableRows.map((r) =>
            allLocations
                ? [r.location, r.date, r.category, r.description, r.checkNo, r.amount]
                : [r.date, r.category, r.description, r.checkNo, r.amount]
        );
        const csvRows = [];
        if (allVendors && vendorTotals.length) {
            csvRows.push(["All vendors"]);
            csvRows.push(["Vendor", "Facilities", "Entries", "Total"]);
            vendorTotals.forEach((r) => csvRows.push([r.name, r.facilities, r.entries, r.amount]));
            csvRows.push(["Total", locCount, matched.length, total]);
            csvRows.push([]);
        }
        if (allLocations && locationTotals.length) {
            csvRows.push(["Totals by facility"]);
            csvRows.push(["Facility", "Entries", "Total"]);
            locationTotals.forEach((r) => csvRows.push([r.locationLabel, r.entries, r.amount]));
            csvRows.push(["Total", matched.length, total]);
            csvRows.push([]);
            csvRows.push(["Date-by-date"]);
        }
        csvRows.push(csvHeader, ...csvBody);
        csvRows.push(
            csvHeader.map((_, i) => (i === 0 ? "Total" : i === csvHeader.length - 1 ? total : ""))
        );

        const vendorLabel = allVendors ? "All vendors" : meta.vendorName || "—";
        return {
            type: "vendor_expenses",
            title: "Vendor expenses",
            meta,
            headline: vendorLabel,
            subhead: meta.monthLabel || "",
            allLocations,
            allVendors,
            ...locationReportExtras(allLocations ? {} : meta),
            summary: [
                { label: "Vendor", value: vendorLabel, format: "text" },
                ...(allVendors ? [{ label: "Vendors", value: vendorTotals.length, format: "number" }] : []),
                { label: "Entries", value: tableRows.length, format: "number" },
                ...(allLocations ? [{ label: "Facilities", value: locCount, format: "number" }] : []),
                { label: "Total", value: total },
            ],
            vendorTotals,
            locationTotals,
            tableRows,
            csvRows,
        };
    }

    window.OplixReportsModel = {
        REPORT_TYPES,
        PERIOD_PRESETS,
        MAX_SPAN_DAYS,
        num,
        toDate,
        intervalFromPreset,
        spanExceedsLimit,
        formatRange,
        formatAddress,
        facilityLabel,
        buildMonthlyBooksReport,
        buildAllLocationsBooksReport,
        buildAllLocationsCompareReport,
        buildAllLocationsDetailReport,
        buildComplianceReport,
        buildLotteryReport,
        buildPayrollReport,
        buildRegisterReport,
        prevMonthIdFrom,
        buildCashReconciliationReport,
        buildAllLocationsCashReconReport,
        buildPayablesReceivablesReport,
        buildBooksPayrollPayoutsReport,
        ALL_VENDORS,
        buildVendorExpenseReport,
        uniqueVendorNames,
        vendorKey,
        isAllVendors,
        buildBooksSupplement,
    };
})();
