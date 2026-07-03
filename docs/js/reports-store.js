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

    async function loadBooksAggregate(userId, locationId, monthId, hasGasStation) {
        const { month, daysById } = await Books().loadMonth(userId, locationId, monthId);
        return M().aggregateMonth(month, daysById, { hasGasStation });
    }

    async function loadAllLocationsBooks(userId, locations, monthId) {
        const packs = [];
        for (const loc of locations) {
            const hasGas = loc.facilityType === "c_store_gas";
            const aggregate = await loadBooksAggregate(userId, loc.id, monthId, hasGas);
            packs.push({
                locationId: loc.id,
                locationName: loc.name || "Facility",
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
            packs.push({
                locationId: loc.id,
                locationName: loc.name || "Facility",
                hasGasStation: hasGas,
                aggregate: M().aggregateMonth(month, daysById, { hasGasStation: hasGas }),
                daysById,
            });
        }
        return packs;
    }

    async function loadPayablesReceivables(userId, locationId, locationName) {
        const [payables, receivables] = await Promise.all([
            fetchSub(userId, locationId, "payables"),
            fetchSub(userId, locationId, "receivables"),
        ]);
        return {
            locationId,
            locationName: locationName || "Facility",
            payables,
            receivables,
        };
    }

    async function loadAllLocationsPayablesReceivables(userId, locations) {
        const packs = [];
        for (const loc of locations) {
            packs.push(await loadPayablesReceivables(userId, loc.id, loc.name));
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
                all.push({ ...item, _locationName: loc.name || "Facility", _locationId: loc.id });
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

    window.OplixReportsStore = {
        loadBooksAggregate,
        loadAllLocationsBooks,
        loadAllLocationsBooksDetail,
        loadPayablesReceivables,
        loadAllLocationsPayablesReceivables,
        loadCompliance,
        loadComplianceAll,
        loadShiftReportData,
    };
})();
