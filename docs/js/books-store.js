/**
 * Firestore persistence for location books (month + daily entries).
 */
(function () {
    const M = () => window.OplixBooksModel;

    function monthRef(userId, locationId, monthId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("books")
            .doc(monthId);
    }

    function dayRef(userId, locationId, monthId, dayId) {
        return monthRef(userId, locationId, monthId).collection("days").doc(dayId);
    }

    async function loadMonth(userId, locationId, monthId) {
        const snap = await monthRef(userId, locationId, monthId).get();
        const month = snap.exists ? snap.data() : M().defaultMonthDoc();
        const daysSnap = await monthRef(userId, locationId, monthId).collection("days").get();
        const daysById = {};
        daysSnap.docs.forEach((d) => {
            daysById[d.id] = { ...d.data(), _dayId: d.id };
        });
        return { month, daysById };
    }

    async function saveMonth(userId, locationId, monthId, month) {
        const payload = {
            ...month,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        await monthRef(userId, locationId, monthId).set(payload, { merge: true });
    }

    async function saveDay(userId, locationId, monthId, dayId, day) {
        const payload = {
            ...day,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        await dayRef(userId, locationId, monthId, dayId).set(payload, { merge: true });
    }

    /** Load many months for comparison (cap to avoid huge reads). */
    async function loadMonthsForCompare(userId, locationIds, monthIds, options) {
        const facilityTypesById = (options && options.facilityTypesById) || {};
        const tasks = [];
        for (const locationId of locationIds) {
            const hasGasStation = facilityTypesById[locationId] === "c_store_gas";
            for (const monthId of monthIds) {
                tasks.push(
                    loadMonth(userId, locationId, monthId)
                        .then(({ month, daysById }) => ({
                            locationId,
                            monthId,
                            month,
                            daysById,
                            aggregate: M().aggregateMonth(month, daysById, { hasGasStation }),
                        }))
                        .catch(() => ({
                            locationId,
                            monthId,
                            month: M().defaultMonthDoc(),
                            daysById: {},
                            aggregate: M().aggregateMonth(M().defaultMonthDoc(), {}, { hasGasStation }),
                        }))
                );
            }
        }
        return Promise.all(tasks);
    }

    window.OplixBooksStore = {
        loadMonth,
        saveMonth,
        saveDay,
        loadMonthsForCompare,
    };
})();
