/**
 * Load data for web reports.
 */
(function () {
    const M = () => window.OplixBooksModel;
    const Books = () => window.OplixBooksStore;
    const Compliance = () => window.OplixComplianceStore;

    function col(userId, locationId, name) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(name);
    }

    async function fetchSub(userId, locationId, name) {
        const snap = await col(userId, locationId, name).get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    function formatLocationAddress(value) {
        return String(value || "")
            .trim()
            .replace(/\s*\n+\s*/g, ", ");
    }

    async function loadBooksAggregate(userId, locationId, monthId, hasGasStation) {
        const { month, daysById } = await Books().loadMonth(userId, locationId, monthId);
        const aggregate = M().aggregateMonth(month, daysById, { hasGasStation });
        // Facility receivables for itemized report lines (open + received this month).
        try {
            const facilityReceivables = await fetchSub(userId, locationId, "receivables");
            aggregate.facilityReceivables = facilityReceivables;
        } catch (_) {
            aggregate.facilityReceivables = [];
        }
        return aggregate;
    }

    async function loadAllLocationsBooks(userId, locations, monthId) {
        const packs = [];
        for (const loc of locations) {
            const hasGas = loc.facilityType === "c_store_gas";
            const aggregate = await loadBooksAggregate(userId, loc.id, monthId, hasGas);
            packs.push({
                locationId: loc.id,
                locationName: loc.name || "Facility",
                locationAddress: formatLocationAddress(loc.address),
                aggregate,
            });
        }
        return packs;
    }

    async function loadAllLocationsBooksDetail(userId, locations, monthId) {
        const packs = [];
        for (const loc of locations) {
            const hasGas = loc.facilityType === "c_store_gas";
            const { month, daysById } = await Books().loadMonth(userId, loc.id, monthId);
            const aggregate = M().aggregateMonth(month, daysById, { hasGasStation: hasGas });
            try {
                aggregate.facilityReceivables = await fetchSub(userId, loc.id, "receivables");
            } catch (_) {
                aggregate.facilityReceivables = [];
            }
            packs.push({
                locationId: loc.id,
                locationName: loc.name || "Facility",
                locationAddress: formatLocationAddress(loc.address),
                hasGasStation: hasGas,
                aggregate,
                daysById,
            });
        }
        return packs;
    }

    async function loadPayablesReceivables(userId, locationId, locationName, locationAddress) {
        const [payables, receivables] = await Promise.all([
            fetchSub(userId, locationId, "payables"),
            fetchSub(userId, locationId, "receivables"),
        ]);
        return {
            locationId,
            locationName: locationName || "Facility",
            locationAddress: formatLocationAddress(locationAddress),
            payables,
            receivables,
        };
    }

    async function loadAllLocationsPayablesReceivables(userId, locations) {
        const packs = [];
        for (const loc of locations) {
            packs.push(
                await loadPayablesReceivables(userId, loc.id, loc.name, loc.address)
            );
        }
        return packs;
    }

    async function loadCompliance(userId, locationId) {
        if (!Compliance()) return [];
        return Compliance().list(userId, locationId);
    }

    async function loadComplianceAll(userId, locations) {
        const all = [];
        for (const loc of locations) {
            const items = await loadCompliance(userId, loc.id);
            items.forEach((item) => {
                all.push({
                    ...item,
                    _locationName: loc.name || "Facility",
                    _locationId: loc.id,
                    _locationAddress: formatLocationAddress(loc.address),
                });
            });
        }
        return all;
    }

    async function loadShiftReportData(userId, locationId) {
        const [shifts, employees, lotteryForms] = await Promise.all([
            fetchSub(userId, locationId, "shifts"),
            fetchSub(userId, locationId, "employees"),
            fetchSub(userId, locationId, "lotteryForms"),
        ]);
        return { shifts, employees, lotteryForms };
    }

    function collectDailyExpenseLines(daysById, locationId, locationName, locationAddress) {
        const lines = [];
        const lists = [
            ["cashExpenses", "Cash expense"],
            ["checksAch", "Check / ACH"],
            ["otherExpenses", "Other expense"],
        ];
        Object.keys(daysById || {})
            .sort()
            .forEach((dayId) => {
                const day = daysById[dayId] || {};
                lists.forEach(([key, category]) => {
                    (day[key] || []).forEach((row) => {
                        const description = String(row.description || "").trim();
                        const checkNo = String(row.checkNo || "").trim();
                        const amount = M().num(row.amount);
                        if (!description && !checkNo && amount === 0) return;
                        if (!description) return;
                        lines.push({
                            locationId,
                            locationName,
                            locationAddress: formatLocationAddress(locationAddress),
                            dayId: row.date || dayId,
                            category,
                            description,
                            checkNo,
                            amount,
                        });
                    });
                });
            });
        return lines;
    }

    async function loadVendorExpenseLines(userId, locations, monthId) {
        const lines = [];
        for (const loc of locations || []) {
            const { daysById } = await Books().loadMonth(userId, loc.id, monthId);
            lines.push(
                ...collectDailyExpenseLines(
                    daysById,
                    loc.id,
                    loc.name || "Facility",
                    loc.address
                )
            );
        }
        return lines;
    }

    window.OplixReportsStore = {
        loadBooksAggregate,
        loadAllLocationsBooks,
        loadAllLocationsBooksDetail,
        loadPayablesReceivables,
        loadAllLocationsPayablesReceivables,
        loadCompliance,
        loadComplianceAll,
        loadShiftReportData,
        loadVendorExpenseLines,
    };
})();
