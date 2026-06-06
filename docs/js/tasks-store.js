/**
 * Firestore CRUD for location tasks.
 */
(function () {
    const M = () => window.OplixTasksModel;

    function locationRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId);
    }

    function taskColRef(userId, locationId) {
        return locationRef(userId, locationId).collection("tasks");
    }

    function managerTaskRef(userId) {
        return window.oplixDb.collection("users").doc(userId).collection("tasks");
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    function stripUndefined(obj) {
        const out = {};
        Object.keys(obj || {}).forEach((k) => {
            if (obj[k] !== undefined) out[k] = obj[k];
        });
        return out;
    }

    async function appendTaskIdToLocation(userId, locationId, taskId) {
        const ref = locationRef(userId, locationId);
        await window.oplixDb.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const data = snap.exists ? snap.data() : {};
            const tasks = Array.isArray(data.tasks) ? [...data.tasks] : [];
            if (!tasks.includes(taskId)) tasks.push(taskId);
            tx.set(ref, { tasks }, { merge: true });
        });
    }

    async function removeTaskIdFromLocation(userId, locationId, taskId) {
        const ref = locationRef(userId, locationId);
        await window.oplixDb.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) return;
            const data = snap.data() || {};
            const tasks = (Array.isArray(data.tasks) ? data.tasks : []).filter((id) => id !== taskId);
            tx.set(ref, { tasks }, { merge: true });
        });
    }

    async function writeTask(userId, locationId, task, options) {
        const opts = options || {};
        const normalized = M().normalizeTask(task, locationId);
        const payload = stripUndefined({
            ...normalized,
            ...(opts.setCreatedAt
                ? { createdAt: firebase.firestore.FieldValue.serverTimestamp() }
                : {}),
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
        await taskColRef(userId, locationId).doc(normalized.id).set(payload, { merge: true });
        await managerTaskRef(userId).doc(normalized.id).set(payload, { merge: true });
        return normalized.id;
    }

    async function create(userId, locationId, raw) {
        const id = raw?.id || newId();
        const task = M().normalizeTask({ ...raw, id }, locationId);
        await writeTask(userId, locationId, task, { setCreatedAt: true });
        await appendTaskIdToLocation(userId, locationId, id);
        return id;
    }

    async function update(userId, locationId, raw) {
        const task = M().normalizeTask(raw, locationId);
        if (!task.id) throw new Error("Task id is required.");
        await writeTask(userId, locationId, task);
        return task.id;
    }

    async function remove(userId, locationId, taskId) {
        if (!taskId) throw new Error("Task id is required.");
        await taskColRef(userId, locationId).doc(taskId).delete();
        try {
            await managerTaskRef(userId).doc(taskId).delete();
        } catch {
            /* manager mirror may not exist for legacy tasks */
        }
        await removeTaskIdFromLocation(userId, locationId, taskId);
    }

    async function propagateSiblings(userId, currentLocationId, groupId, description, frequency) {
        if (!groupId) return { updated: 0, failed: 0 };
        const locSnap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .get();
        let updated = 0;
        let failed = 0;

        for (const locDoc of locSnap.docs) {
            if (locDoc.id === currentLocationId) continue;
            try {
                const tasksSnap = await taskColRef(userId, locDoc.id).get();
                for (const taskDoc of tasksSnap.docs) {
                    const data = taskDoc.data();
                    if (data.crossLocationGroupId !== groupId) continue;
                    try {
                        await update(userId, locDoc.id, {
                            ...data,
                            id: taskDoc.id,
                            description,
                            frequency,
                        });
                        updated += 1;
                    } catch {
                        failed += 1;
                    }
                }
            } catch {
                failed += 1;
            }
        }
        return { updated, failed };
    }

    async function reviewCompletion(userId, locationId, task, opts) {
        const updated = M().applyReview(task, opts);
        if (!updated) throw new Error("Could not find a completion to review.");
        await update(userId, locationId, updated);
        return updated;
    }

    window.OplixTasksStore = {
        create,
        update,
        remove,
        propagateSiblings,
        reviewCompletion,
        newId,
    };
})();
