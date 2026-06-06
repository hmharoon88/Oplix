/**
 * Facility Tasks section — add, edit, delete (mirrors iOS Locations → Tasks).
 */
(function () {
    const M = () => window.OplixTasksModel;
    const Store = () => window.OplixTasksStore;

    const VIEW_KEY = "oplix.tasks.view";

    let userId = null;
    let locations = [];
    let currentRootId = "tasks-embedded-root";
    let state = {
        locationId: "",
        view: "hub",
        category: "",
        tasks: [],
        assignablePeople: [],
        nameById: {},
        loading: false,
        saving: false,
        status: "",
        statusKind: "",
        showAddForm: false,
        editingTaskId: null,
        form: { description: "", frequency: "daily", employeeIds: [] },
        embeddedLocationId: null,
    };

    function $(id, root) {
        return (root || document).getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function locName(id) {
        return locations.find((l) => l.id === id)?.name || "Facility";
    }

    function effectiveLocationId() {
        return state.embeddedLocationId || state.locationId;
    }

    function persistView() {
        try {
            sessionStorage.setItem(
                VIEW_KEY,
                JSON.stringify({
                    locationId: state.locationId,
                    view: state.view,
                    category: state.category,
                })
            );
        } catch {
            /* ignore */
        }
    }

    function restoreView() {
        try {
            const raw = sessionStorage.getItem(VIEW_KEY);
            if (!raw) return;
            const saved = JSON.parse(raw);
            if (saved.locationId && locations.some((l) => l.id === saved.locationId)) {
                state.locationId = saved.locationId;
            }
            if (saved.view === "category" && saved.category) {
                state.view = "category";
                state.category = saved.category;
            }
        } catch {
            /* ignore */
        }
    }

    function setStatus(message, kind) {
        state.status = message || "";
        state.statusKind = kind || "";
    }

    async function fetchSub(locationId, name) {
        const snap = await window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(name)
            .get();
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }

    function resetForm(categoryId) {
        state.form = {
            description: "",
            frequency: M().defaultFrequencyForCategory(categoryId || state.category),
            employeeIds: [],
        };
    }

    let taskSaveReady = null;

    function closeForms() {
        taskSaveReady?.detach();
        taskSaveReady = null;
        state.showAddForm = false;
        state.editingTaskId = null;
        resetForm(state.category);
    }

    function attachTaskSaveReady(rootId) {
        taskSaveReady?.detach();
        const root = $(rootId);
        const formWrap = root?.querySelector("[data-task-form]");
        if (!formWrap || !window.OplixFormSaveReady) return;
        taskSaveReady = OplixFormSaveReady.watch(formWrap, {
            saveButton: "#task-save-form",
            isReady: ({ form }) =>
                !!form.querySelector('[name="task_description"]')?.value?.trim(),
        });
    }

    function render() {
        renderPanel();
    }

    async function loadData(keepStatus) {
        const locId = effectiveLocationId();
        if (!userId || !locId) {
            state.tasks = [];
            state.assignablePeople = [];
            state.nameById = {};
            render();
            return;
        }
        const prevStatus = keepStatus ? state.status : "";
        const prevKind = keepStatus ? state.statusKind : "";
        state.loading = true;
        if (!keepStatus) setStatus("Loading…", "info");
        render();
        try {
            const people = await fetchSub(locId, "employees");
            state.assignablePeople = people.map((p) => ({
                id: p.id,
                name: p.name || p.username || "Employee",
            }));
            state.nameById = {};
            state.assignablePeople.forEach((p) => {
                state.nameById[p.id] = p.name;
            });
            state.tasks = await fetchSub(locId, "tasks");
            if (keepStatus) {
                state.status = prevStatus;
                state.statusKind = prevKind;
            } else {
                setStatus("", "");
            }
        } catch (err) {
            setStatus(err.message || "Failed to load tasks.", "error");
        } finally {
            state.loading = false;
            render();
        }
    }

    async function refreshDashboard() {
        if (window.OplixDashboard?.reloadLocations) {
            await OplixDashboard.reloadLocations();
        }
    }

    function syncFormFromDom(root) {
        const panel = root.querySelector("[data-tasks-panel]");
        if (!panel || (!state.showAddForm && !state.editingTaskId)) return;
        const desc = panel.querySelector('[name="task_description"]');
        const freq = panel.querySelector('[name="task_frequency"]');
        if (desc) state.form.description = desc.value;
        if (freq) state.form.frequency = freq.value;
        const ids = [];
        panel.querySelectorAll('[name="task_employee"]:checked').forEach((el) => {
            ids.push(el.value);
        });
        state.form.employeeIds = ids;
    }

    function readForm(root) {
        syncFormFromDom(root);
        const description = String(state.form.description || "").trim();
        const frequency =
            state.editingTaskId || state.category === "corrective"
                ? state.form.frequency || "one_time"
                : state.category === "recurring"
                  ? state.form.frequency || "daily"
                  : "one_time";
        return { description, frequency, employeeIds: state.form.employeeIds || [] };
    }

    async function createTask(root) {
        const locId = effectiveLocationId();
        const { description, frequency, employeeIds } = readForm(root);
        if (!description) {
            setStatus("Enter a task description.", "error");
            render();
            return;
        }

        state.saving = true;
        setStatus("Saving to Firebase…", "info");
        render();

        try {
            if (!Store()) throw new Error("Task store not loaded. Hard refresh the page.");
            const payload = M().buildNewTask({
                description,
                locationId: locId,
                assignedEmployeeIds: employeeIds,
                frequency:
                    state.category === "corrective" ? "one_time" : frequency,
                id: Store().newId(),
            });
            await Store().create(userId, locId, payload);
            closeForms();
            await loadData(true);
            setStatus("Task saved to Firebase.", "success");
            await refreshDashboard();
            persistView();
        } catch (err) {
            console.error("Task create failed:", err);
            setStatus(err.message || "Failed to save task.", "error");
            render();
        } finally {
            state.saving = false;
        }
    }

    async function updateTask(root) {
        const locId = effectiveLocationId();
        const existing = state.tasks.find((t) => t.id === state.editingTaskId);
        if (!existing) {
            setStatus("Task not found. Reload and try again.", "error");
            closeForms();
            render();
            return;
        }

        const { description, frequency, employeeIds } = readForm(root);
        if (!description) {
            setStatus("Enter a task description.", "error");
            render();
            return;
        }

        state.saving = true;
        setStatus("Saving changes…", "info");
        render();

        try {
            const payload = M().mergeTaskUpdate(
                existing,
                {
                    description,
                    assignedEmployeeIds: employeeIds,
                    frequency,
                },
                locId
            );
            await Store().update(userId, locId, payload);

            if (
                existing.crossLocationGroupId &&
                locations.length > 1 &&
                window.confirm(
                    "This task exists at multiple locations.\n\nApply description and frequency changes to all locations that have this task?\n\n(Assignees always stay per location.)"
                )
            ) {
                const { updated, failed } = await Store().propagateSiblings(
                    userId,
                    locId,
                    existing.crossLocationGroupId,
                    description,
                    frequency
                );
                if (failed > 0) {
                    setStatus(
                        `Saved here. ${updated} other location(s) updated; ${failed} could not be updated.`,
                        "error"
                    );
                }
            }

            closeForms();
            await loadData(true);
            if (!state.statusKind || state.statusKind === "info") {
                setStatus("Task updated.", "success");
            }
            await refreshDashboard();
            persistView();
        } catch (err) {
            console.error("Task update failed:", err);
            setStatus(err.message || "Failed to update task.", "error");
            render();
        } finally {
            state.saving = false;
        }
    }

    async function deleteTask(taskId, description) {
        const locId = effectiveLocationId();
        const label = description || "this task";
        if (!window.confirm(`Delete "${label}"?\n\nThis cannot be undone.`)) return;

        state.saving = true;
        setStatus("Deleting…", "info");
        render();
        try {
            await Store().remove(userId, locId, taskId);
            if (state.editingTaskId === taskId) closeForms();
            await loadData(true);
            setStatus("Task deleted.", "success");
            await refreshDashboard();
        } catch (err) {
            console.error("Task delete failed:", err);
            setStatus(err.message || "Failed to delete task.", "error");
            render();
        } finally {
            state.saving = false;
        }
    }

    function openEdit(task) {
        state.showAddForm = false;
        state.editingTaskId = task.id;
        state.form = {
            description: task.description || "",
            frequency: task.frequency || "one_time",
            employeeIds: [...(task.assignedEmployeeIds || [])],
        };
        render();
    }

    function tasksInCategory(categoryId) {
        return state.tasks.filter((t) => M().inCategory(t, categoryId));
    }

    function statusIcon(stats) {
        if (stats.isFullyComplete) return { glyph: "✓", className: "task-status--done" };
        if (stats.isPartiallyComplete) return { glyph: "◐", className: "task-status--partial" };
        return { glyph: "○", className: "task-status--open" };
    }

    function renderTaskRow(task) {
        const now = new Date();
        const stats = M().completionStats(task, now);
        const icon = statusIcon(stats);
        const recurring = M().isRecurring(task);
        const editing = state.editingTaskId === task.id;
        return `
            <li class="task-row-card${stats.isFullyComplete ? " task-row-card--done" : ""}${editing ? " task-row-card--editing" : ""}" data-task-id="${escapeHtml(task.id)}" role="button" tabindex="0" title="Click to edit">
                <span class="task-status-icon ${icon.className}" aria-hidden="true">${icon.glyph}</span>
                <div class="task-row-body">
                    <div class="task-row-title">
                        <strong${stats.isFullyComplete ? ' class="task-row-strike"' : ""}>${escapeHtml(task.description || "Task")}</strong>
                        ${
                            recurring
                                ? `<span class="task-freq-pill">${escapeHtml(M().frequencyShort(task))}</span>`
                                : ""
                        }
                    </div>
                    <p class="task-row-meta">${escapeHtml(M().assigneeText(task, state.nameById))}</p>
                </div>
                ${
                    stats.assignedCount
                        ? `<span class="task-count-pill task-count-pill--${
                              stats.isFullyComplete
                                  ? "done"
                                  : stats.isPartiallyComplete
                                    ? "partial"
                                    : "open"
                          }">${stats.completedCount}/${stats.assignedCount}</span>`
                        : ""
                }
                <button type="button" class="books-rm" data-task-delete="${escapeHtml(task.id)}" data-task-label="${escapeHtml(task.description || "Task")}" title="Delete task">×</button>
            </li>`;
    }

    function renderEmployeeChecks() {
        if (!state.assignablePeople.length) {
            return `<p class="books-hint">No employees at this location yet — add them in Facilities or the app.</p>`;
        }
        const allSelected =
            state.form.employeeIds.length === state.assignablePeople.length &&
            state.assignablePeople.length > 0;
        return `
            <div class="task-assign-list">
                <label class="task-assign-all">
                    <input type="checkbox" id="task-select-all"${allSelected ? " checked" : ""}>
                    Select all
                </label>
                ${state.assignablePeople
                    .map(
                        (p) => `
                    <label class="task-assign-row">
                        <input type="checkbox" name="task_employee" value="${escapeHtml(p.id)}"${
                            state.form.employeeIds.includes(p.id) ? " checked" : ""
                        }>
                        <span>${escapeHtml(p.name)}</span>
                    </label>`
                    )
                    .join("")}
            </div>`;
    }

    function renderTaskForm(mode) {
        const isEdit = mode === "edit";
        const categoryId = state.category;
        const isAddCorrective = !isEdit && categoryId === "corrective";
        const freqOptions = isEdit
            ? M().ALL_FREQUENCIES
            : M().allowedFrequencies(categoryId);

        const freqField = isAddCorrective
            ? `<p class="books-hint task-form-locked">Corrective task — one-time only.</p>`
            : `<label class="books-label">Repeat
                <select class="books-select" name="task_frequency">
                    ${freqOptions
                        .map(
                            (f) =>
                                `<option value="${f}"${
                                    state.form.frequency === f ? " selected" : ""
                                }>${escapeHtml(M().frequencyLabel({ frequency: f }))}</option>`
                        )
                        .join("")}
                </select>
            </label>`;

        const title = isEdit ? "Edit task" : `New ${M().CATEGORIES[categoryId]?.title?.toLowerCase() || ""} task`;

        return `
            <div class="books-panel task-add-form" data-task-form>
                <h3 class="books-subtitle">${escapeHtml(title)}</h3>
                <label class="books-label">Description *
                    <textarea class="books-input task-desc-input" name="task_description" rows="2" placeholder="What needs to be done?" required>${escapeHtml(state.form.description)}</textarea>
                </label>
                ${freqField}
                <fieldset class="task-assign-fieldset">
                    <legend class="books-label">Assign to</legend>
                    ${renderEmployeeChecks()}
                </fieldset>
                <div class="task-form-actions">
                    <button type="button" class="btn books-save" id="task-save-form"${state.saving ? " disabled" : ""}>${isEdit ? "Save changes" : "Save task"}</button>
                    <button type="button" class="btn btn-nav-outline" id="task-cancel-form"${state.saving ? " disabled" : ""}>Cancel</button>
                    ${
                        isEdit
                            ? `<button type="button" class="btn btn-nav-outline task-delete-btn" id="task-delete-form"${state.saving ? " disabled" : ""}>Delete task</button>`
                            : ""
                    }
                </div>
            </div>`;
    }

    function renderStatsBanner(stats) {
        return `
            <div class="task-stats-banner">
                <div class="task-stat"><strong>${stats.total}</strong><span>Total</span></div>
                <div class="task-stat task-stat--done"><strong>${stats.done}</strong><span>Done</span></div>
                <div class="task-stat task-stat--pending"><strong>${stats.pending}</strong><span>Pending</span></div>
            </div>`;
    }

    function renderCategoryCard(categoryId) {
        const cat = M().CATEGORIES[categoryId];
        const list = tasksInCategory(categoryId);
        const countLabel =
            list.length === 0
                ? "No tasks"
                : `${list.length} task${list.length === 1 ? "" : "s"}`;
        return `
            <button type="button" class="loc-category-card ${cat.cardClass} task-category-card" data-task-category="${categoryId}">
                <span class="loc-category-icon">${cat.icon}</span>
                <div class="task-category-card-text">
                    <strong>${escapeHtml(cat.title)}</strong>
                    <span class="data-list-meta">${escapeHtml(cat.subtitle)}</span>
                    <span class="task-category-count">${escapeHtml(countLabel)}</span>
                </div>
                <span class="task-category-chevron" aria-hidden="true">›</span>
            </button>`;
    }

    function renderStatusBanner() {
        if (!state.status) return "";
        return `<div class="tasks-status-banner tasks-status-banner--${escapeHtml(state.statusKind || "info")}" role="status">${escapeHtml(state.status)}</div>`;
    }

    function renderHub() {
        const recurring = tasksInCategory("recurring");
        const corrective = tasksInCategory("corrective");

        return `
            <div class="tasks-panel" data-tasks-panel>
                ${renderStatusBanner()}
                <p class="books-hint">Add, edit, or delete recurring and corrective tasks for this facility (syncs with the iOS app).</p>
                <div class="loc-category-cards">
                    ${renderCategoryCard("recurring")}
                    ${renderCategoryCard("corrective")}
                </div>
                ${
                    recurring.length + corrective.length === 0 && !state.loading
                        ? `<p class="data-list-empty">No tasks yet. Open a category and tap <strong>Add task</strong>.</p>`
                        : ""
                }
            </div>`;
    }

    function renderCategoryView(categoryId) {
        const cat = M().CATEGORIES[categoryId];
        const list = tasksInCategory(categoryId);
        const stats = M().categoryStats(list, new Date());
        const showForm = state.showAddForm || state.editingTaskId;
        const formMode = state.editingTaskId ? "edit" : "add";

        return `
            <div class="tasks-panel" data-tasks-panel>
                ${renderStatusBanner()}
                <button type="button" class="task-category-back" id="tasks-back">← Tasks</button>
                <div class="loc-category-card ${cat.cardClass} task-category-header">
                    <span class="loc-category-icon">${cat.icon}</span>
                    <div class="task-category-card-text">
                        <strong>${escapeHtml(cat.title)}</strong>
                        <span class="data-list-meta">${escapeHtml(cat.subtitle)}</span>
                    </div>
                </div>
                ${list.length ? renderStatsBanner(stats) : ""}
                ${
                    list.length
                        ? `<ul class="task-row-list">${list.map(renderTaskRow).join("")}</ul>`
                        : !showForm
                          ? `<div class="task-empty">
                            <span class="loc-category-icon task-empty-icon">${cat.icon}</span>
                            <p>No ${escapeHtml(cat.title.toLowerCase())} tasks yet. Add the first one below.</p>
                           </div>`
                          : ""
                }
                ${showForm ? renderTaskForm(formMode) : ""}
                <div class="task-category-actions">
                    ${
                        !showForm
                            ? `<button type="button" class="btn books-save" id="task-show-add">+ Add task</button>`
                            : ""
                    }
                </div>
            </div>`;
    }

    function renderPanel() {
        const root = $(currentRootId);
        if (!root) return;

        if (!state.embeddedLocationId && !effectiveLocationId()) {
            root.innerHTML =
                '<p class="data-list-empty">Open a facility and choose Tasks to manage them here.</p>';
            return;
        }

        const body =
            state.view === "hub" ? renderHub() : renderCategoryView(state.category);

        root.innerHTML = body;
        attachTaskSaveReady(currentRootId);
    }

    function bind(rootId) {
        const root = $(rootId);
        if (!root || root.dataset.tasksBound) return;
        root.dataset.tasksBound = "1";

        root.addEventListener("click", async (e) => {
            if (e.target.closest("[data-task-delete]")) {
                const delBtn = e.target.closest("[data-task-delete]");
                await deleteTask(delBtn.dataset.taskDelete, delBtn.dataset.taskLabel);
                return;
            }

            const row = e.target.closest("[data-task-id]");
            if (row && state.view === "category") {
                const task = state.tasks.find((t) => t.id === row.dataset.taskId);
                if (task) {
                    openEdit(task);
                    root.querySelector("[data-task-form]")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
                }
                return;
            }

            const catBtn = e.target.closest("[data-task-category]");
            if (catBtn) {
                state.view = "category";
                state.category = catBtn.dataset.taskCategory;
                closeForms();
                persistView();
                renderPanel();
                return;
            }
            if (e.target.id === "tasks-back") {
                state.view = "hub";
                state.category = "";
                closeForms();
                persistView();
                renderPanel();
                return;
            }
            if (e.target.id === "tasks-reload") {
                await loadData();
                return;
            }
            if (e.target.id === "task-show-add") {
                state.editingTaskId = null;
                resetForm(state.category);
                state.showAddForm = true;
                renderPanel();
                root.querySelector('[name="task_description"]')?.focus();
                return;
            }
            if (e.target.id === "task-cancel-form") {
                closeForms();
                renderPanel();
                return;
            }
            if (e.target.id === "task-save-form") {
                if (state.editingTaskId) await updateTask(root);
                else await createTask(root);
                return;
            }
            if (e.target.id === "task-delete-form") {
                const task = state.tasks.find((t) => t.id === state.editingTaskId);
                if (task) await deleteTask(task.id, task.description);
                return;
            }
            if (e.target.id === "task-select-all") {
                const checked = e.target.checked;
                state.form.employeeIds = checked
                    ? state.assignablePeople.map((p) => p.id)
                    : [];
                renderPanel();
            }
        });

        root.addEventListener("change", async (e) => {
            if (e.target.id === "tasks-location") {
                state.locationId = e.target.value;
                state.view = "hub";
                state.category = "";
                closeForms();
                persistView();
                await loadData();
            }
        });
    }

    async function init(uid, locs, options) {
        userId = uid;
        locations = locs || [];
        state.embeddedLocationId = options?.embeddedLocationId || null;
        if (locations.length && !state.locationId) state.locationId = locations[0].id;
        if (state.embeddedLocationId) state.locationId = state.embeddedLocationId;

        currentRootId = options?.rootId || "tasks-embedded-root";
        const root = $(currentRootId);
        if (root) {
            root.dataset.tasksBound = "";
            bind(currentRootId);
        }
        await loadData();
    }

    async function setLocations(locs) {
        locations = locs || [];
        if (userId && state.embeddedLocationId && document.getElementById("tasks-embedded-root")) {
            await loadData(true);
        }
    }

    async function openEmbeddedCategory(locationId, categoryId, taskId) {
        const slot = document.getElementById("tasks-embedded-root");
        if (!slot || !userId) return;
        if (currentRootId !== "tasks-embedded-root" || !state.embeddedLocationId) {
            await init(userId, locations, {
                rootId: "tasks-embedded-root",
                embeddedLocationId: locationId,
            });
        } else if (state.locationId !== locationId) {
            state.locationId = locationId;
            state.embeddedLocationId = locationId;
            await loadData();
        }
        state.view = "category";
        state.category = categoryId || "";
        closeForms();
        renderPanel();
        if (taskId) {
            const task = state.tasks.find((t) => t.id === taskId);
            if (task) openEdit(task);
        }
    }

    function renderEmbedded(ctx) {
        return `
            <h2 class="loc-section-heading">Tasks</h2>
            <p class="books-hint dir-hint">Recurring and corrective tasks for <strong>${escapeHtml(ctx.locationName || "this facility")}</strong>.</p>
            <div id="tasks-embedded-root"></div>`;
    }

    function bindEmbedded(container, ctx) {
        const slot = container.querySelector("#tasks-embedded-root");
        if (!slot) return;
        slot.dataset.tasksBound = "";
        slot.innerHTML = "";
        init(ctx.userId, ctx.locations || locations, {
            rootId: "tasks-embedded-root",
            embeddedLocationId: ctx.locationId,
        });
    }

    async function navigateToCategory(locationId, categoryId, taskId) {
        return openEmbeddedCategory(locationId, categoryId, taskId);
    }

    window.OplixTasksUI = {
        init,
        setLocations,
        openEmbeddedCategory,
        openCategory(locationId, categoryId, taskId) {
            return openEmbeddedCategory(locationId, categoryId, taskId);
        },
        openEdit(locationId, categoryId, taskId) {
            return openEmbeddedCategory(locationId, categoryId, taskId);
        },
        renderEmbedded,
        bindEmbedded,
    };
})();
