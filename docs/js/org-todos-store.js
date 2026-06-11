/**
 * Firestore CRUD for organization-level home to-dos.
 */
(function () {
    const M = () => window.OplixOrgTodosModel;

    function colRef(userId) {
        return window.oplixDb.collection("users").doc(userId).collection(M().COLLECTION);
    }

    async function list(userId) {
        const snap = await colRef(userId).get();
        return snap.docs.map((d) => M().normalizeItem({ id: d.id, ...d.data() }));
    }

    async function save(userId, id, data) {
        const payload = {
            ...data,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        if (!data.createdAt) {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await colRef(userId).doc(id).set(payload, { merge: true });
    }

    async function remove(userId, id) {
        await colRef(userId).doc(id).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixOrgTodosStore = {
        list,
        save,
        remove,
        newId,
    };
})();
