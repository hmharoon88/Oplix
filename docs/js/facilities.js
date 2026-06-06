/**
 * Facilities tab — LocationRow list + LocationDetailView + section screens.
 */
(function () {
    const ACCENTS = [
        "fac-accent-0",
        "fac-accent-1",
        "fac-accent-2",
        "fac-accent-3",
        "fac-accent-4",
        "fac-accent-5",
        "fac-accent-6",
        "fac-accent-7",
    ];

    const SECTIONS = [
        { id: "employees", title: "Employees", color: "#2563eb" },
        { id: "supervisors", title: "Supervisors", color: "#7c3aed" },
        { id: "tasks", title: "Tasks", color: "#16a34a" },
        { id: "shifts", title: "Shift Manager", color: "#6366f1" },
        { id: "lottery", title: "Lottery", color: "#ea580c" },
        { id: "documents", title: "Documents", color: "#4f46e5" },
        { id: "compliance", title: "Compliance", color: "#b45309" },
        { id: "reminders", title: "Reminders", color: "#db2777" },
        { id: "payroll", title: "Payroll", color: "#059669" },
        { id: "reports", title: "Reports", color: "#0891b2" },
        { id: "sales", title: "Sales", color: "#0d9488" },
        { id: "payables", title: "Payables", color: "#dc2626" },
        { id: "receivables", title: "Receivables", color: "#2563eb" },
        { id: "vendors", title: "Vendors", color: "#0f766e" },
        { id: "utility-providers", title: "Utilities", color: "#ca8a04" },
        { id: "servicers", title: "Servicers", color: "#64748b" },
    ];

    let userId = null;
    let locations = [];
    let tasks = [];
    let listRendered = false;
    let currentDetail = null;
    let currentSectionId = null;
    let showCreateForm = false;
    let showEditForm = false;
    let facEditSaveReady = null;

    const FAC_NAV_KEY = "oplix.facilities.nav";

    const Store = () => window.OplixLocationStore;

    const FACILITY_TYPES = [
        { id: "c_store", label: "C Store" },
        { id: "c_store_gas", label: "C Store Gas Station" },
    ];

    function escapeHtml(text) {
        const div = document.createElement("div");
        div.textContent = text == null ? "" : String(text);
        return div.innerHTML;
    }

    function $(id) {
        return document.getElementById(id);
    }

    function readFacNav() {
        try {
            const raw = sessionStorage.getItem(FAC_NAV_KEY);
            if (!raw) return null;
            const nav = JSON.parse(raw);
            if (!nav?.locationId) return null;
            return nav;
        } catch {
            return null;
        }
    }

    function saveFacNav() {
        try {
            if (!currentDetail?.location?.id) return;
            sessionStorage.setItem(
                FAC_NAV_KEY,
                JSON.stringify({
                    locationId: currentDetail.location.id,
                    sectionId: currentSectionId || null,
                })
            );
        } catch {
            /* ignore */
        }
    }

    function clearFacNav() {
        try {
            sessionStorage.removeItem(FAC_NAV_KEY);
        } catch {
            /* ignore */
        }
    }

    function formatCurrency(amount) {
        return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(amount || 0);
    }

    function toDate(value) {
        return OplixTaskProgress.toDate(value);
    }

    function getAcknowledgedSet(uid) {
        try {
            const raw = localStorage.getItem(`oplix.acknowledgedAlerts.${uid}`);
            return raw ? new Set(JSON.parse(raw)) : new Set();
        } catch {
            return new Set();
        }
    }

    function acknowledgeAlert(uid, alertId) {
        const set = getAcknowledgedSet(uid);
        set.add(alertId);
        localStorage.setItem(`oplix.acknowledgedAlerts.${uid}`, JSON.stringify([...set]));
    }

    function severityClass(severity) {
        if (severity === 0) return "home-severity--critical";
        if (severity === 1) return "home-severity--warning";
        return "home-severity--info";
    }

    async function fetchSub(uid, locationId, name) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(uid)
            .collection("locations")
            .doc(locationId)
            .collection(name)
            .get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    function renderLocationCard(loc, index) {
        const accent = ACCENTS[index % ACCENTS.length];
        const name = loc.name || "Unnamed";

        return `
            <button type="button" class="fac-card ${accent}" data-location-id="${escapeHtml(loc.id)}">
                <span class="fac-card-name">${escapeHtml(name)}</span>
            </button>`;
    }

    function renderCreateForm() {
        const panel = $("facilities-create");
        if (!panel) return;
        if (!showCreateForm) {
            panel.hidden = true;
            panel.innerHTML = "";
            return;
        }
        panel.hidden = false;
        const typeOpts = renderFacilityTypeOptions("c_store");
        panel.innerHTML = `
            <form id="fac-create-form" class="fac-create-form">
                <h2 class="fac-create-title">New facility</h2>
                <div class="books-grid-2">
                    <label class="books-label">Name *
                        <input class="books-input" name="name" required autocomplete="organization">
                    </label>
                    <label class="books-label">Type
                        <select class="books-select" name="facilityType">${typeOpts}</select>
                    </label>
                </div>
                <label class="books-label">Address *
                    <textarea class="books-input fac-create-address" name="address" rows="2" required></textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Create facility</button>
                    <button type="button" class="btn btn-nav-outline" id="fac-create-cancel">Cancel</button>
                    <span class="dir-status" id="fac-create-status"></span>
                </div>
            </form>`;
    }

    function effectiveFacilityType(loc) {
        return loc?.facilityType === "c_store_gas" ? "c_store_gas" : "c_store";
    }

    function renderFacilityTypeOptions(selected) {
        return FACILITY_TYPES.map(
            (t) =>
                `<option value="${t.id}"${t.id === selected ? " selected" : ""}>${escapeHtml(t.label)}</option>`
        ).join("");
    }

    async function afterLocationsChanged() {
        if (window.OplixDashboard?.reloadLocations) {
            locations = await OplixDashboard.reloadLocations();
        }
        listRendered = false;
        renderList();
    }

    function renderList() {
        const listEl = $("facilities-list");
        const emptyEl = $("facilities-empty");
        const loadingEl = $("facilities-loading");
        if (!listEl) return;

        renderCreateForm();
        if (loadingEl) loadingEl.hidden = true;

        if (!locations.length) {
            listEl.innerHTML = "";
            if (emptyEl) emptyEl.hidden = showCreateForm;
            listRendered = true;
            return;
        }

        if (emptyEl) emptyEl.hidden = true;

        let cardIndex = 0;
        const grouped = FACILITY_TYPES.map((type) => ({
            type,
            locations: locations
                .filter((loc) => effectiveFacilityType(loc) === type.id)
                .slice()
                .sort((a, b) => (a.name || "").localeCompare(b.name || "")),
        })).filter((g) => g.locations.length > 0);

        listEl.innerHTML = grouped
            .map(
                (group) => `
            <section class="facilities-group">
                <h2 class="facilities-group-title">${escapeHtml(group.type.label)}</h2>
                <div class="facilities-group-grid">
                    ${group.locations
                        .map((loc) => {
                            const html = renderLocationCard(loc, cardIndex);
                            cardIndex += 1;
                            return html;
                        })
                        .join("")}
                </div>
            </section>`
            )
            .join("");

        listEl.querySelectorAll(".fac-card").forEach((btn) => {
            btn.addEventListener("click", () => openLocation(btn.dataset.locationId));
        });
        listRendered = true;
    }

    async function fetchUserRole(employeeId) {
        try {
            const doc = await window.oplixDb.collection("users").doc(employeeId).get();
            if (doc.exists) return doc.data().role || "employee";
        } catch {
            /* ignore */
        }
        return "employee";
    }

    async function loadLocationDetail(locationId) {
        const loc = locations.find((l) => l.id === locationId);
        if (!loc) return null;

        const [
            allPeople,
            locTasks,
            shifts,
            lotteryForms,
            payables,
            receivables,
            reminders,
            documents,
            directory,
            complianceItems,
        ] = await Promise.all([
            fetchSub(userId, locationId, "employees"),
            fetchSub(userId, locationId, "tasks"),
            fetchSub(userId, locationId, "shifts"),
            fetchSub(userId, locationId, "lotteryForms"),
            fetchSub(userId, locationId, "payables"),
            fetchSub(userId, locationId, "receivables"),
            fetchSub(userId, locationId, "reminders"),
            fetchSub(userId, locationId, "documents"),
            window.OplixLocationDirectoryStore
                ? OplixLocationDirectoryStore.loadAll(userId, locationId)
                : Promise.resolve({ vendors: [], utilityProviders: [], servicers: [] }),
            window.OplixComplianceStore
                ? OplixComplianceStore.list(userId, locationId)
                : Promise.resolve([]),
        ]);

        const roles = await Promise.all(allPeople.map((e) => fetchUserRole(e.id)));
        const employees = [];
        const supervisors = [];
        const nameById = {};
        allPeople.forEach((e, i) => {
            nameById[e.id] = e.name || e.username || "Employee";
            if (roles[i] === "supervisor") supervisors.push(e);
            else employees.push(e);
        });

        const managerTasksHere = tasks.filter((t) => t.locationId === locationId);
        let alerts = OplixLocationAlerts.buildLocationAlerts({
            locationId,
            shifts,
            forms: lotteryForms,
            payables,
            employees: allPeople,
            documents,
            managerTasks: tasks,
        });
        const acknowledged = getAcknowledgedSet(userId);
        alerts = alerts.filter((a) => !acknowledged.has(a.id));

        return {
            location: loc,
            employees,
            supervisors,
            allPeople,
            nameById,
            tasks: locTasks,
            managerTasks: managerTasksHere,
            shifts,
            lotteryForms,
            payables,
            receivables,
            reminders,
            documents,
            vendors: directory.vendors || [],
            utilityProviders: directory.utilityProviders || [],
            servicers: directory.servicers || [],
            complianceItems: complianceItems || [],
            alerts,
            recurringPayables: payables.filter(
                (p) => p.frequency && p.frequency !== "none" && !p.isPaid
            ).length,
            recurringReceivables: receivables.filter(
                (r) => r.frequency && r.frequency !== "none" && !r.isReceived
            ).length,
            openReminders: reminders.filter((r) => !r.isCompleted).length,
        };
    }

    function renderNeedsAttention(alerts) {
        if (!alerts.length) return "";
        const limit = 5;
        const visible = alerts.slice(0, limit);
        return `
            <section class="home-section home-card loc-attention">
                <div class="home-card-header">
                    <span class="home-card-header-icon">⚠️</span>
                    <h2>Needs Attention</h2>
                    <span class="home-badge">${alerts.length}</span>
                </div>
                <ul class="home-alert-list">
                    ${visible
                        .map(
                            (a) => `
                    <li class="home-alert-item">
                        <div class="home-alert-main">
                            <span class="home-severity-dot ${severityClass(a.severity)}"></span>
                            <span class="home-alert-text">
                                <span class="home-alert-title">${escapeHtml(a.title)}</span>
                                ${a.subtitle ? `<span class="home-alert-sub">${escapeHtml(a.subtitle)}</span>` : ""}
                            </span>
                        </div>
                        <button type="button" class="home-alert-ack" data-alert-id="${escapeHtml(a.id)}" title="Acknowledge">✓</button>
                    </li>`
                        )
                        .join("")}
                </ul>
                ${
                    alerts.length > limit
                        ? `<p class="home-more-note">Show ${alerts.length - limit} more</p>`
                        : ""
                }
            </section>`;
    }

    function renderEditForm(data) {
        const loc = data.location;
        const type = effectiveFacilityType(loc);
        return `
            <form id="fac-edit-form" class="fac-create-form fac-edit-form">
                <h2 class="fac-create-title">Edit facility</h2>
                <div class="books-grid-2">
                    <label class="books-label">Name *
                        <input class="books-input" name="name" required value="${escapeHtml(loc.name || "")}">
                    </label>
                    <label class="books-label">Type
                        <select class="books-select" name="facilityType">${renderFacilityTypeOptions(type)}</select>
                    </label>
                </div>
                <label class="books-label">Address *
                    <textarea class="books-input fac-create-address" name="address" rows="2" required>${escapeHtml(loc.address || "")}</textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save changes</button>
                    <button type="button" class="btn btn-nav-outline" id="fac-edit-cancel">Cancel</button>
                    <span class="dir-status" id="fac-edit-status"></span>
                </div>
            </form>`;
    }

    function renderLocationMain(data) {
        const badges = {
            reminders: data.openReminders,
            payables: data.recurringPayables,
            receivables: data.recurringReceivables,
            vendors: (data.vendors || []).filter((v) => v.active !== false).length,
            "utility-providers": (data.utilityProviders || []).filter((v) => v.active !== false).length,
            servicers: (data.servicers || []).filter((v) => v.active !== false).length,
            compliance: window.OplixComplianceModel
                ? OplixComplianceModel.needsAttentionCount(data.complianceItems)
                : 0,
        };

        return `
            <header class="fac-detail-header">
                <div class="fac-detail-header-text">
                    <h1>${escapeHtml(data.location.name)}</h1>
                    <p>${escapeHtml(data.location.address || "")}</p>
                    <p class="fac-detail-type">${escapeHtml(FACILITY_TYPES.find((t) => t.id === effectiveFacilityType(data.location))?.label || "C Store")}</p>
                </div>
                <div class="fac-detail-actions">
                    <button type="button" class="btn btn-nav-outline" id="fac-edit-btn">Edit</button>
                    <button type="button" class="btn fac-btn-delete" id="fac-delete-btn">Delete</button>
                </div>
            </header>
            ${showEditForm ? renderEditForm(data) : ""}
            ${renderNeedsAttention(data.alerts)}
            <div class="fac-section-grid">
                ${SECTIONS.map((s) => {
                    const badge = badges[s.id] || 0;
                    return `
                    <button type="button" class="fac-section-tile" data-section="${s.id}" style="--fac-accent: ${s.color}">
                        ${badge > 0 ? `<span class="fac-section-badge">${badge}</span>` : ""}
                        <span class="fac-section-title">${escapeHtml(s.title)}</span>
                    </button>`;
                }).join("")}
            </div>`;
    }

    function bindDetailMainEvents(data) {
        const main = $("location-detail-main");
        main.querySelectorAll(".home-alert-ack").forEach((btn) => {
            btn.addEventListener("click", async () => {
                acknowledgeAlert(userId, btn.dataset.alertId);
                currentDetail = await loadLocationDetail(data.location.id);
                showDetailMain(currentDetail);
            });
        });
        main.querySelectorAll(".fac-section-tile").forEach((btn) => {
            btn.addEventListener("click", () => openSection(btn.dataset.section));
        });
    }

    function employeeProgress(emp, locTasks) {
        return OplixTaskProgress.employeeToday(locTasks, emp.id);
    }

    function shiftStatusLabel(shift) {
        if (!shift.clockInTime) return "Assigned";
        if (!shift.clockOutTime) return "Clocked in";
        return "Completed";
    }

    function isTodayShift(shift) {
        const today = OplixTaskProgress.startOfDay(new Date());
        const tomorrow = new Date(today);
        tomorrow.setDate(tomorrow.getDate() + 1);
        if (!shift.clockInTime && !shift.clockOutTime) return true;
        const cin = toDate(shift.clockInTime);
        const cout = toDate(shift.clockOutTime);
        if (cin && cin >= today && cin < tomorrow) return true;
        if (cout && cout >= today && cout < tomorrow) return true;
        return false;
    }

    function renderSection(sectionId, data) {
        const title = SECTIONS.find((s) => s.id === sectionId)?.title || sectionId;

        switch (sectionId) {
            case "employees":
                return renderPeopleList(title, data.employees, data);
            case "supervisors":
                return renderPeopleList(title, data.supervisors, data);
            case "tasks":
                return window.OplixTasksUI
                    ? OplixTasksUI.renderEmbedded({
                          locationName: data.location.name,
                      })
                    : renderComingSoonSection(title);
            case "shifts":
                return renderShiftsScreen(data);
            case "lottery":
                return renderLotteryScreen(data);
            case "documents":
                return window.OplixFacilityDocuments
                    ? OplixFacilityDocuments.renderSection({
                          userId,
                          locationId: data.location.id,
                          data,
                      })
                    : renderDocumentsScreen(data);
            case "reminders":
                return renderRemindersScreen(data);
            case "payables":
                return renderPayablesScreen(data, true);
            case "receivables":
                return renderPayablesScreen(data, false);
            case "compliance":
                return window.OplixFacilityCompliance
                    ? OplixFacilityCompliance.renderSection({
                          userId,
                          locationId: data.location.id,
                          data,
                      })
                    : renderComingSoonSection(title);
            case "vendors":
            case "utility-providers":
            case "servicers":
                return window.OplixFacilityDirectory
                    ? OplixFacilityDirectory.renderSection(sectionId, {
                          userId,
                          locationId: data.location.id,
                          data,
                      })
                    : renderComingSoonSection(title);
            case "reports":
                return window.OplixReports
                    ? OplixReports.renderEmbedded({
                          locationName: data.location.name,
                      })
                    : renderComingSoonSection(title);
            case "payroll":
                return window.OplixPayrollUI
                    ? OplixPayrollUI.renderEmbedded({
                          locationName: data.location.name,
                      })
                    : renderComingSoonSection(title);
            case "sales":
                return renderComingSoonSection(title);
            default:
                return renderComingSoonSection(title);
        }
    }

    function renderPeopleList(title, people, data) {
        const locId = data.location.id;
        const isSupervisors = title === "Supervisors";
        const addLabel = isSupervisors ? "Add supervisor" : "Add employee";
        const roleAttr = isSupervisors ? ' data-fac-add-role="supervisor"' : "";
        const toolbar = `
            <div class="dir-toolbar">
                <button type="button" class="btn" data-fac-add-employee="${escapeHtml(locId)}"${roleAttr}>${escapeHtml(addLabel)}</button>
            </div>`;
        if (!people.length) {
            return `<h2 class="loc-section-heading">${escapeHtml(title)}</h2>${toolbar}<p class="data-list-empty">No one listed yet.</p>`;
        }
        const rows = people
            .map((emp) => {
                const prog = employeeProgress(emp, data.tasks);
                const progHtml = prog
                    ? `<span class="loc-emp-badge loc-emp-badge--${prog.completed === prog.assigned ? "done" : prog.completed > 0 ? "partial" : "none"}">${prog.completed}/${prog.assigned}</span>`
                    : "";
                const empShift =
                    data.shifts.find(
                        (s) => s.employeeId === emp.id && s.clockInTime && !s.clockOutTime
                    ) ||
                    data.shifts.find((s) => s.employeeId === emp.id && !s.clockInTime) ||
                    {};
                const status = shiftStatusLabel(empShift);
                return `
                <li class="loc-row-card dir-row">
                    <div>
                        <strong>${escapeHtml(emp.name || "Unnamed")}</strong>
                        <span class="data-list-meta">@${escapeHtml(emp.username || "—")}</span>
                    </div>
                    <div class="loc-row-end fac-people-row-end">
                        ${progHtml}
                        <span class="loc-shift-pill">${escapeHtml(status)}</span>
                        <div class="dir-row-actions">
                            <button type="button" class="dir-btn-edit" data-fac-emp-edit="${escapeHtml(emp.id)}">Edit</button>
                            <button type="button" class="dir-btn-edit fac-people-delete" data-fac-emp-delete="${escapeHtml(emp.id)}">Delete</button>
                        </div>
                    </div>
                </li>`;
            })
            .join("");
        return `<h2 class="loc-section-heading">${escapeHtml(title)}</h2>${toolbar}<ul class="loc-row-list">${rows}</ul>`;
    }

    function renderShiftsScreen(data) {
        const todayShifts = data.shifts.filter(isTodayShift);
        const sorted = [...todayShifts].sort((a, b) => {
            const aAssigned = !a.clockInTime;
            const bAssigned = !b.clockInTime;
            if (aAssigned !== bAssigned) return aAssigned ? -1 : 1;
            return (toDate(b.clockInTime) || 0) - (toDate(a.clockInTime) || 0);
        });
        if (!sorted.length) {
            return `<h2 class="loc-section-heading">Shift Manager</h2><p class="data-list-empty">No shifts for today.</p>`;
        }
        return `
            <h2 class="loc-section-heading">Shift Manager</h2>
            <p class="loc-subhint">Today</p>
            <ul class="loc-row-list">
                ${sorted
                    .map((s) => {
                        const name = data.nameById[s.employeeId] || "Employee";
                        const cin = toDate(s.clockInTime);
                        const cout = toDate(s.clockOutTime);
                        const time =
                            cin && cout
                                ? `${cin.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })} – ${cout.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`
                                : cin
                                  ? `In ${cin.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`
                                  : "Not started";
                        return `<li class="loc-row-card"><div><strong>${escapeHtml(name)}</strong><span class="data-list-meta">${escapeHtml(time)}</span></div><span class="loc-shift-pill">${escapeHtml(shiftStatusLabel(s))}</span></li>`;
                    })
                    .join("")}
            </ul>
            <p class="loc-subhint">Older shifts — full history available in location records.</p>`;
    }

    function renderLotteryScreen(data) {
        const forms = [...data.lotteryForms].sort(
            (a, b) => (toDate(b.submittedAt) || 0) - (toDate(a.submittedAt) || 0)
        );
        if (!forms.length) {
            return `<h2 class="loc-section-heading">Lottery</h2><p class="data-list-empty">No lottery forms yet.</p>`;
        }
        return `
            <h2 class="loc-section-heading">Lottery</h2>
            <ul class="loc-row-list">
                ${forms
                    .slice(0, 30)
                    .map((f) => {
                        const d = toDate(f.submittedAt);
                        const sold = f.shiftSummary?.totalSoldAmount;
                        const os = f.shiftSummary?.overShort;
                        const sub = [
                            d ? d.toLocaleString() : "",
                            sold != null ? formatCurrency(sold) + " sold" : "",
                            os != null ? formatCurrency(os) + " O/S" : "",
                        ]
                            .filter(Boolean)
                            .join(" · ");
                        return `<li class="loc-row-card"><div><strong>Shift close</strong><span class="data-list-meta">${escapeHtml(sub)}</span></div></li>`;
                    })
                    .join("")}
            </ul>`;
    }

    function renderDocumentsScreen(data) {
        if (!data.documents.length) {
            return `<h2 class="loc-section-heading">Documents</h2><p class="data-list-empty">No documents yet.</p>`;
        }
        return `
            <h2 class="loc-section-heading">Documents</h2>
            <ul class="loc-row-list">
                ${data.documents
                    .map((d) => {
                        const exp = toDate(d.expiryDate);
                        const sub = exp ? `Expires ${exp.toLocaleDateString()}` : "";
                        return `<li class="loc-row-card"><div><strong>${escapeHtml(d.name || "Document")}</strong>${sub ? `<span class="data-list-meta">${escapeHtml(sub)}</span>` : ""}</div></li>`;
                    })
                    .join("")}
            </ul>`;
    }

    function renderRemindersScreen(data) {
        const open = data.reminders.filter((r) => !r.isCompleted);
        const done = data.reminders.filter((r) => r.isCompleted);
        return `
            <h2 class="loc-section-heading">Reminders</h2>
            ${open.length ? `<h3 class="loc-subheading">Open (${open.length})</h3>${renderReminderList(open)}` : ""}
            ${done.length ? `<h3 class="loc-subheading">Completed</h3>${renderReminderList(done)}` : ""}
            ${!open.length && !done.length ? '<p class="data-list-empty">No reminders.</p>' : ""}`;
    }

    function renderReminderList(items) {
        return `<ul class="loc-row-list">${items
            .map((r) => {
                const due = toDate(r.dueDate);
                return `<li class="loc-row-card"><div><strong>${escapeHtml(r.title || r.text || "Reminder")}</strong>${due ? `<span class="data-list-meta">Due ${due.toLocaleDateString()}</span>` : ""}</div></li>`;
            })
            .join("")}</ul>`;
    }

    function renderPayablesScreen(data, isPayable) {
        const items = isPayable ? data.payables : data.receivables;
        const title = isPayable ? "Payables" : "Receivables";
        const active = items.filter((p) => (isPayable ? !p.isPaid : !p.isReceived));
        const paid = items.filter((p) => (isPayable ? p.isPaid : p.isReceived));
        const total = active.reduce((s, p) => s + (p.amount || 0), 0);

        return `
            <h2 class="loc-section-heading">${title}</h2>
            <div class="loc-total-banner">
                <span>Total ${isPayable ? "payables" : "receivables"}</span>
                <strong>${formatCurrency(total)}</strong>
            </div>
            <h3 class="loc-subheading">Active (${active.length})</h3>
            ${renderMoneyList(active, isPayable)}
            ${paid.length ? `<h3 class="loc-subheading">History (${paid.length})</h3>${renderMoneyList(paid.slice(0, 20), isPayable, true)}` : ""}`;
    }

    function renderMoneyList(items, isPayable, history) {
        if (!items.length) return '<p class="data-list-empty">None</p>';
        return `<ul class="loc-row-list">${items
            .map((p) => {
                const party = isPayable ? p.payTo : p.receiveFrom;
                const due = toDate(p.dueDate);
                const sub = [party, due ? `Due ${due.toLocaleDateString()}` : "", history ? "Paid" : ""]
                    .filter(Boolean)
                    .join(" · ");
                return `<li class="loc-row-card"><div><strong>${formatCurrency(p.amount)}</strong><span class="data-list-meta">${escapeHtml(sub)}</span></div></li>`;
            })
            .join("")}</ul>`;
    }

    function renderComingSoonSection(title) {
        return `
            <h2 class="loc-section-heading">${escapeHtml(title)}</h2>
            <p class="data-list-empty">Full ${escapeHtml(title.toLowerCase())} tools are not available on web yet.</p>`;
    }

    function updateNav(mode) {
        const backFac = $("location-detail-back");
        const backSec = $("location-section-back");
        if (mode === "list") {
            backFac.hidden = true;
            backSec.hidden = true;
        } else if (mode === "detail") {
            backFac.hidden = false;
            backSec.hidden = true;
        } else {
            backFac.hidden = true;
            backSec.hidden = false;
        }
    }

    function showDetailMain(data) {
        currentDetail = data;
        $("location-detail-loading").hidden = true;
        $("location-detail-main").hidden = false;
        $("location-section-panel").hidden = true;
        $("location-detail-main").innerHTML = renderLocationMain(data);
        bindDetailMainEvents(data);
        updateNav("detail");
        attachFacEditSaveReady();
    }

    function attachFacEditSaveReady() {
        facEditSaveReady?.detach();
        facEditSaveReady = null;
        if (!showEditForm || !window.OplixFormSaveReady) return;
        const form = $("fac-edit-form");
        if (!form) return;
        facEditSaveReady = OplixFormSaveReady.watch(form, { mode: "edit" });
    }

    function bindPeopleSectionActions(content, sectionId) {
        content.querySelectorAll("[data-fac-emp-edit]").forEach((btn) => {
            btn.addEventListener("click", async () => {
                const empId = btn.dataset.facEmpEdit;
                if (window.showDashboardPanel) showDashboardPanel("employees");
                if (window.OplixEmployeesUI?.openEdit) {
                    await OplixEmployeesUI.openEdit(empId);
                }
            });
        });
        content.querySelectorAll("[data-fac-emp-delete]").forEach((btn) => {
            btn.addEventListener("click", async () => {
                const empId = btn.dataset.facEmpDelete;
                const emp = currentDetail?.allPeople?.find((e) => e.id === empId);
                if (!emp) return;
                if (
                    !confirm(
                        `Delete ${emp.name || "this employee"}?\n\nThis removes their login and facility assignments.`
                    )
                ) {
                    return;
                }
                try {
                    await window.OplixEmployeesStore.deleteEmployee(userId, emp);
                    if (window.OplixEmployeesUI?.refresh) {
                        await OplixEmployeesUI.refresh();
                    }
                    if (window.OplixDashboard?.reloadLocations) {
                        await OplixDashboard.reloadLocations();
                    }
                    currentDetail = await loadLocationDetail(currentDetail.location.id);
                    openSection(sectionId);
                } catch (err) {
                    alert(err.message || "Could not delete employee.");
                }
            });
        });
    }

    function openSection(sectionId) {
        if (!currentDetail) return;
        currentSectionId = sectionId;
        $("location-detail-main").hidden = true;
        $("location-section-panel").hidden = false;
        const content = $("location-section-content");
        content.innerHTML = renderSection(sectionId, currentDetail);
        content.dataset.dirBound = "";
        if (window.OplixFacilityDirectory?.isDirectorySection(sectionId)) {
            OplixFacilityDirectory.bind(content, sectionId, {
                userId,
                locationId: currentDetail.location.id,
                data: currentDetail,
                onRefresh: async () => {
                    currentDetail = await loadLocationDetail(currentDetail.location.id);
                    openSection(sectionId);
                },
            });
        }
        if (window.OplixFacilityCompliance?.isComplianceSection(sectionId)) {
            content.dataset.compBound = "";
            OplixFacilityCompliance.bind(content, {
                userId,
                locationId: currentDetail.location.id,
                data: currentDetail,
                onRefresh: async () => {
                    currentDetail = await loadLocationDetail(currentDetail.location.id);
                    openSection(sectionId);
                },
            });
        }
        if (window.OplixFacilityDocuments?.isDocumentsSection(sectionId)) {
            content.dataset.docBound = "";
            OplixFacilityDocuments.bind(content, {
                userId,
                locationId: currentDetail.location.id,
                data: currentDetail,
                onRefresh: async () => {
                    currentDetail = await loadLocationDetail(currentDetail.location.id);
                    openSection(sectionId);
                },
            });
        }
        if (sectionId === "reports" && window.OplixReports) {
            content.querySelector("#rpt-embedded-root")?.removeAttribute("data-rpt-embedded-bound");
            OplixReports.bindEmbedded(content, {
                userId,
                locationId: currentDetail.location.id,
                locationName: currentDetail.location.name,
                locations: locations.length ? locations : [currentDetail.location],
            });
        }
        if (sectionId === "payroll" && window.OplixPayrollUI) {
            OplixPayrollUI.bindEmbedded(content, {
                userId,
                locationId: currentDetail.location.id,
                locationName: currentDetail.location.name,
                locations: locations.length ? locations : [currentDetail.location],
            });
        }
        if (sectionId === "tasks" && window.OplixTasksUI) {
            OplixTasksUI.bindEmbedded(content, {
                userId,
                locationId: currentDetail.location.id,
                locationName: currentDetail.location.name,
                locations: locations.length ? locations : [currentDetail.location],
            });
        }
        content.querySelectorAll("[data-fac-add-employee]").forEach((btn) => {
            btn.addEventListener("click", () => {
                const locId = btn.dataset.facAddEmployee;
                const role = btn.dataset.facAddRole || "employee";
                if (window.showDashboardPanel) showDashboardPanel("employees");
                if (window.OplixEmployeesUI?.openCreate) {
                    OplixEmployeesUI.openCreate(locId, role);
                }
            });
        });
        if (sectionId === "employees" || sectionId === "supervisors") {
            bindPeopleSectionActions(content, sectionId);
        }
        saveFacNav();
        updateNav("section");
    }

    function closeSection() {
        if (!currentDetail) return;
        currentSectionId = null;
        saveFacNav();
        showDetailMain(currentDetail);
    }

    async function openLocation(locationId, options) {
        const listView = $("facilities-list-view");
        const detailView = $("location-detail-view");
        const sectionId = options?.sectionId || null;

        showEditForm = false;
        currentSectionId = sectionId;
        listView.hidden = true;
        detailView.hidden = false;
        $("location-detail-loading").hidden = false;
        $("location-detail-main").hidden = true;
        $("location-section-panel").hidden = true;
        $("location-detail-loading").textContent = "Loading location…";

        try {
            const data = await loadLocationDetail(locationId);
            showDetailMain(data);
            if (sectionId) {
                openSection(sectionId);
            } else {
                saveFacNav();
            }
        } catch (err) {
            if (options?.restoring) {
                clearFacNav();
                currentSectionId = null;
                closeLocation();
                listRendered = false;
                renderList();
                return;
            }
            $("location-detail-loading").hidden = true;
            $("location-detail-main").hidden = false;
            $("location-detail-main").innerHTML = `<p class="app-error">${escapeHtml(err.message || "Failed to load facility.")}</p>`;
            updateNav("detail");
        }
    }

    function closeLocation() {
        $("facilities-list-view").hidden = false;
        $("location-detail-view").hidden = true;
        currentDetail = null;
        currentSectionId = null;
        showEditForm = false;
        clearFacNav();
        updateNav("list");
    }

    function resetToRoot() {
        showCreateForm = false;
        showEditForm = false;
        closeLocation();
        renderCreateForm();
    }

    function bindFacilitiesShell() {
        const panel = $("panel-facilities");
        if (!panel || panel.dataset.facShellBound) return;
        panel.dataset.facShellBound = "1";

        panel.addEventListener("click", async (e) => {
            if (e.target.id === "fac-add-btn") {
                showCreateForm = true;
                renderList();
                $("facilities-create")?.querySelector('[name="name"]')?.focus();
                return;
            }
            if (e.target.id === "fac-create-cancel") {
                showCreateForm = false;
                renderList();
                return;
            }
            if (e.target.id === "fac-edit-btn" && currentDetail) {
                showEditForm = true;
                showDetailMain(currentDetail);
                $("fac-edit-form")?.querySelector('[name="name"]')?.focus();
                return;
            }
            if (e.target.id === "fac-edit-cancel" && currentDetail) {
                showEditForm = false;
                showDetailMain(currentDetail);
                return;
            }
            if (e.target.id === "fac-delete-btn" && currentDetail) {
                const name = currentDetail.location.name || "this facility";
                if (
                    !confirm(
                        `Delete "${name}"?\n\nThis permanently removes employees, shifts, tasks, books data, and all records for this facility. This cannot be undone.`
                    )
                ) {
                    return;
                }
                const status = $("fac-edit-status") || $("location-detail-main");
                try {
                    await Store().deleteLocation(userId, currentDetail.location.id);
                    showEditForm = false;
                    closeLocation();
                    await afterLocationsChanged();
                } catch (err) {
                    alert(err.message || "Could not delete facility.");
                }
            }
        });

        panel.addEventListener("submit", async (e) => {
            if (e.target.id === "fac-edit-form" && currentDetail) {
                e.preventDefault();
                const status = $("fac-edit-status");
                const fd = new FormData(e.target);
                const name = String(fd.get("name") || "").trim();
                const address = String(fd.get("address") || "").trim();
                const facilityType = fd.get("facilityType");
                if (!name || !address) return;
                if (status) status.textContent = "Saving…";
                try {
                    const updated = await Store().updateLocation(
                        userId,
                        currentDetail.location.id,
                        { name, address, facilityType }
                    );
                    if (updated) {
                        const idx = locations.findIndex((l) => l.id === updated.id);
                        if (idx >= 0) locations[idx] = { ...locations[idx], ...updated };
                    }
                    showEditForm = false;
                    await afterLocationsChanged();
                    currentDetail = await loadLocationDetail(currentDetail.location.id);
                    showDetailMain(currentDetail);
                    if (status) status.textContent = "";
                } catch (err) {
                    if (status) status.textContent = err.message || "Could not save.";
                }
                return;
            }
            if (e.target.id !== "fac-create-form") return;
            e.preventDefault();
            const status = $("fac-create-status");
            const fd = new FormData(e.target);
            const name = String(fd.get("name") || "").trim();
            const address = String(fd.get("address") || "").trim();
            const facilityType = fd.get("facilityType");
            if (!name || !address) return;

            if (status) status.textContent = "Creating…";
            try {
                const created = await Store().createLocation(userId, {
                    name,
                    address,
                    facilityType,
                });
                showCreateForm = false;
                if (status) status.textContent = "";
                await afterLocationsChanged();
                if (window.OplixLocationDirectoryStore && created?.id) {
                    await OplixLocationDirectoryStore.ensureDefaultUtilityProviders(
                        userId,
                        created.id
                    );
                }
            } catch (err) {
                if (status) status.textContent = err.message || "Could not create facility.";
            }
        });
    }

    window.OplixFacilities = {
        async refresh(uid, locs, taskList) {
            userId = uid;
            locations = locs || [];
            tasks = taskList || [];

            const nav = readFacNav();
            if (nav?.locationId) {
                if (locations.some((l) => l.id === nav.locationId)) {
                    listRendered = true;
                    await openLocation(nav.locationId, {
                        sectionId: nav.sectionId || null,
                        restoring: true,
                    });
                    return;
                }
                clearFacNav();
            }

            listRendered = false;
            const loadingEl = $("facilities-loading");
            const listEl = $("facilities-list");
            if (loadingEl) loadingEl.hidden = false;
            if (listEl) listEl.innerHTML = "";

            if ($("location-detail-view") && !$("location-detail-view").hidden) {
                closeLocation();
            } else {
                currentDetail = null;
                currentSectionId = null;
            }
            renderList();
        },

        ensureLoaded() {
            if (!listRendered && userId) renderList();
        },

        openLocation,
        resetToRoot,
    };

    function bindNav() {
        $("location-detail-back")?.addEventListener("click", closeLocation);
        $("location-section-back")?.addEventListener("click", closeSection);
    }

    bindFacilitiesShell();
    bindNav();
    updateNav("list");
})();
