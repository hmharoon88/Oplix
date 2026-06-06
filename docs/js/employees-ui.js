/**
 * Sidebar Employees tab — create and edit staff.
 */
(function () {
    const Store = () => window.OplixEmployeesStore;
    const TP = () => window.OplixTaskProgress;

    let userId = null;
    let locations = [];
    let employees = [];
    let tasks = [];
    let userRoles = {};
    let state = {
        view: "list",
        editingId: null,
        createPrefillLocationId: null,
        createdInfo: null,
        status: "",
        statusKind: "",
        saving: false,
    };
    let saveReadyHandle = null;
    let editForm = null;
    let createForm = null;
    let editOriginalRole = "employee";
    let editOriginalAssigned = [];

    function $(id) {
        return document.getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function locationName(id) {
        return locations.find((l) => l.id === id)?.name || "Facility";
    }

    function employeeProgress(emp) {
        if (!TP()?.employeeToday || !tasks.length) return null;
        const r = TP().employeeToday(tasks, emp.id);
        if (!r || !r.assigned) return null;
        return r;
    }

    function roleLabel(role) {
        if (role === "supervisor") return "Supervisor";
        if (role === "manager") return "Manager";
        return "Employee";
    }

    function roleChipClass(role) {
        return role === "supervisor" ? "emp-role-chip--supervisor" : "emp-role-chip--employee";
    }

    function progressBadgeClass(completed, assigned) {
        if (completed === assigned) return "loc-emp-badge--done";
        if (completed > 0) return "loc-emp-badge--partial";
        return "loc-emp-badge--none";
    }

    function shiftStatusLabel(status) {
        const s = String(status || "clockedOut");
        if (s === "clockedIn") return "Clocked in";
        if (s === "assigned") return "Assigned";
        return "Clocked out";
    }

    async function loadData() {
        if (!userId) return;
        const [emps, taskSnap] = await Promise.all([
            Store().list(userId),
            window.oplixDb.collection("users").doc(userId).collection("tasks").get(),
        ]);
        employees = emps.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        tasks = taskSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        userRoles = await Store().fetchUserRoles(employees.map((e) => e.id));
    }

    function renderEmployeeRow(emp) {
        const role = userRoles[emp.id];
        const prog = employeeProgress(emp);
        const locIds = emp.assignedLocationIds || [];
        const locNames = locIds.map(locationName).filter(Boolean);
        const locMeta =
            locIds.length > 0
                ? `${locIds.length} location${locIds.length === 1 ? "" : "s"}`
                : "Unassigned";

        return `
            <li class="loc-row-card emp-hub-row" data-emp-id="${escapeHtml(emp.id)}" role="button" tabindex="0">
                <div class="emp-hub-row-main">
                    <div class="emp-hub-row-top">
                        <strong>${escapeHtml(emp.name || "Unnamed")}</strong>
                        ${role ? `<span class="emp-role-chip ${roleChipClass(role)}">${escapeHtml(roleLabel(role))}</span>` : ""}
                        <span class="emp-hub-loc-meta">${escapeHtml(locMeta)}</span>
                        ${
                            prog
                                ? `<span class="loc-emp-badge ${progressBadgeClass(prog.completed, prog.assigned)}">${prog.completed}/${prog.assigned}</span>`
                                : ""
                        }
                    </div>
                    <span class="data-list-meta">Username: ${escapeHtml(emp.username || "—")}</span>
                    ${
                        locNames.length
                            ? `<span class="data-list-meta emp-hub-locations">Locations: ${escapeHtml(locNames.join(", "))}</span>`
                            : ""
                    }
                </div>
                <span class="settings-chevron" aria-hidden="true">›</span>
            </li>`;
    }

    function generatedUsername(name) {
        return Store().usernameFromName(name);
    }

    function renderList() {
        return `
            <div class="emp-hub" data-emp-hub>
                <div class="dir-toolbar emp-hub-toolbar">
                    <button type="button" class="btn" id="emp-add-btn">Add employee</button>
                    <span class="dir-status" id="emp-list-status">${escapeHtml(state.status && state.view === "list" ? state.status : "")}</span>
                </div>
                <p class="books-hint">All staff across your organization. Username and login email are generated from the employee name.</p>
                ${
                    employees.length
                        ? `<ul class="loc-row-list dir-list">${employees.map(renderEmployeeRow).join("")}</ul>`
                        : `<div class="emp-hub-empty">
                            <p class="emp-hub-empty-title">No employees yet</p>
                            <p class="data-list-meta">Add your first team member with the button above.</p>
                           </div>`
                }
            </div>`;
    }

    function toggleRow(label, checked, name) {
        return `
            <label class="settings-toggle-row">
                <span class="settings-toggle-text"><strong>${escapeHtml(label)}</strong></span>
                <input type="checkbox" name="${escapeHtml(name)}"${checked ? " checked" : ""}>
            </label>`;
    }

    function defaultCreateForm(role) {
        const prefill = state.createPrefillLocationId;
        const assignedLocationIds = prefill ? [prefill] : [];
        const initialRole = role || "employee";
        return {
            name: "",
            password: "",
            hourlyRate: "",
            role: initialRole,
            assignedLocationIds,
            is24Hours: false,
            canTakeRegister: false,
            canSubmitLottery: false,
            canViewEmployeeData: false,
            canManageTasks: false,
            canManageDocuments: false,
            canViewRegisterData: false,
            canViewLotteryData: false,
            canEditSchedules: false,
            canViewReports: false,
        };
    }

    function renderPermissionFields(f, isSupervisor, prefix) {
        const p = prefix || "";
        return `
            <fieldset class="books-fieldset">
                <legend class="books-label">Permissions</legend>
                ${toggleRow("Register access", f.canTakeRegister, `${p}canTakeRegister`)}
                ${toggleRow("Lottery forms", f.canSubmitLottery, `${p}canSubmitLottery`)}
                ${toggleRow("24/7 clock-in", f.is24Hours, `${p}is24Hours`)}
            </fieldset>
            ${
                isSupervisor
                    ? `<fieldset class="books-fieldset">
                <legend class="books-label">Supervisor permissions</legend>
                ${toggleRow("View employee data", f.canViewEmployeeData, `${p}canViewEmployeeData`)}
                ${toggleRow("Manage tasks", f.canManageTasks, `${p}canManageTasks`)}
                ${toggleRow("Manage documents", f.canManageDocuments, `${p}canManageDocuments`)}
                ${toggleRow("View register data", f.canViewRegisterData, `${p}canViewRegisterData`)}
                ${toggleRow("View lottery data", f.canViewLotteryData, `${p}canViewLotteryData`)}
                ${toggleRow("Edit schedules", f.canEditSchedules, `${p}canEditSchedules`)}
                ${toggleRow("View reports", f.canViewReports, `${p}canViewReports`)}
            </fieldset>`
                    : ""
            }`;
    }

    function renderCreate() {
        const f = createForm || defaultCreateForm();
        const role = f.role || "employee";
        const isSupervisor = role === "supervisor";
        const usernamePreview = generatedUsername(f.name);
        const emailPreview = usernamePreview ? `${usernamePreview}@oplix.app` : "—";

        const locChecks = locations
            .map(
                (loc) => `
            <label class="settings-toggle-row">
                <span class="settings-toggle-text"><strong>${escapeHtml(loc.name)}</strong></span>
                <input type="checkbox" name="emp_loc" value="${escapeHtml(loc.id)}"${
                    f.assignedLocationIds.includes(loc.id) ? " checked" : ""
                }>
            </label>`
            )
            .join("");

        return `
            <div class="emp-edit" data-emp-create>
                <button type="button" class="settings-back" id="emp-back-list">← Employees</button>
                ${state.status ? `<div class="settings-status settings-status--${escapeHtml(state.statusKind || "info")}">${escapeHtml(state.status)}</div>` : ""}
                <div class="books-panel emp-edit-card">
                    <h2 class="books-subtitle">New employee</h2>
                    <form id="emp-create-form" class="dir-form">
                        <label class="books-label">Name *
                            <input class="books-input" name="name" required value="${escapeHtml(f.name)}" placeholder="Full name">
                        </label>
                        <label class="books-label">Password *
                            <input class="books-input" name="password" type="text" autocomplete="new-password" required value="${escapeHtml(f.password)}" placeholder="Login password">
                        </label>
                        <label class="books-label">Hourly rate
                            <input class="books-input" name="hourlyRate" inputmode="decimal" value="${escapeHtml(f.hourlyRate)}" placeholder="e.g. 15.00">
                        </label>
                        <label class="books-label">Role
                            <select class="books-select" name="role">
                                <option value="employee"${role === "employee" ? " selected" : ""}>Employee</option>
                                <option value="supervisor"${role === "supervisor" ? " selected" : ""}>Supervisor</option>
                            </select>
                        </label>
                        <fieldset class="books-fieldset">
                            <legend class="books-label">Assigned facilities</legend>
                            ${locChecks || `<p class="data-list-meta">No facilities yet — create one first.</p>`}
                        </fieldset>
                        ${renderPermissionFields(f, isSupervisor, "")}
                        <div class="emp-generated-preview">
                            <p class="books-hint"><strong>Auto-generated login</strong></p>
                            <p class="data-list-meta">Username: <strong>${escapeHtml(usernamePreview || "—")}</strong></p>
                            <p class="data-list-meta">Email: <strong>${escapeHtml(emailPreview)}</strong></p>
                            <p class="books-hint">If that email is taken, a number is added automatically (e.g. johnsmith1@oplix.app).</p>
                        </div>
                        <p class="books-hint">Weekly schedules — set detailed hours after creating the employee.</p>
                        <div class="dir-form-actions">
                            <button type="button" class="btn" id="emp-create-btn"${state.saving ? " disabled" : ""}>Create employee</button>
                            <button type="button" class="btn btn-nav-outline" id="emp-cancel-create">Cancel</button>
                        </div>
                    </form>
                </div>
                ${
                    state.createdInfo
                        ? `<div class="emp-create-success home-card" role="status">
                    <h3 class="books-subtitle">Employee created</h3>
                    <p class="data-list-meta">Share these login details with the employee:</p>
                    <ul class="emp-create-credentials">
                        <li><span>Email</span><strong>${escapeHtml(state.createdInfo.email)}</strong></li>
                        <li><span>Username</span><strong>${escapeHtml(state.createdInfo.username)}</strong></li>
                        <li><span>Password</span><strong>${escapeHtml(state.createdInfo.password)}</strong></li>
                    </ul>
                    <div class="dir-form-actions">
                        <button type="button" class="btn btn-nav-outline" id="emp-copy-password">Copy password</button>
                        <button type="button" class="btn" id="emp-done-create">Done</button>
                    </div>
                </div>`
                        : ""
                }
            </div>`;
    }

    function renderEdit() {
        const emp = employees.find((e) => e.id === state.editingId);
        if (!emp) {
            state.view = "list";
            return renderList();
        }

        const role = editForm?.role ?? userRoles[emp.id] ?? "employee";
        const isSupervisor = role === "supervisor";
        const f = editForm || {
            name: emp.name || "",
            password: emp.password || "",
            hourlyRate: emp.hourlyRate != null ? String(emp.hourlyRate) : "",
            is24Hours: !!emp.is24Hours,
            canTakeRegister: !!emp.canTakeRegister,
            canSubmitLottery: !!emp.canSubmitLottery,
            assignedLocationIds: [...(emp.assignedLocationIds || [])],
            role,
            canViewEmployeeData: !!emp.canViewEmployeeData,
            canManageTasks: !!emp.canManageTasks,
            canManageDocuments: !!emp.canManageDocuments,
            canViewRegisterData: !!emp.canViewRegisterData,
            canViewLotteryData: !!emp.canViewLotteryData,
            canEditSchedules: !!emp.canEditSchedules,
            canViewReports: !!emp.canViewReports,
        };

        const locChecks = locations
            .map(
                (loc) => `
            <label class="settings-toggle-row">
                <span class="settings-toggle-text"><strong>${escapeHtml(loc.name)}</strong></span>
                <input type="checkbox" name="emp_loc" value="${escapeHtml(loc.id)}"${
                    f.assignedLocationIds.includes(loc.id) ? " checked" : ""
                }>
            </label>`
            )
            .join("");

        return `
            <div class="emp-edit" data-emp-edit>
                <button type="button" class="settings-back" id="emp-back-list">← Employees</button>
                ${state.status ? `<div class="settings-status settings-status--${escapeHtml(state.statusKind || "info")}">${escapeHtml(state.status)}</div>` : ""}
                <div class="books-panel emp-edit-card">
                    <div class="emp-edit-header">
                        <h2 class="books-subtitle">${escapeHtml(f.name || emp.name)}</h2>
                        <span class="data-list-meta">@${escapeHtml(emp.username)}</span>
                        <span class="loc-shift-pill">${escapeHtml(shiftStatusLabel(emp.currentShiftStatus))}</span>
                    </div>
                    <form id="emp-edit-form" class="dir-form">
                        <label class="books-label">Name *
                            <input class="books-input" name="name" required value="${escapeHtml(f.name)}">
                        </label>
                        <label class="books-label">Password
                            <input class="books-input" name="password" type="text" autocomplete="off" value="${escapeHtml(f.password)}" placeholder="Login password">
                        </label>
                        <label class="books-label">Hourly rate
                            <input class="books-input" name="hourlyRate" inputmode="decimal" value="${escapeHtml(f.hourlyRate)}" placeholder="e.g. 15.00">
                        </label>
                        <label class="books-label">Role
                            <select class="books-select" name="role">
                                <option value="employee"${role === "employee" ? " selected" : ""}>Employee</option>
                                <option value="supervisor"${role === "supervisor" ? " selected" : ""}>Supervisor</option>
                            </select>
                        </label>
                        <fieldset class="books-fieldset">
                            <legend class="books-label">Assigned facilities</legend>
                            ${locChecks || `<p class="data-list-meta">No facilities yet.</p>`}
                        </fieldset>
                        <fieldset class="books-fieldset">
                            <legend class="books-label">Permissions</legend>
                            ${toggleRow("Register access", f.canTakeRegister, "canTakeRegister")}
                            ${toggleRow("Lottery forms", f.canSubmitLottery, "canSubmitLottery")}
                            ${toggleRow("24/7 clock-in", f.is24Hours, "is24Hours")}
                        </fieldset>
                        ${
                            isSupervisor
                                ? `<fieldset class="books-fieldset">
                            <legend class="books-label">Supervisor permissions</legend>
                            ${toggleRow("View employee data", f.canViewEmployeeData, "canViewEmployeeData")}
                            ${toggleRow("Manage tasks", f.canManageTasks, "canManageTasks")}
                            ${toggleRow("Manage documents", f.canManageDocuments, "canManageDocuments")}
                            ${toggleRow("View register data", f.canViewRegisterData, "canViewRegisterData")}
                            ${toggleRow("View lottery data", f.canViewLotteryData, "canViewLotteryData")}
                            ${toggleRow("Edit schedules", f.canEditSchedules, "canEditSchedules")}
                            ${toggleRow("View reports", f.canViewReports, "canViewReports")}
                        </fieldset>`
                                : ""
                        }
                        <p class="books-hint">Weekly schedules — per-facility schedule controls available when editing.</p>
                        <div class="dir-form-actions">
                            <button type="button" class="btn" id="emp-save-btn"${state.saving ? " disabled" : ""}>Save changes</button>
                            <button type="button" class="btn btn-nav-outline" id="emp-cancel-edit">Cancel</button>
                            <button type="button" class="btn dir-btn-delete" id="emp-delete-btn"${state.saving ? " disabled" : ""}>Delete employee</button>
                        </div>
                    </form>
                </div>
            </div>`;
    }

    function renderPanel() {
        const root = $("employees-root");
        if (!root) return;
        if (state.view === "edit") root.innerHTML = renderEdit();
        else if (state.view === "create") root.innerHTML = renderCreate();
        else root.innerHTML = renderList();
    }

    function openCreate(locationId, role) {
        saveReadyHandle?.detach();
        saveReadyHandle = null;
        state.view = "create";
        state.editingId = null;
        state.createPrefillLocationId = locationId || null;
        state.createdInfo = null;
        state.status = "";
        createForm = defaultCreateForm(role);
        renderPanel();
    }

    function closeCreate() {
        state.view = "list";
        state.createPrefillLocationId = null;
        state.createdInfo = null;
        state.status = "";
        createForm = null;
        renderPanel();
    }

    async function openEdit(empId) {
        saveReadyHandle?.detach();
        saveReadyHandle = null;
        if (!employees.find((e) => e.id === empId)) {
            await loadData();
        }
        const emp = employees.find((e) => e.id === empId);
        if (!emp) return;
        state.view = "edit";
        state.editingId = empId;
        state.status = "";
        editOriginalRole = userRoles[emp.id] || "employee";
        editOriginalAssigned = [...(emp.assignedLocationIds || [])];
        editForm = null;
        renderPanel();
        attachSaveReady();
    }

    function closeEdit() {
        saveReadyHandle?.detach();
        saveReadyHandle = null;
        state.view = "list";
        state.editingId = null;
        state.status = "";
        editForm = null;
        renderPanel();
    }

    function readCreateForm() {
        const form = $("emp-create-form");
        if (!form) return null;
        const fd = new FormData(form);
        const assignedLocationIds = [...form.querySelectorAll('[name="emp_loc"]:checked')].map(
            (el) => el.value
        );
        const rateRaw = String(fd.get("hourlyRate") || "").trim();
        const hourlyRate = rateRaw ? parseFloat(rateRaw) : null;
        return {
            name: String(fd.get("name") || "").trim(),
            password: String(fd.get("password") || ""),
            hourlyRate: Number.isFinite(hourlyRate) ? hourlyRate : null,
            role: fd.get("role") || "employee",
            assignedLocationIds,
            is24Hours: !!form.querySelector('[name="is24Hours"]')?.checked,
            canTakeRegister: !!form.querySelector('[name="canTakeRegister"]')?.checked,
            canSubmitLottery: !!form.querySelector('[name="canSubmitLottery"]')?.checked,
            canViewEmployeeData: !!form.querySelector('[name="canViewEmployeeData"]')?.checked,
            canManageTasks: !!form.querySelector('[name="canManageTasks"]')?.checked,
            canManageDocuments: !!form.querySelector('[name="canManageDocuments"]')?.checked,
            canViewRegisterData: !!form.querySelector('[name="canViewRegisterData"]')?.checked,
            canViewLotteryData: !!form.querySelector('[name="canViewLotteryData"]')?.checked,
            canEditSchedules: !!form.querySelector('[name="canEditSchedules"]')?.checked,
            canViewReports: !!form.querySelector('[name="canViewReports"]')?.checked,
        };
    }

    async function saveCreate() {
        const form = readCreateForm();
        if (!form?.name || !form.password) {
            state.status = "Name and password are required.";
            state.statusKind = "error";
            renderPanel();
            return;
        }

        state.saving = true;
        state.status = "Creating employee…";
        state.statusKind = "info";
        renderPanel();

        try {
            const info = await Store().createEmployee(userId, form);
            await loadData();
            state.saving = false;
            state.createdInfo = info;
            state.status = "";
            renderPanel();
            if (window.OplixDashboard?.reloadLocations) {
                await OplixDashboard.reloadLocations();
            }
        } catch (err) {
            state.saving = false;
            state.status = err.message || "Failed to create employee.";
            state.statusKind = "error";
            renderPanel();
        }
    }

    function readEditForm() {
        const form = $("emp-edit-form");
        if (!form) return null;
        const fd = new FormData(form);
        const assignedLocationIds = [...form.querySelectorAll('[name="emp_loc"]:checked')].map(
            (el) => el.value
        );
        const rateRaw = String(fd.get("hourlyRate") || "").trim();
        const hourlyRate = rateRaw ? parseFloat(rateRaw) : null;
        return {
            name: String(fd.get("name") || "").trim(),
            password: String(fd.get("password") || ""),
            hourlyRate: Number.isFinite(hourlyRate) ? hourlyRate : null,
            role: fd.get("role") || "employee",
            assignedLocationIds,
            is24Hours: !!form.querySelector('[name="is24Hours"]')?.checked,
            canTakeRegister: !!form.querySelector('[name="canTakeRegister"]')?.checked,
            canSubmitLottery: !!form.querySelector('[name="canSubmitLottery"]')?.checked,
            canViewEmployeeData: !!form.querySelector('[name="canViewEmployeeData"]')?.checked,
            canManageTasks: !!form.querySelector('[name="canManageTasks"]')?.checked,
            canManageDocuments: !!form.querySelector('[name="canManageDocuments"]')?.checked,
            canViewRegisterData: !!form.querySelector('[name="canViewRegisterData"]')?.checked,
            canViewLotteryData: !!form.querySelector('[name="canViewLotteryData"]')?.checked,
            canEditSchedules: !!form.querySelector('[name="canEditSchedules"]')?.checked,
            canViewReports: !!form.querySelector('[name="canViewReports"]')?.checked,
        };
    }

    function attachSaveReady() {
        saveReadyHandle?.detach();
        const panel = $("employees-root")?.querySelector("[data-emp-edit]");
        if (!panel || !window.OplixFormSaveReady) return;
        saveReadyHandle = OplixFormSaveReady.watch(panel, {
            saveButton: "#emp-save-btn",
            mode: "edit",
            baseline: null,
            isReady: () => {
                const form = readEditForm();
                if (!form?.name) return false;
                const emp = employees.find((e) => e.id === state.editingId);
                if (!emp) return false;
                const base = JSON.stringify({
                    name: emp.name || "",
                    password: emp.password || "",
                    hourlyRate: emp.hourlyRate != null ? String(emp.hourlyRate) : "",
                    role: editOriginalRole,
                    assignedLocationIds: [...editOriginalAssigned].sort(),
                    is24Hours: !!emp.is24Hours,
                    canTakeRegister: !!emp.canTakeRegister,
                    canSubmitLottery: !!emp.canSubmitLottery,
                    canViewEmployeeData: !!emp.canViewEmployeeData,
                    canManageTasks: !!emp.canManageTasks,
                    canManageDocuments: !!emp.canManageDocuments,
                    canViewRegisterData: !!emp.canViewRegisterData,
                    canViewLotteryData: !!emp.canViewLotteryData,
                    canEditSchedules: !!emp.canEditSchedules,
                    canViewReports: !!emp.canViewReports,
                });
                const current = JSON.stringify({
                    ...form,
                    assignedLocationIds: [...form.assignedLocationIds].sort(),
                    hourlyRate: form.hourlyRate != null ? String(form.hourlyRate) : "",
                });
                return current !== base;
            },
        });
    }

    async function saveEdit() {
        const emp = employees.find((e) => e.id === state.editingId);
        const form = readEditForm();
        if (!emp || !form || !form.name) return;

        state.saving = true;
        state.status = "Saving…";
        state.statusKind = "info";
        renderPanel();
        attachSaveReady();

        try {
            const isSupervisor = form.role === "supervisor";
            const updated = {
                ...emp,
                name: form.name,
                password: form.password || emp.password,
                hourlyRate: form.hourlyRate,
                assignedLocationIds: form.assignedLocationIds,
                is24Hours: form.is24Hours,
                canTakeRegister: form.canTakeRegister,
                canSubmitLottery: form.canSubmitLottery,
                canViewEmployeeData: isSupervisor ? form.canViewEmployeeData : false,
                canManageTasks: isSupervisor ? form.canManageTasks : false,
                canManageDocuments: isSupervisor ? form.canManageDocuments : false,
                canViewRegisterData: isSupervisor ? form.canViewRegisterData : false,
                canViewLotteryData: isSupervisor ? form.canViewLotteryData : false,
                canEditSchedules: isSupervisor ? form.canEditSchedules : false,
                canViewReports: isSupervisor ? form.canViewReports : false,
            };

            await Store().updateEmployee(userId, updated, editOriginalAssigned);

            if (form.role !== editOriginalRole) {
                await Store().updateUserRole(emp.id, form.role);
            }

            await loadData();
            state.saving = false;
            state.status = "Saved.";
            state.statusKind = "success";
            closeEdit();
            if (window.OplixDashboard?.reloadLocations) {
                await OplixDashboard.reloadLocations();
            }
        } catch (err) {
            state.saving = false;
            state.status = err.message || "Failed to save.";
            state.statusKind = "error";
            renderPanel();
            attachSaveReady();
        }
    }

    async function deleteEdit() {
        const emp = employees.find((e) => e.id === state.editingId);
        if (!emp) return;
        if (!confirm(`Delete ${emp.name}? This removes their login and assignments.`)) return;

        state.saving = true;
        state.status = "Deleting…";
        state.statusKind = "info";
        renderPanel();

        try {
            await Store().deleteEmployee(userId, emp);
            await loadData();
            state.saving = false;
            closeEdit();
            if (window.OplixDashboard?.reloadLocations) {
                await OplixDashboard.reloadLocations();
            }
        } catch (err) {
            state.saving = false;
            state.status = err.message || "Failed to delete.";
            state.statusKind = "error";
            renderPanel();
            attachSaveReady();
        }
    }

    function bind() {
        const root = $("employees-root");
        if (!root || root.dataset.empBound) return;
        root.dataset.empBound = "1";

        root.addEventListener("click", async (e) => {
            if (e.target.id === "emp-add-btn") {
                openCreate();
                return;
            }
            if (e.target.id === "emp-back-list") {
                if (state.view === "create") closeCreate();
                else closeEdit();
                return;
            }
            if (e.target.id === "emp-cancel-create") {
                closeCreate();
                return;
            }
            if (e.target.id === "emp-create-btn") {
                await saveCreate();
                return;
            }
            if (e.target.id === "emp-copy-password" && state.createdInfo?.password) {
                try {
                    await navigator.clipboard.writeText(state.createdInfo.password);
                    state.status = "Password copied.";
                    state.statusKind = "success";
                } catch {
                    state.status = "Could not copy — select and copy manually.";
                    state.statusKind = "error";
                }
                renderPanel();
                return;
            }
            if (e.target.id === "emp-done-create") {
                closeCreate();
                return;
            }
            if (e.target.id === "emp-cancel-edit") {
                closeEdit();
                return;
            }
            if (e.target.id === "emp-save-btn") {
                await saveEdit();
                return;
            }
            if (e.target.id === "emp-delete-btn") {
                await deleteEdit();
                return;
            }
            const row = e.target.closest("[data-emp-id]");
            if (row && state.view === "list") {
                openEdit(row.dataset.empId);
            }
        });

        root.addEventListener("keydown", (e) => {
            if (e.key !== "Enter") return;
            const row = e.target.closest("[data-emp-id]");
            if (row && state.view === "list") {
                openEdit(row.dataset.empId);
            }
        });

        root.addEventListener("input", (e) => {
            if (state.view !== "create") return;
            if (e.target.closest("#emp-create-form") && e.target.name === "name") {
                createForm = readCreateForm();
                const preview = $("employees-root")?.querySelector(".emp-generated-preview");
                if (preview && createForm) {
                    const username = generatedUsername(createForm.name);
                    const email = username ? `${username}@oplix.app` : "—";
                    const lines = preview.querySelectorAll(".data-list-meta");
                    if (lines[0]) lines[0].innerHTML = `Username: <strong>${escapeHtml(username || "—")}</strong>`;
                    if (lines[1]) lines[1].innerHTML = `Email: <strong>${escapeHtml(email)}</strong>`;
                }
            }
        });

        root.addEventListener("change", (e) => {
            if (state.view === "create" && e.target.name === "role") {
                createForm = readCreateForm();
                renderPanel();
                return;
            }
            if (state.view !== "edit") return;
            if (e.target.name === "role") {
                editForm = readEditForm();
                renderPanel();
                attachSaveReady();
            }
        });
    }

    async function refresh() {
        await loadData();
        renderPanel();
        if (state.view === "edit" && state.editingId) {
            attachSaveReady();
        }
    }

    async function setLocations(locs) {
        locations = locs || [];
        await refresh();
    }

    async function init(uid, locs) {
        userId = uid;
        locations = locs || [];
        state.view = "list";
        state.editingId = null;
        const root = $("employees-root");
        if (root) root.dataset.empBound = "";
        bind();
        await refresh();
    }

    async function onShow() {
        if (!userId) return;
        await refresh();
    }

    function resetToRoot() {
        if (state.view === "edit") closeEdit();
        if (state.view === "create") closeCreate();
    }

    window.OplixEmployeesUI = { init, onShow, refresh, setLocations, resetToRoot, openCreate, openEdit };
})();
