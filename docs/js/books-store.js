/**
 * Firestore persistence for location books (month + daily entries).
 */
(function () {
    const M = () => window.OplixBooksModel;

    const monthCache = new Map();
    const inflight = new Map();

    function cacheKey(userId, locationId, monthId) {
        return `${userId}|${locationId}|${monthId}`;
    }

    function cloneMonthPayload(payload) {
        return {
            month: { ...payload.month },
            daysById: Object.fromEntries(
                Object.entries(payload.daysById).map(([id, day]) => [id, { ...day }])
            ),
        };
    }

    function invalidateMonth(userId, locationId, monthId) {
        monthCache.delete(cacheKey(userId, locationId, monthId));
    }

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

    function hasCachedMonth(userId, locationId, monthId) {
        return monthCache.has(cacheKey(userId, locationId, monthId));
    }

    async function loadMonth(userId, locationId, monthId, options = {}) {
        const key = cacheKey(userId, locationId, monthId);
        if (!options.bypassCache && monthCache.has(key)) {
            return cloneMonthPayload(monthCache.get(key));
        }
        if (inflight.has(key)) {
            return inflight.get(key).then(cloneMonthPayload);
        }

        const ref = monthRef(userId, locationId, monthId);
        const promise = Promise.all([ref.get(), ref.collection("days").get()])
            .then(([snap, daysSnap]) => {
                const month = snap.exists ? snap.data() : M().defaultMonthDoc();
                const daysById = {};
                daysSnap.docs.forEach((d) => {
                    daysById[d.id] = { ...d.data(), _dayId: d.id };
                });
                const payload = { month, daysById };
                monthCache.set(key, payload);
                inflight.delete(key);
                return cloneMonthPayload(payload);
            })
            .catch((err) => {
                inflight.delete(key);
                throw err;
            });

        inflight.set(key, promise);
        return promise;
    }

    async function saveMonth(userId, locationId, monthId, month) {
        const payload = {
            ...month,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        await monthRef(userId, locationId, monthId).set(payload, { merge: true });
        invalidateMonth(userId, locationId, monthId);
    }

    async function saveDay(userId, locationId, monthId, dayId, day) {
        const payload = {
            ...day,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        await dayRef(userId, locationId, monthId, dayId).set(payload, { merge: true });
        invalidateMonth(userId, locationId, monthId);
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

    function prefetchMonths(userId, locationIds, monthIds, options) {
        if (!userId || !locationIds.length || !monthIds.length) return;
        loadMonthsForCompare(userId, locationIds, monthIds, options || {}).catch(() => {});
    }

    window.OplixBooksStore = {
        loadMonth,
        saveMonth,
        saveDay,
        loadMonthsForCompare,
        hasCachedMonth,
        invalidateMonth,
        prefetchMonths,
    };
})();
