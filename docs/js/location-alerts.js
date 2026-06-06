/**
 * Per-location Needs Attention alerts — mirrors LocationAlertsViewModel.swift
 */
(function () {
    const VARIANCE_THRESHOLD = 5;
    const VARIANCE_CRITICAL = 20;
    const UNCLOSED_SHIFT_HOURS = 12;
    const VARIANCE_LOOKBACK_DAYS = 7;
    const MISSING_REGISTER_LOOKBACK_DAYS = 7;
    const LOTTERY_ACTIVITY_DAYS = 30;
    const DOC_EXPIRY_DAYS = 30;
    const WEEKDAY_KEYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

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

    function addDays(d, n) {
        const x = new Date(d);
        x.setDate(x.getDate() + n);
        return x;
    }

    function formatDateMedium(d) {
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function formatCurrency(amount) {
        return new Intl.NumberFormat("en-US", {
            style: "currency",
            currency: "USD",
        }).format(amount || 0);
    }

    function shiftIsActive(shift) {
        return shift.clockInTime && !shift.clockOutTime;
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

    function employeeWorksOn(employee, date) {
        const schedule = employee.weeklySchedule;
        if (!schedule) return false;
        const key = WEEKDAY_KEYS[date.getDay()];
        const day = schedule[key];
        return day && day.isWorking !== false;
    }

    function makeVarianceAlert(id, kind, value, date, sortKey) {
        const severity = Math.abs(value) >= VARIANCE_CRITICAL ? 0 : 1;
        const label = value < 0 ? "SHORT" : "OVER";
        const kindCap = kind.charAt(0).toUpperCase() + kind.slice(1);
        return {
            id,
            severity,
            title: `${kindCap} ${label} ${formatCurrency(Math.abs(value))}`,
            subtitle: formatDateMedium(date),
            sortKey,
        };
    }

    function buildLocationAlerts({
        locationId,
        shifts,
        forms,
        payables,
        employees,
        documents,
        managerTasks,
    }) {
        const alerts = [];
        const now = new Date();
        const todayStart = startOfDay(now);
        const cutoffUnclosed = new Date(now.getTime() - UNCLOSED_SHIFT_HOURS * 3600000);
        const cutoffVariance = addDays(now, -VARIANCE_LOOKBACK_DAYS);
        const cutoffRegister = addDays(now, -MISSING_REGISTER_LOOKBACK_DAYS);
        const nameLookup = {};
        employees.forEach((e) => {
            nameLookup[e.id] = e.name || e.username || "Employee";
        });

        for (const shift of shifts) {
            const clockIn = toDate(shift.clockInTime);
            if (shiftIsActive(shift) && clockIn && clockIn < cutoffUnclosed) {
                const name = nameLookup[shift.employeeId] || "Employee";
                const hours = Math.floor((now - clockIn) / 3600000);
                alerts.push({
                    id: `clockout_${shift.id}`,
                    severity: 0,
                    title: `${name} forgot to clock out`,
                    subtitle: `clocked in ${hours}h ago`,
                    sortKey: 0,
                });
            }
            const clockOut = toDate(shift.clockOutTime);
            if (clockOut && clockOut >= cutoffRegister && !shiftHasRegisterData(shift)) {
                const hours = shiftHoursWorked(shift);
                if (hours == null || hours >= 1) {
                    const name = nameLookup[shift.employeeId] || "Employee";
                    alerts.push({
                        id: `noregister_${shift.id}`,
                        severity: 0,
                        title: "Register data missing",
                        subtitle: `${name}'s shift · ${formatDateMedium(clockOut)}`,
                        sortKey: 1,
                    });
                }
            }
            const dateRef =
                toDate(shift.registerClosedAt) || toDate(shift.clockOutTime);
            if (dateRef && dateRef >= cutoffVariance) {
                const regs = shift.registers || [];
                if (regs.length) {
                    regs.forEach((reg, i) => {
                        const v = reg.overShort;
                        if (v != null && Math.abs(v) >= VARIANCE_THRESHOLD) {
                            alerts.push(
                                makeVarianceAlert(
                                    `regvar_${shift.id}_${i}`,
                                    "register",
                                    v,
                                    dateRef,
                                    10
                                )
                            );
                        }
                    });
                } else if (shift.overShort != null && Math.abs(shift.overShort) >= VARIANCE_THRESHOLD) {
                    alerts.push(
                        makeVarianceAlert(
                            `regvar_legacy_${shift.id}`,
                            "register",
                            shift.overShort,
                            dateRef,
                            10
                        )
                    );
                }
            }
        }

        const activityCutoff = addDays(now, -LOTTERY_ACTIVITY_DAYS);
        const hasLottery = forms.some((f) => {
            const t = toDate(f.submittedAt);
            return t && t >= activityCutoff;
        });
        if (hasLottery) {
            const yesterday = addDays(todayStart, -1);
            const submittedYesterday = forms.some((f) => {
                const t = toDate(f.submittedAt);
                return t && t >= yesterday && t < todayStart;
            });
            if (!submittedYesterday) {
                alerts.push({
                    id: `lotteryclose_${locationId}`,
                    severity: 0,
                    title: "Lottery not closed",
                    subtitle: `No submission for ${formatDateMedium(yesterday)}`,
                    sortKey: 2,
                });
            }
        }

        for (const form of forms) {
            const submitted = toDate(form.submittedAt);
            const v = form.shiftSummary?.overShort;
            if (submitted && submitted >= cutoffVariance && v != null && Math.abs(v) >= VARIANCE_THRESHOLD) {
                alerts.push(
                    makeVarianceAlert(`lotvar_${form.id}`, "lottery", v, submitted, 11)
                );
            }
        }

        const overdue = payables.filter((p) => {
            if (p.isPaid) return false;
            const due = toDate(p.dueDate);
            return due && startOfDay(due) < todayStart;
        });
        if (overdue.length) {
            const total = overdue.reduce((s, p) => s + (p.amount || 0), 0);
            alerts.push({
                id: `payables_${locationId}`,
                severity: 2,
                title: `${overdue.length} payable${overdue.length === 1 ? "" : "s"} overdue · ${formatCurrency(total)}`,
                subtitle: "",
                sortKey: 20,
            });
        }

        const docCutoff = addDays(now, DOC_EXPIRY_DAYS);
        for (const doc of documents) {
            const exp = toDate(doc.expiryDate);
            if (!exp || exp < now || exp > docCutoff) continue;
            const days = Math.max(0, Math.floor((exp - now) / 86400000));
            alerts.push({
                id: `doc_${doc.id}`,
                severity: days <= 7 ? 1 : 2,
                title: `${doc.name || "Document"} expires in ${days} day${days === 1 ? "" : "s"}`,
                subtitle: "",
                sortKey: 21,
            });
        }

        const weekStart = (() => {
            const d = new Date(now);
            const day = d.getDay();
            const diff = day === 0 ? 6 : day - 1;
            d.setDate(d.getDate() - diff);
            return startOfDay(d);
        })();

        for (const emp of employees) {
            if (!emp.weeklySchedule) continue;
            let workingDays = 0;
            for (let i = 0; i < 7; i++) {
                if (employeeWorksOn(emp, addDays(weekStart, i))) workingDays += 1;
            }
            if (workingDays === 0) {
                alerts.push({
                    id: `schedgap_${emp.id}`,
                    severity: 2,
                    title: `${emp.name || "Employee"} has no shifts this week`,
                    subtitle: "",
                    sortKey: 30,
                });
            }
        }

        const here = (managerTasks || []).filter((t) => t.locationId === locationId);
        const disapproved = here.filter((task) =>
            Object.values(task.employeeCompletions || {}).some((c) => c.isApproved === false)
        ).length;
        if (disapproved > 0) {
            alerts.push({
                id: `disapp_${locationId}`,
                severity: 1,
                title: `${disapproved} task${disapproved === 1 ? "" : "s"} need rework`,
                subtitle: "",
                sortKey: 12,
            });
        }

        alerts.sort((a, b) => {
            if (a.severity !== b.severity) return a.severity - b.severity;
            return a.sortKey - b.sortKey;
        });

        return alerts;
    }

    window.OplixLocationAlerts = { buildLocationAlerts };
})();
