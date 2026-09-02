/**
 * Firestore CRUD for payrollRuns (canonical) and legacy payrollEntries.
 */
(function () {
    const M = () => window.OplixPayrollModel;

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(M().COLLECTION);
    }

    function runsColRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(M().RUNS_COLLECTION);
    }

    function managerEmployeeRef(userId, employeeId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("employees")
            .doc(employeeId);
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) => M().normalizeEntry({ id: d.id, ...d.data() }, locationId));
    }

    async function listRuns(userId, locationId) {
        const snap = await runsColRef(userId, locationId).orderBy("periodEnd", "desc").get();
        return snap.docs.map((d) => M().normalizeRun({ id: d.id, ...d.data() }, locationId));
    }

    async function save(userId, locationId, entry) {
        const e = M().normalizeEntry(entry, locationId);
        const id = e.id || newId();
        const payload = {
            ...e,
            pay: M().calcPay(e.hours, e.hourlyRate),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!entry.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        } else {
            payload.createdAt = entry.createdAt;
        }
        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
        return id;
    }

    async function saveRun(userId, locationId, run) {
        const r = M().normalizeRun(run, locationId);
        const id = r.id || newId();
        const payload = {
            id,
            locationId,
            periodStart: firebase.firestore.Timestamp.fromDate(r.periodStart),
            periodEnd: firebase.firestore.Timestamp.fromDate(r.periodEnd),
            note: r.note,
            lines: r.lines,
            totalPay: r.totalPay,
            totalHours: r.totalHours,
            totalGrossPay: r.totalGrossPay,
            totalLoanDeductions: r.totalLoanDeductions,
            createdSource: r.createdSource || "web",
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!run.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        } else if (run.createdAt?.toDate) {
            payload.createdAt = run.createdAt;
        } else if (run.createdAt instanceof Date) {
            payload.createdAt = firebase.firestore.Timestamp.fromDate(run.createdAt);
        } else {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await runsColRef(userId, locationId).doc(id).set(payload, { merge: true });
        return { ...r, id };
    }

    async function remove(userId, locationId, entryId) {
        await colRef(userId, locationId).doc(entryId).delete();
    }

    async function listEmployees(userId, locationId) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("employees")
            .get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    async function fetchManagerEmployee(userId, employeeId) {
        const snap = await managerEmployeeRef(userId, employeeId).get();
        return snap.exists ? { id: snap.id, ...snap.data() } : null;
    }

    async function enrichEmployeesFromManager(userId, employees) {
        const enriched = [];
        for (const employee of employees || []) {
            let merged = { ...employee };
            try {
                const manager = await fetchManagerEmployee(userId, employee.id);
                if (manager) {
                    if (manager.hourlyRate != null && merged.hourlyRate == null) {
                        merged.hourlyRate = manager.hourlyRate;
                    }
                    if (Array.isArray(manager.loans) && manager.loans.length) {
                        merged.loans = manager.loans;
                    }
                    if (manager.assignedLocationIds) {
                        merged.assignedLocationIds = manager.assignedLocationIds;
                    }
                }
            } catch {
                /* use location copy */
            }
            enriched.push(merged);
        }
        return enriched.sort((a, b) =>
            String(a.name || a.username || "").localeCompare(String(b.name || b.username || ""))
        );
    }

    async function applyLoanBalances(userId, locationId, lines) {
        for (const line of lines || []) {
            const deductions = line.loanDeductions || [];
            if (!deductions.length) continue;

            const snap = await managerEmployeeRef(userId, line.id).get();
            if (!snap.exists) continue;

            const managerEmployee = { id: snap.id, ...snap.data() };
            const loans = Array.isArray(managerEmployee.loans) ? [...managerEmployee.loans] : [];

            deductions.forEach((deduction) => {
                const loanIndex = loans.findIndex((l) => l.id === deduction.id);
                if (loanIndex < 0) return;
                const loan = { ...loans[loanIndex] };
                loan.remainingBalance = Math.max(0, num(loan.remainingBalance) - num(deduction.amount));
                if (loan.remainingBalance < 0.01) {
                    loan.remainingBalance = 0;
                    loan.isActive = false;
                }
                loans[loanIndex] = loan;
            });

            const updated = { ...managerEmployee, loans };
            await managerEmployeeRef(userId, line.id).set(updated, { merge: true });

            const locationIds = new Set([...(updated.assignedLocationIds || []), locationId]);
            for (const locId of locationIds) {
                await window.oplixDb
                    .collection("users")
                    .doc(userId)
                    .collection("locations")
                    .doc(locId)
                    .collection("employees")
                    .doc(line.id)
                    .set({ ...updated, locationId: locId }, { merge: true });
            }
        }
    }

    function num(v) {
        const n = parseFloat(v);
        return Number.isFinite(n) ? n : 0;
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    async function syncRunToBooks(userId, locationId, run) {
        const Books = () => window.OplixBooksStore;
        const B = () => window.OplixBooksModel;
        const monthId = B().monthIdFromDate(run.periodEnd);
        const { month, daysById } = await Books().loadMonth(userId, locationId, monthId);
        if (B().isMonthClosed(month)) {
            throw new Error(
                "Daily books for this month are closed. Reopen the month before syncing payroll."
            );
        }
        const updated = B().applyPayrollRunToMonth(month, run);
        await Books().saveMonth(userId, locationId, monthId, updated);
        return {
            month: updated,
            daysById,
            monthId,
            payrollTotal: B().payrollTotalFrom(updated),
        };
    }

    async function syncToBooksMonth(userId, locationId, monthId) {
        const Books = () => window.OplixBooksStore;
        const B = () => window.OplixBooksModel;
        const allEntries = await list(userId, locationId);
        const fromEntries = M().buildBooksPayrollFromEntries(
            allEntries,
            monthId,
            B()
        );
        const { month, daysById } = await Books().loadMonth(userId, locationId, monthId);
        const merged = B().mergePayrollWithRunSyncs(fromEntries, month.payrollRunSyncs);
        const updated = {
            ...month,
            payrollLines: merged.payrollLines,
            payroll: merged.payroll,
            payrollRunSyncs: month.payrollRunSyncs || {},
        };
        await Books().saveMonth(userId, locationId, monthId, updated);
        return { month: updated, daysById, payrollLines: merged.payrollLines, payrollTotal: B().payrollTotalFrom(updated) };
    }

    async function syncAllBooksMonths(userId, locationId, extraMonthIds) {
        const allEntries = await list(userId, locationId);
        const months = M().affectedMonthIds(allEntries, extraMonthIds);
        const results = [];
        for (const monthId of months) {
            results.push(await syncToBooksMonth(userId, locationId, monthId));
        }
        return results;
    }

    window.OplixPayrollStore = {
        list,
        listRuns,
        save,
        saveRun,
        remove,
        listEmployees,
        enrichEmployeesFromManager,
        applyLoanBalances,
        newId,
        syncRunToBooks,
        syncToBooksMonth,
        syncAllBooksMonths,
    };
})();
