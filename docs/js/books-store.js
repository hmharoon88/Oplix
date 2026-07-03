/**
 * Firestore persistence for location books (month + daily entries).
 */
(function () {
    const M = () => window.OplixBooksModel;

    const monthCache = new Map();
    const inflight = new Map();
    const LOAD_TIMEOUT_MS = 15000;

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

    function withTimeout(promise, ms, message) {
        return Promise.race([
            promise,
            new Promise((_, reject) => {
                setTimeout(
                    () => reject(new Error(message || "Books load timed out — check your connection.")),
                    ms
                );
            }),
        ]);
    }

    async function readMonthFromFirestore(ref, source) {
        const getOpts = source ? { source } : undefined;
        const [snap, daysSnap] = await Promise.all([
            getOpts ? ref.get(getOpts) : ref.get(),
            getOpts ? ref.collection("days").get(getOpts) : ref.collection("days").get(),
        ]);
        const month = snap.exists ? snap.data() : M().defaultMonthDoc();
        const daysById = {};
        daysSnap.docs.forEach((d) => {
            daysById[d.id] = { ...d.data(), _dayId: d.id };
        });
        return { month, daysById };
    }

    function refreshMonthFromServer(userId, locationId, monthId) {
        const key = cacheKey(userId, locationId, monthId);
        const ref = monthRef(userId, locationId, monthId);
        readMonthFromFirestore(ref)
            .then((payload) => {
                monthCache.set(key, payload);
            })
            .catch(() => {});
    }

    async function loadMonth(userId, locationId, monthId, options = {}) {
        const key = cacheKey(userId, locationId, monthId);
        if (!options.bypassCache && monthCache.has(key)) {
            return cloneMonthPayload(monthCache.get(key));
        }
        if (inflight.has(key)) {
            return inflight.get(key);
        }

        const ref = monthRef(userId, locationId, monthId);
        const timeoutMs = options.timeoutMs ?? LOAD_TIMEOUT_MS;

        const promise = (async () => {
            try {
                const cached = await withTimeout(
                    readMonthFromFirestore(ref, "cache"),
                    2500,
                    "cache miss"
                );
                monthCache.set(key, cached);
                refreshMonthFromServer(userId, locationId, monthId);
                return cloneMonthPayload(cached);
            } catch {
                const fresh = await withTimeout(readMonthFromFirestore(ref), timeoutMs);
                monthCache.set(key, fresh);
                return cloneMonthPayload(fresh);
            }
        })()
            .catch((err) => {
                inflight.delete(key);
                throw err;
            })
            .then((result) => {
                inflight.delete(key);
                return result;
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
        const ref = dayRef(userId, locationId, monthId, dayId);
        const snap = await ref.get();
        const existing = snap.exists ? snap.data() : null;
        if (existing?.closed && day.closed !== false) {
            throw new Error("This day is closed. Reopen it before saving changes.");
        }
        const payload = {
            ...day,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        await ref.set(payload, { merge: true });
        invalidateMonth(userId, locationId, monthId);
    }

    /** Load many months for comparison (cap to avoid huge reads). */
    async function loadMonthsForCompare(userId, locationIds, monthIds, options) {
        const facilityTypesById = (options && options.facilityTypesById) || {};
        const booksFieldConfigsById = (options && options.booksFieldConfigsById) || {};
        const tasks = [];
        for (const locationId of locationIds) {
            const hasGasStation = facilityTypesById[locationId] === "c_store_gas";
            const booksFieldConfig = booksFieldConfigsById[locationId] || null;
            for (const monthId of monthIds) {
                tasks.push(
                    loadMonth(userId, locationId, monthId)
                        .then(({ month, daysById }) => ({
                            locationId,
                            monthId,
                            month,
                            daysById,
                            aggregate: M().aggregateMonth(month, daysById, {
                                hasGasStation,
                                booksFieldConfig,
                            }),
                        }))
                        .catch(() => ({
                            locationId,
                            monthId,
                            month: M().defaultMonthDoc(),
                            daysById: {},
                            aggregate: M().aggregateMonth(M().defaultMonthDoc(), {}, {
                                hasGasStation,
                                booksFieldConfig,
                            }),
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
        hasCachedMonth,
        invalidateMonth,
    };
})();
