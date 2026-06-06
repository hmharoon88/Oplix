/**
 * Location CRUD — users/{uid}/locations/{id}.
 */
(function () {
    function locRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId);
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    async function deleteQueryDocs(query) {
        const snap = await query.get();
        if (snap.empty) return;
        const batch = window.oplixDb.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (snap.size >= 400) await deleteQueryDocs(query);
    }

    async function deleteSubcollection(userId, locationId, name) {
        const ref = locRef(userId, locationId).collection(name);
        await deleteQueryDocs(ref);
    }

    async function deleteBooks(userId, locationId) {
        const monthsSnap = await locRef(userId, locationId).collection("books").get();
        for (const monthDoc of monthsSnap.docs) {
            await deleteQueryDocs(monthDoc.ref.collection("days"));
            await monthDoc.ref.delete();
        }
    }

    async function deleteLocationEmployees(userId, locationId) {
        const snap = await locRef(userId, locationId).collection("employees").get();
        for (const doc of snap.docs) {
            await doc.ref.delete();
            try {
                await window.oplixDb.collection("users").doc(doc.id).delete();
            } catch {
                /* ignore */
            }
        }
    }

    async function deleteManagerTasksForLocation(userId, locationId) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("tasks")
            .where("locationId", "==", locationId)
            .get();
        if (snap.empty) return;
        const batch = window.oplixDb.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
    }

    async function createLocation(userId, { name, address, facilityType }) {
        const id = newId();
        const location = {
            id,
            name: name.trim(),
            address: address.trim(),
            managerId: userId,
            employees: [],
            tasks: [],
            lotteryForms: [],
            facilityType: facilityType === "c_store_gas" ? "c_store_gas" : "c_store",
        };
        await locRef(userId, id).set(location);
        return location;
    }

    async function updateLocation(userId, locationId, { name, address, facilityType }) {
        const payload = {
            name: name.trim(),
            address: address.trim(),
        };
        if (facilityType) {
            payload.facilityType =
                facilityType === "c_store_gas" ? "c_store_gas" : "c_store";
        }
        await locRef(userId, locationId).set(payload, { merge: true });
        const snap = await locRef(userId, locationId).get();
        return snap.exists ? { id: locationId, ...snap.data() } : null;
    }

    async function deleteLocation(userId, locationId) {
        await deleteLocationEmployees(userId, locationId);
        await deleteManagerTasksForLocation(userId, locationId);

        const subcollections = [
            "tasks",
            "shifts",
            "lotteryForms",
            "payables",
            "receivables",
            "reminders",
            "documents",
            "vendors",
            "utilityProviders",
            "servicers",
            "complianceItems",
            "payrollEntries",
        ];
        for (const name of subcollections) {
            await deleteSubcollection(userId, locationId, name);
        }
        await deleteBooks(userId, locationId);
        await locRef(userId, locationId).delete();
    }

    window.OplixLocationStore = {
        createLocation,
        updateLocation,
        deleteLocation,
        newId,
    };
})();
