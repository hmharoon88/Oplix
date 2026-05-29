/**
 * Firestore CRUD for complianceItems subcollection.
 */
(function () {
    const M = () => window.OplixComplianceModel;

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(M().COLLECTION);
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) => M().normalizeItem({ id: d.id, ...d.data() }));
    }

    async function save(userId, locationId, id, data) {
        const payload = {
            ...data,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!data.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
    }

    async function remove(userId, locationId, id) {
        await colRef(userId, locationId).doc(id).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixComplianceStore = {
        list,
        save,
        remove,
        newId,
    };
})();
