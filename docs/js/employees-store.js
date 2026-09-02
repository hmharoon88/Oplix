/**
 * Manager-level employees — Firestore CRUD.
 */
(function () {
    const PROVISIONING_APP = "OplixEmployeeProvisioning";

    function managerCol(userId) {
        return window.oplixDb.collection("users").doc(userId).collection("employees");
    }

    function locCol(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection("employees");
    }

    function locRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId);
    }

    function provisioningAuth() {
        let app;
        try {
            app = firebase.app(PROVISIONING_APP);
        } catch {
            app = firebase.initializeApp(firebase.app().options, PROVISIONING_APP);
        }
        return firebase.auth(app);
    }

    function usernameFromName(name) {
        const base = String(name || "")
            .toLowerCase()
            .replace(/\s+/g, "")
            .replace(/[^a-z0-9]/g, "");
        return base || "employee";
    }

    function isEmailInUseError(err) {
        const code = err?.code || "";
        const msg = String(err?.message || "").toLowerCase();
        return code === "auth/email-already-in-use" || (msg.includes("email") && msg.includes("already"));
    }

    async function createAuthUser({ email, password, username, role, locationId, managerUserId }) {
        const auth = provisioningAuth();
        let credential;
        try {
            credential = await auth.createUserWithEmailAndPassword(email, password);
        } finally {
            try {
                await auth.signOut();
            } catch {
                /* ignore */
            }
        }
        const uid = credential.user.uid;
        await window.oplixDb
            .collection("users")
            .doc(uid)
            .set({
                id: uid,
                username,
                role,
                locationId: locationId || null,
                managerUserId: managerUserId || null,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            });
        return uid;
    }

    async function createEmployee(managerUserId, form) {
        const name = String(form.name || "").trim();
        const password = String(form.password || "");
        if (!name) throw new Error("Employee name is required.");
        if (!password) throw new Error("Password is required.");

        const role = form.role === "supervisor" ? "supervisor" : "employee";
        const assignedLocationIds = [...(form.assignedLocationIds || [])];
        const rateRaw = form.hourlyRate;
        const hourlyRate =
            rateRaw != null && rateRaw !== "" && Number.isFinite(Number(rateRaw))
                ? Number(rateRaw)
                : null;
        const isSupervisor = role === "supervisor";

        let finalUsername = usernameFromName(name);
        let email = `${finalUsername}@oplix.app`;
        let uid = null;
        let attempts = 0;
        const maxAttempts = 10;

        while (attempts < maxAttempts) {
            try {
                uid = await createAuthUser({
                    email,
                    password,
                    username: finalUsername,
                    role,
                    locationId: assignedLocationIds[0] || null,
                    managerUserId,
                });
                break;
            } catch (err) {
                if (isEmailInUseError(err) && attempts < maxAttempts - 1) {
                    attempts += 1;
                    finalUsername = `${usernameFromName(name)}${attempts}`;
                    email = `${finalUsername}@oplix.app`;
                    continue;
                }
                throw err;
            }
        }

        if (!uid) {
            throw new Error("Could not create login after several attempts. Try a different name.");
        }

        const employee = {
            id: uid,
            name,
            username: finalUsername,
            locationId: assignedLocationIds[0] || null,
            managerUserId,
            password,
            shiftHistory: [],
            currentShiftStatus: "clockedOut",
            assignedLocationIds,
            hourlyRate,
            is24Hours: form.is24Hours ? true : null,
            canTakeRegister: !!form.canTakeRegister,
            canSubmitLottery: !!form.canSubmitLottery,
            canViewEmployeeData: isSupervisor ? !!form.canViewEmployeeData : false,
            canManageTasks: isSupervisor ? !!form.canManageTasks : false,
            canManageDocuments: isSupervisor ? !!form.canManageDocuments : false,
            canViewRegisterData: isSupervisor ? !!form.canViewRegisterData : false,
            canViewLotteryData: isSupervisor ? !!form.canViewLotteryData : false,
            canEditSchedules: isSupervisor ? !!form.canEditSchedules : false,
            canViewReports: isSupervisor ? !!form.canViewReports : false,
            canManagePayroll: isSupervisor ? !!form.canManagePayroll : false,
        };

        await managerCol(managerUserId).doc(uid).set(employee);

        let current = { ...employee };
        for (const locationId of assignedLocationIds) {
            current = await assignToLocation(managerUserId, current, locationId);
        }

        return {
            id: uid,
            username: finalUsername,
            email,
            password,
            employee: current,
        };
    }

    async function list(userId) {
        const snap = await managerCol(userId).get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    async function fetchUserRole(employeeId) {
        const snap = await window.oplixDb.collection("users").doc(employeeId).get();
        if (!snap.exists) return "employee";
        return snap.data()?.role || "employee";
    }

    async function fetchUserRoles(employeeIds) {
        const roles = {};
        await Promise.all(
            employeeIds.map(async (id) => {
                roles[id] = await fetchUserRole(id);
            })
        );
        return roles;
    }

    async function updateUserRole(employeeId, role) {
        await window.oplixDb.collection("users").doc(employeeId).set({ role }, { merge: true });
    }

    async function assignToLocation(userId, employee, locationId) {
        const assigned = [...(employee.assignedLocationIds || [])];
        if (!assigned.includes(locationId)) assigned.push(locationId);

        const updated = {
            ...employee,
            assignedLocationIds: assigned,
            locationId: employee.locationId || locationId,
        };

        await managerCol(userId).doc(employee.id).set(updated, { merge: true });

        const locEmployee = { ...updated, locationId };
        await locCol(userId, locationId).doc(employee.id).set(locEmployee, { merge: true });

        const userSnap = await window.oplixDb.collection("users").doc(employee.id).get();
        if (userSnap.exists && !userSnap.data()?.locationId) {
            await window.oplixDb.collection("users").doc(employee.id).set(
                { locationId },
                { merge: true }
            );
        }

        const locSnap = await locRef(userId, locationId).get();
        if (locSnap.exists) {
            const loc = locSnap.data();
            const employees = Array.isArray(loc.employees) ? [...loc.employees] : [];
            if (!employees.includes(employee.id)) {
                employees.push(employee.id);
                await locRef(userId, locationId).set({ employees }, { merge: true });
            }
        }

        return updated;
    }

    async function unassignFromLocation(userId, employee, locationId) {
        const assigned = (employee.assignedLocationIds || []).filter((id) => id !== locationId);
        const updated = {
            ...employee,
            assignedLocationIds: assigned,
        };

        await managerCol(userId).doc(employee.id).set(updated, { merge: true });
        await locCol(userId, locationId).doc(employee.id).delete();

        const locSnap = await locRef(userId, locationId).get();
        if (locSnap.exists) {
            const loc = locSnap.data();
            const employees = (Array.isArray(loc.employees) ? loc.employees : []).filter(
                (id) => id !== employee.id
            );
            await locRef(userId, locationId).set({ employees }, { merge: true });
        }

        return updated;
    }

    async function syncLocationAssignments(userId, previousIds, nextIds, employee) {
        const prev = new Set(previousIds || []);
        const next = new Set(nextIds || []);
        let current = { ...employee, assignedLocationIds: [...nextIds] };

        for (const locId of prev) {
            if (!next.has(locId)) {
                current = await unassignFromLocation(userId, current, locId);
            }
        }
        for (const locId of next) {
            if (!prev.has(locId)) {
                current = await assignToLocation(userId, current, locId);
            }
        }

        return current;
    }

    async function updateEmployee(userId, employee, previousAssignedIds) {
        let payload = { ...employee };
        const nextIds = payload.assignedLocationIds || [];

        payload = await syncLocationAssignments(userId, previousAssignedIds, nextIds, payload);

        if (nextIds.length && !payload.locationId) {
            payload.locationId = nextIds[0];
        }

        for (const locationId of nextIds) {
            const locEmployee = { ...payload, locationId };
            await locCol(userId, locationId).doc(payload.id).set(locEmployee, { merge: true });
        }

        await managerCol(userId).doc(payload.id).set(payload, { merge: true });
        return payload;
    }

    async function deleteEmployee(userId, employee) {
        for (const locationId of employee.assignedLocationIds || []) {
            try {
                await unassignFromLocation(userId, employee, locationId);
            } catch {
                /* ignore */
            }
        }
        await managerCol(userId).doc(employee.id).delete();
        try {
            await window.oplixDb.collection("users").doc(employee.id).delete();
        } catch {
            /* ignore */
        }
    }

    window.OplixEmployeesStore = {
        list,
        fetchUserRole,
        fetchUserRoles,
        updateUserRole,
        updateEmployee,
        deleteEmployee,
        createEmployee,
        usernameFromName,
    };
})();
