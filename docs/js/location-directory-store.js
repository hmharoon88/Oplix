/**
 * Firestore CRUD for location directory subcollections (vendors, utilityProviders, servicers).
 */
(function () {
    const M = () => window.OplixLocationDirectoryModel;

    function colRef(userId, locationId, collectionName) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(collectionName);
    }

    async function list(userId, locationId, collectionName) {
        const snap = await colRef(userId, locationId, collectionName).get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    async function ensureDefaultUtilityProviders(userId, locationId) {
        const B = window.OplixBooksModel;
        if (!B?.UTILITY_KEYS) return;
        const existing = await list(userId, locationId, M().COLLECTIONS.utilityProviders);
        const have = new Set(existing.map((p) => p.utilityType || p.id));
        await Promise.all(
            B.UTILITY_KEYS.filter((u) => !have.has(u.key)).map((u) =>
                save(userId, locationId, M().COLLECTIONS.utilityProviders, u.key, {
                    ...M().defaultUtilityProvider(u.key),
                    isDefault: true,
                })
            )
        );
    }

    async function loadAll(userId, locationId) {
        await ensureDefaultUtilityProviders(userId, locationId);
        const GV = window.OplixGlobalVendorsStore;
        const [vendors, utilityProviders, servicers] = await Promise.all([
            GV
                ? GV.list(userId).then((rows) =>
                      rows
                          .map((v) => ({ ...M().normalizeVendor(v), id: v.id }))
                          .filter((v) => v.active !== false)
                  )
                : list(userId, locationId, M().COLLECTIONS.vendors),
            list(userId, locationId, M().COLLECTIONS.utilityProviders),
            list(userId, locationId, M().COLLECTIONS.servicers),
        ]);
        return {
            vendors,
            utilityProviders: M().sortUtilityProviders(utilityProviders),
            servicers,
        };
    }

    async function save(userId, locationId, collectionName, id, data) {
        const payload = {
            ...data,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!data.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await colRef(userId, locationId, collectionName).doc(id).set(payload, { merge: true });
    }

    async function remove(userId, locationId, collectionName, id) {
        await colRef(userId, locationId, collectionName).doc(id).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixLocationDirectoryStore = {
        list,
        loadAll,
        ensureDefaultUtilityProviders,
        save,
        remove,
        newId,
    };
})();
