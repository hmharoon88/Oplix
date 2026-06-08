/**
 * Web reports — builders for books, compliance, and shift/lottery exports.
 */
(function () {
    const MAX_SPAN_DAYS = 366;

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

    function buildMonthlyBooksReport(agg, meta) {
        const M = window.OplixBooksModel;
        const rows = [];
        const add = (label, value, fmt) => rows.push({ label, value, fmt });

        if (agg.hasGasStation) {
            add("Total sales (merch)", agg.sales);
            (M.gasSalesDetailBreakdownFromAggregate
                ? M.gasSalesDetailBreakdownFromAggregate(agg)
                : agg.salesBreakdown || M.salesBreakdownFromAggregate(agg)
            ).forEach((r) => {
                if (r.label === "Merch sale") return;
                if (num(r.amount) !== 0) add(r.label, r.amount, r.format);
            });
        } else {
            add("Total sales", agg.sales);
            (agg.salesBreakdown || M.salesBreakdownFromAggregate(agg)).forEach((r) => {
                if (num(r.amount) !== 0) add(r.label, r.amount);
            });
            if (num(agg.lotteryCash) !== 0) add("Lottery (not in total sales)", agg.lotteryCash);
            if (num(agg.pulltabCash) !== 0) add("Pulltab (not in total sales)", agg.pulltabCash);
        }

        add("Receivables", agg.receivablesTotal);
        rows.push({ label: "—", value: null, section: true });
        add("Cash expense", agg.cashExpense);
        add("Checks / ACH", agg.checksAch);
        add("Other expense", agg.otherExpense);
        add("Utilities", agg.utilitiesTotal);
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
            summary: [
                { label: agg.hasGasStation ? "Merch sales" : "Total sales", value: agg.sales },
                { label: "Expenses", value: agg.expenses },
                { label: "Net", value: agg.net },
            ],
            rows,
            csvRows: rows
                .filter((r) => !r.section)
                .map((r) => [r.label, r.fmt === "number" ? num(r.value) : num(r.value)]),
        };
    }

    function buildAllLocationsBooksReport(packs, meta) {
        const M = window.OplixBooksModel;
        const tableRows = packs.map((p) => {
            const a = p.aggregate;
            return {
                location: p.locationName,
                hasGas: a.hasGasStation,
                sales: a.sales,
                creditCard: a.creditCard,
                fuel: a.fuelDollars,
                expenses: a.expenses,
                net: a.net,
            };
        });
        const totals = tableRows.reduce(
            (t, r) => ({
                sales: t.sales + r.sales,
                creditCard: t.creditCard + r.creditCard,
                fuel: t.fuel + r.fuel,
                expenses: t.expenses + r.expenses,
                net: t.net + r.net,
            }),
            { sales: 0, creditCard: 0, fuel: 0, expenses: 0, net: 0 }
        );
        const anyGas = tableRows.some((r) => r.hasGas);

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
            anyGas,
            csvRows: [
                anyGas
                    ? ["Facility", "Merch / sales", "Credit card", "Fuel ($)", "Expenses", "Net"]
                    : ["Facility", "Sales", "Expenses", "Net"],
                ...tableRows.map((r) =>
                    anyGas
                        ? [r.location, r.sales, r.creditCard, r.fuel, r.expenses, r.net]
                        : [r.location, r.sales, r.expenses, r.net]
                ),
                anyGas
                    ? ["Total", totals.sales, totals.creditCard, totals.fuel, totals.expenses, totals.net]
                    : ["Total", totals.sales, totals.expenses, totals.net],
            ],
        };
    }

    function buildAllLocationsDetailReport(packs, meta) {
        const M = window.OplixBooksModel;
        const locationSections = packs.map((p) => {
            const agg = p.aggregate;
            const monthly = buildMonthlyBooksReport(agg, {
                locationName: p.locationName,
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
                hasGas: agg.hasGasStation,
                monthlyRows: monthly.rows,
                monthlySummary: monthly.summary,
                dailyRows,
                dailyTotals,
            };
        });

        const totals = locationSections.reduce(
            (t, s) => {
                const sales = s.hasGas ? s.dailyTotals.totalRevenue : s.dailyTotals.sales;
                return {
                    sales: t.sales + sales,
                    expenses: t.expenses + s.dailyTotals.expenses,
                    net: t.net + s.dailyTotals.net,
                };
            },
            { sales: 0, expenses: 0, net: 0 }
        );

        const csvRows = [["Monthly breakdown"]];
        locationSections.forEach((s) => {
            csvRows.push([s.locationName]);
            s.monthlyRows
                .filter((r) => !r.section)
                .forEach((r) => {
                    csvRows.push(["", r.label, num(r.value)]);
                });
            csvRows.push([]);
        });
        csvRows.push(["Daily sales & expenses"]);
        const anyGas = locationSections.some((s) => s.hasGas);
        if (anyGas) {
            csvRows.push([
                "Facility",
                "Day",
                "Merch",
                "Fuel ($)",
                "Pump credit",
                "Revenue",
                "Cash exp.",
                "Checks",
                "Other",
                "Total exp.",
                "Net",
            ]);
            locationSections.forEach((s) => {
                s.dailyRows.forEach((row) => {
                    if (!row.hasData) return;
                    csvRows.push([
                        s.locationName,
                        row.dayId,
                        s.hasGas ? row.merchSale : "",
                        s.hasGas ? row.fuelDollars : "",
                        s.hasGas ? row.creditCard : "",
                        s.hasGas ? row.totalRevenue : row.sales,
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
                "Checks",
                "Other",
                "Total exp.",
                "Net",
            ]);
            locationSections.forEach((s) => {
                s.dailyRows.forEach((row) => {
                    if (!row.hasData) return;
                    csvRows.push([
                        s.locationName,
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
                facility: item._locationName || meta.locationName || "—",
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

    window.OplixReportsModel = {
        REPORT_TYPES,
        PERIOD_PRESETS,
        MAX_SPAN_DAYS,
        num,
        toDate,
        intervalFromPreset,
        spanExceedsLimit,
        formatRange,
        buildMonthlyBooksReport,
        buildAllLocationsBooksReport,
        buildAllLocationsDetailReport,
        buildComplianceReport,
        buildLotteryReport,
        buildPayrollReport,
        buildRegisterReport,
    };
})();
