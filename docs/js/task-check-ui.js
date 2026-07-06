/**
 * Tasks sidebar — review completions, photos, and history by facility.
 */
(function () {
    const M = () => window.OplixTasksModel;
    const Store = () => window.OplixTasksStore;
    const TP = () => window.OplixTaskProgress;
    const Audit = () => window.OplixTaskAssignmentAudit;

    let userId = null;
    let reviewerUserId = null;
    let locations = [];
    let managerTasks = [];
    let currentRootId = "tasks-root";

    let state = {
        view: "locations",
        locationId: "",
        category: "",
        listMode: "current",
        expandedHistoryDate: null,
        tasks: [],
        employees: [],
        nameById: {},
        loading: false,
        status: "",
        statusKind: "",
        photoModal: null,
        editingTaskId: null,
        showAddForm: false,
        form: { description: "", frequency: "daily", employeeIds: [] },
        saving: false,
    };

    function $(id) {
        return document.getElementById(id);
    }

    function rootEl() {
        return $(currentRootId);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function locById(id) {
        return locations.find((l) => l.id === id);
    }

    function locName(id) {
        return locById(id)?.name || "Facility";
    }

    function tasksInCategory(categoryId) {
        return state.tasks.filter((t) => M().inCategory(t, categoryId));
    }

    function formatTs(value) {
        const d = TP().toDate(value);
        if (!d) return "—";
        return `${d.toLocaleDateString()} · ${d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`;
    }

    function dayKey(d) {
        return TP().startOfDay(d).getTime();
    }

    function toDateInputValue(d) {
        const x = TP().startOfDay(d);
        const y = x.getFullYear();
        const m = String(x.getMonth() + 1).padStart(2, "0");
        const day = String(x.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }

    function parseDateInput(value) {
        if (!value) return null;
        const parts = value.split("-").map(Number);
        if (parts.length !== 3) return null;
        return TP().startOfDay(new Date(parts[0], parts[1] - 1, parts[2]));
    }

    function historyDayRange() {
        const today = TP().startOfDay(new Date());
        const days = [];
        for (let i = 0; i < Audit().LOOKBACK_DAYS; i++) {
            const d = new Date(today);
            d.setDate(d.getDate() - i);
            days.push(TP().startOfDay(d));
        }
        return { today, days, oldest: days[days.length - 1] };
    }

    function expandedHistoryDay() {
        const { today, days } = historyDayRange();
        if (state.expandedHistoryDate == null) return today;
        const match = days.find((d) => dayKey(d) === state.expandedHistoryDate);
        return match || today;
    }

    function renderCurrentDateBanner() {
        const now = new Date();
        const label = now.toLocaleDateString(undefined, {
            weekday: "long",
            month: "long",
            day: "numeric",
            year: "numeric",
        });
        return `
            <div class="tc-current-date books-panel">
                <span class="tc-current-date-label">Current cycle</span>
                <strong>${escapeHtml(label)}</strong>
                <p class="data-list-meta">Daily tasks are for today; weekly and monthly tasks use their current cycle.</p>
            </div>`;
    }

    function scoreBadge(tasks) {
        const seg = TP().locationToday(tasks);
        if (!seg) return "";
        const cls =
            seg.displayPercent >= 100
                ? "tc-score--done"
                : seg.displayPercent > 0
                  ? "tc-score--partial"
                  : "tc-score--none";
        return `<span class="tc-score ${cls}">${seg.displayPercent}% today</span>`;
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

    async function loadManagerTasks() {
        const snap = await window.oplixDb.collection("users").doc(userId).collection("tasks").get();
        managerTasks = snap.docs.map((d) => M().normalizeTask({ id: d.id, ...d.data() }, d.data().locationId));
    }

    async function loadLocationData() {
        const locId = state.locationId;
        if (!userId || !locId) return;
        state.loading = true;
        state.status = "Loading…";
        state.statusKind = "info";
        renderPanel();
        try {
            const [people, tasks] = await Promise.all([
                fetchSub(locId, "employees"),
                fetchSub(locId, "tasks"),
            ]);
            state.employees = people;
            state.nameById = {};
            people.forEach((p) => {
                state.nameById[p.id] = p.name || p.username || "Employee";
            });
            state.tasks = tasks.map((t) => M().normalizeTask(t, locId));
            state.status = "";
        } catch (err) {
            state.status = err.message || "Failed to load tasks.";
            state.statusKind = "error";
        } finally {
            state.loading = false;
            renderPanel();
        }
    }

    function renderLocationRow(loc, index) {
        const locTasks = managerTasks.filter((t) => t.locationId === loc.id);
        const accent = `fac-gradient-${index % 8}`;
        const address = loc.address ? String(loc.address).trim() : "";
        const titleAttr = address ? ` title="${escapeHtml(address)}"` : "";
        return `
            <button type="button" class="fac-card ${accent} tc-loc-row"${titleAttr} data-tc-loc="${escapeHtml(loc.id)}">
                <span class="fac-card-name">${escapeHtml(loc.name || "Facility")}</span>
                ${scoreBadge(locTasks)}
            </button>`;
    }

    function renderLocations() {
        return `
            <div class="tc-panel" data-tc-panel>
                ${state.status ? `<div class="tasks-status-banner tasks-status-banner--${escapeHtml(state.statusKind || "info")}">${escapeHtml(state.status)}</div>` : ""}
                <p class="books-hint">Tap a facility to review completions and photo proof.</p>
                ${
                    locations.length
                        ? `<div class="facilities-group-grid tc-loc-grid">${locations
                              .map((loc, i) => renderLocationRow(loc, i))
                              .join("")}</div>`
                        : `<div class="emp-hub-empty"><p class="emp-hub-empty-title">No facilities yet</p><p class="data-list-meta">Add a facility first.</p></div>`
                }
            </div>`;
    }

    function renderCategoryCard(categoryId, count) {
        const cat = M().CATEGORIES[categoryId];
        const countLabel = count === 0 ? "No tasks" : `${count} task${count === 1 ? "" : "s"}`;
        return `
            <button type="button" class="loc-category-card ${cat.cardClass} task-category-card tc-category-card" data-tc-category="${categoryId}">
                <span class="loc-category-icon">${cat.icon}</span>
                <div class="task-category-card-text">
                    <strong>${escapeHtml(cat.title)}</strong>
                    <span class="data-list-meta">${escapeHtml(cat.subtitle)}</span>
                    <span class="task-category-count">${escapeHtml(countLabel)}</span>
                </div>
                <span class="task-category-chevron" aria-hidden="true">›</span>
            </button>`;
    }

    function renderLocationHub() {
        const loc = locById(state.locationId);
        const recurring = state.tasks.filter((t) => M().isRecurring(t)).length;
        const corrective = state.tasks.filter((t) => !M().isRecurring(t)).length;
        return `
            <div class="tc-panel" data-tc-panel>
                ${state.status ? `<div class="tasks-status-banner tasks-status-banner--${escapeHtml(state.statusKind || "info")}">${escapeHtml(state.status)}</div>` : ""}
                <button type="button" class="task-category-back" id="tc-back-locations">← Tasks</button>
                <div class="tc-loc-header books-panel">
                    <h2 class="books-subtitle">${escapeHtml(loc?.name || "Facility")}</h2>
                    ${loc?.address ? `<p class="data-list-meta">${escapeHtml(loc.address)}</p>` : ""}
                </div>
                <div class="loc-category-cards">
                    ${renderCategoryCard("recurring", recurring)}
                    ${renderCategoryCard("corrective", corrective)}
                </div>
            </div>`;
    }

    function statusPillClass(status) {
        if (status === "done") return "tc-pill--done";
        if (status === "partial") return "tc-pill--partial";
        if (status === "unassigned") return "tc-pill--muted";
        return "tc-pill--pending";
    }

    function renderCompletionCard(task, employeeId, completion) {
        const name = state.nameById[employeeId] || "Employee";
        const urls = Audit().completionUrls(completion);
        const thumb = urls[0]
            ? `<img class="tc-comp-thumb" src="${escapeHtml(urls[0])}" alt="" loading="lazy">`
            : `<span class="tc-comp-thumb tc-comp-thumb--empty">📷</span>`;
        const reviewCls =
            completion.isApproved === true
                ? "tc-review--approved"
                : completion.isApproved === false
                  ? "tc-review--rejected"
                  : "";
        const note = completion.note?.trim();
        return `
            <div class="tc-comp-card ${reviewCls}">
                <button type="button" class="tc-comp-photo-btn" data-tc-photo="${escapeHtml(task.id)}" data-tc-emp="${escapeHtml(employeeId)}" data-tc-ts="${escapeHtml(String(TP().toDate(completion.timestamp)?.getTime() || ""))}">
                    ${thumb}
                </button>
                <div class="tc-comp-meta">
                    <strong>Completed by ${escapeHtml(name)}</strong>
                    <span class="data-list-meta">${escapeHtml(formatTs(completion.timestamp))}</span>
                    ${
                        urls.length > 1
                            ? `<span class="data-list-meta">${urls.length} photos — tap to view</span>`
                            : `<span class="data-list-meta">Tap photo to review</span>`
                    }
                    ${note ? `<p class="tc-comp-note">${escapeHtml(note)}</p>` : ""}
                </div>
            </div>`;
    }

    function renderStatusRow(task) {
        const now = new Date();
        const status = M().rowStatus(task, now);
        const label = M().statusLabel(task, now);
        const cycle = M().cyclePeriodLabel(task, now);
        const completions = M().currentCycleCompletions(task, now);
        const compKeys = Object.keys(completions).sort();
        const assignees = M().assigneeText(task, state.nameById);

        return `
            <article class="tc-status-row tc-status-row--${status}" data-tc-task="${escapeHtml(task.id)}">
                <div class="tc-status-row-head">
                    <div class="tc-status-row-title">
                        <h3>${escapeHtml(task.description || "Task")}</h3>
                        ${M().isRecurring(task) ? `<span class="task-freq-pill">${escapeHtml(M().frequencyShort(task))}</span>` : ""}
                        ${cycle ? `<p class="data-list-meta"><span aria-hidden="true">📅</span> ${escapeHtml(cycle)}</p>` : ""}
                    </div>
                    <span class="tc-pill ${statusPillClass(status)}">${escapeHtml(label)}</span>
                </div>
                <p class="tc-assignees"><span aria-hidden="true">👥</span> ${escapeHtml(assignees)}</p>
                ${
                    compKeys.length
                        ? `<div class="tc-completions">${compKeys
                              .map((id) => renderCompletionCard(task, id, completions[id]))
                              .join("")}</div>`
                        : status === "pending"
                          ? `<p class="tc-pending-pill">${M().isRecurring(task) ? "Not completed yet this cycle" : "Not completed"}</p>`
                          : ""
                }
                <button type="button" class="btn btn-nav-outline tc-edit-btn" data-tc-edit="${escapeHtml(task.id)}">Edit task</button>
            </article>`;
    }

    function renderHistorySectionBody(section) {
        const doneRows = section.doneEntries
            .map((entry) => {
                const name = state.nameById[entry.completion.employeeId] || "Employee";
                const urls = Audit().completionUrls(entry.completion);
                const review =
                    entry.completion.isApproved === true
                        ? `<span class="tc-pill tc-pill--done">Approved</span>`
                        : entry.completion.isApproved === false
                          ? `<span class="tc-pill tc-pill--rejected">Disapproved</span>`
                          : "";
                return `
                <div class="tc-history-done">
                    <div class="tc-history-done-head">
                        <strong>${escapeHtml(entry.task.description || "Task")}</strong>
                        <span class="tc-pill tc-pill--done">DONE</span>
                        ${M().isRecurring(entry.task) ? `<span class="task-freq-pill">${escapeHtml(M().frequencyShort(entry.task))}</span>` : ""}
                        ${review}
                    </div>
                    <p class="data-list-meta">${escapeHtml(name)} · ${escapeHtml(formatTs(entry.completion.timestamp))}</p>
                    ${
                        urls.length
                            ? `<button type="button" class="tc-comp-photo-btn tc-history-photo" data-tc-photo="${escapeHtml(entry.task.id)}" data-tc-emp="${escapeHtml(entry.completion.employeeId)}" data-tc-ts="${escapeHtml(String(TP().toDate(entry.completion.timestamp)?.getTime() || ""))}"><img src="${escapeHtml(urls[0])}" alt="" loading="lazy"></button>`
                            : ""
                    }
                </div>`;
            })
            .join("");
        const missedRows = section.missedSlots
            .map((slot) => {
                const name = state.nameById[slot.employeeId] || "Employee";
                return `
                <div class="tc-history-missed">
                    <strong>${escapeHtml(slot.task.description || "Task")}</strong>
                    <span class="tc-pill tc-pill--missed">MISSED</span>
                    <p class="data-list-meta">${escapeHtml(name)}</p>
                </div>`;
            })
            .join("");
        return `${doneRows}${missedRows}`;
    }

    function renderHistoryDateGroup(date, section, expandedKey) {
        const key = dayKey(date);
        const isToday = key === dayKey(new Date());
        const isOpen = key === expandedKey;
        const weekday = date.toLocaleDateString(undefined, { weekday: "long" });
        const shortDate = date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
        const stats = section
            ? `<span class="tc-date-group-stat tc-stat-done">${section.doneCount} done</span>${
                  section.missedCount > 0
                      ? `<span class="tc-date-group-stat tc-stat-missed">${section.missedCount} missed</span>`
                      : ""
              }<span class="tc-date-group-stat">${section.assignedCount} assigned</span>`
            : `<span class="tc-date-group-stat tc-date-group-stat--muted">No activity</span>`;

        const body = section
            ? renderHistorySectionBody(section)
            : `<p class="tc-history-empty-inline">Nothing assigned or completed on this date.</p>`;

        return `
            <div class="tc-date-group${isOpen ? " is-open" : ""}${section ? "" : " tc-date-group--quiet"}" data-tc-date-group="${key}">
                <button type="button" class="tc-date-group-head" data-tc-history-date="${key}" aria-expanded="${isOpen ? "true" : "false"}">
                    <span class="tc-date-group-date">
                        ${isToday ? '<span class="tc-today-tag">Today</span>' : ""}
                        <strong>${escapeHtml(weekday)}, ${escapeHtml(shortDate)}</strong>
                    </span>
                    <span class="tc-date-group-stats">${stats}</span>
                    <span class="tc-date-chevron" aria-hidden="true"></span>
                </button>
                <div class="tc-date-group-body"${isOpen ? "" : " hidden"}>${body}</div>
            </div>`;
    }

    function renderHistory() {
        const list = tasksInCategory(state.category);
        const sections = Audit().sections(list);
        const sectionByKey = {};
        sections.forEach((s) => {
            sectionByKey[s.id] = s;
        });

        const { today, days, oldest } = historyDayRange();
        const pickerDay = expandedHistoryDay();
        const expandedKey = state.expandedHistoryDate;

        const groups = days.map((d) => renderHistoryDateGroup(d, sectionByKey[dayKey(d)], expandedKey)).join("");

        return `
            <div class="tc-history-hub">
                <label class="tc-date-picker books-label">
                    Jump to date
                    <input type="date" class="books-input" id="tc-history-date-input" value="${toDateInputValue(pickerDay)}" max="${toDateInputValue(today)}" min="${toDateInputValue(oldest)}">
                </label>
                <p class="books-hint tc-history-hint">Tap a date to expand or collapse its tasks.</p>
                <div class="tc-history-days">${groups}</div>
            </div>`;
    }

    function renderCategory() {
        const cat = M().CATEGORIES[state.category];
        const list = tasksInCategory(state.category);
        const stats = M().categoryStats(list, new Date());
        return `
            <div class="tc-panel" data-tc-panel>
                ${state.status ? `<div class="tasks-status-banner tasks-status-banner--${escapeHtml(state.statusKind || "info")}">${escapeHtml(state.status)}</div>` : ""}
                <button type="button" class="task-category-back" id="tc-back-location">← ${escapeHtml(locName(state.locationId))}</button>
                <div class="loc-category-card ${cat.cardClass} task-category-header">
                    <span class="loc-category-icon">${cat.icon}</span>
                    <div class="task-category-card-text">
                        <strong>${escapeHtml(cat.title)}</strong>
                        <span class="data-list-meta">${escapeHtml(locName(state.locationId))}</span>
                    </div>
                </div>
                ${
                    list.length
                        ? `<nav class="tc-mode-tabs" aria-label="View mode">
                    <button type="button" class="tc-mode-tab${state.listMode === "current" ? " active" : ""}" data-tc-mode="current">Current</button>
                    <button type="button" class="tc-mode-tab${state.listMode === "history" ? " active" : ""}" data-tc-mode="history">History</button>
                </nav>`
                        : ""
                }
                ${
                    list.length && state.listMode === "current"
                        ? `${renderCurrentDateBanner()}<div class="task-stats-banner">${renderStatsBanner(stats)}</div>`
                        : ""
                }
                ${
                    !list.length
                        ? `<div class="task-empty"><span class="loc-category-icon task-empty-icon">${cat.icon}</span><p>No ${escapeHtml(cat.title.toLowerCase())} tasks at this location yet.</p></div>`
                        : state.listMode === "history"
                          ? renderHistory()
                          : `<div class="tc-status-list">${list.map(renderStatusRow).join("")}</div>`
                }
                <div class="tc-bottom-bar">
                    <button type="button" class="btn btn-nav-outline" id="tc-done">Done</button>
                    <button type="button" class="btn" id="tc-add-task">+ Add task</button>
                </div>
            </div>`;
    }

    function renderStatsBanner(stats) {
        return `
            <div class="task-stat"><strong>${stats.total}</strong><span>Total</span></div>
            <div class="task-stat task-stat--done"><strong>${stats.done}</strong><span>Done</span></div>
            <div class="task-stat task-stat--pending"><strong>${stats.pending}</strong><span>Pending</span></div>`;
    }

    function renderPhotoModal() {
        const m = state.photoModal;
        if (!m) return "";
        const urls = m.urls || [];
        const imgIdx = m.imageIndex || 0;
        const status =
            m.approval === true ? "Approved" : m.approval === false ? "Disapproved" : "Pending review";
        return `
            <div class="tc-photo-overlay" data-tc-photo-overlay>
                <div class="tc-photo-dialog" role="dialog" aria-modal="true" aria-label="Task photo review">
                    <header class="tc-photo-head">
                        <div>
                            <strong>${escapeHtml(m.employeeName || "Employee")}</strong>
                            <span class="data-list-meta">${escapeHtml(formatTs(m.timestamp))}</span>
                            <span class="data-list-meta">${escapeHtml(m.taskDescription || "")}</span>
                        </div>
                        <button type="button" class="books-rm tc-photo-close" id="tc-photo-close" aria-label="Close">×</button>
                    </header>
                    <div class="tc-photo-body">
                        ${
                            urls.length
                                ? `<img class="tc-photo-full" src="${escapeHtml(urls[imgIdx])}" alt="Task completion photo">`
                                : `<p class="data-list-meta">No photo attached.</p>`
                        }
                        ${
                            urls.length > 1
                                ? `<div class="tc-photo-thumbs">${urls
                                      .map(
                                          (u, i) =>
                                              `<button type="button" class="tc-photo-thumb-btn${i === imgIdx ? " active" : ""}" data-tc-img-idx="${i}"><img src="${escapeHtml(u)}" alt=""></button>`
                                      )
                                      .join("")}</div>`
                                : ""
                        }
                    </div>
                    <p class="tc-photo-status">Review status: <strong>${escapeHtml(status)}</strong></p>
                    ${
                        m.disapprovalNote
                            ? `<p class="tc-photo-note">Note: ${escapeHtml(m.disapprovalNote)}</p>`
                            : ""
                    }
                    <label class="books-label tc-disapprove-note" id="tc-disapprove-note-wrap"${m.showDisapproveNote ? "" : " hidden"}>
                        Disapproval reason (optional)
                        <input class="books-input" id="tc-disapprove-note" value="${escapeHtml(m.disapproveDraft || "")}">
                    </label>
                    <div class="tc-photo-actions">
                        <button type="button" class="btn tc-approve-btn" id="tc-photo-approve">Approve</button>
                        <button type="button" class="btn btn-nav-outline tc-reject-btn" id="tc-photo-disapprove">Disapprove</button>
                    </div>
                </div>
            </div>`;
    }

    function renderPanel() {
        const root = rootEl();
        if (!root) return;
        let body = "";
        if (state.view === "locations") body = renderLocations();
        else if (state.view === "location") body = renderLocationHub();
        else if (state.view === "category") body = renderCategory();
        root.innerHTML = body + renderPhotoModal();
    }

    function openPhotoModal(taskId, employeeId, timestampMs) {
        const task = state.tasks.find((t) => t.id === taskId);
        if (!task) return;
        let completion = task.employeeCompletions?.[employeeId];
        if (timestampMs) {
            const target = Number(timestampMs);
            const fromHist = Audit().allCompletionsForHistory(task).find(
                (c) =>
                    c.employeeId === employeeId &&
                    Math.abs(TP().toDate(c.timestamp)?.getTime() - target) < 1000
            );
            if (fromHist) completion = fromHist;
        }
        if (!completion) return;
        state.photoModal = {
            taskId,
            employeeId,
            employeeName: state.nameById[employeeId] || "Employee",
            taskDescription: task.description,
            timestamp: completion.timestamp,
            urls: Audit().completionUrls(completion),
            imageIndex: 0,
            approval: completion.isApproved,
            disapprovalNote: completion.disapprovalNote || "",
            showDisapproveNote: false,
            disapproveDraft: "",
            historyTimestamp: timestampMs ? Number(timestampMs) : null,
        };
        renderPanel();
    }

    function closePhotoModal() {
        state.photoModal = null;
        renderPanel();
    }

    async function submitReview(approved) {
        const m = state.photoModal;
        if (!m) return;
        let note = null;
        if (!approved) {
            if (!m.showDisapproveNote) {
                m.showDisapproveNote = true;
                renderPanel();
                return;
            }
            note = (rootEl()?.querySelector("#tc-disapprove-note")?.value || "").trim() || null;
        }
        const task = state.tasks.find((t) => t.id === m.taskId);
        if (!task) return;
        state.status = "Saving review…";
        state.statusKind = "info";
        renderPanel();
        try {
            await OplixSaveBusy.run(async () => {
                const updated = await Store().reviewCompletion(userId, state.locationId, task, {
                    employeeId: m.employeeId,
                    approved,
                    note,
                    reviewerId: reviewerUserId || userId,
                    completionTimestamp: m.historyTimestamp
                        ? new Date(m.historyTimestamp)
                        : null,
                });
                const idx = state.tasks.findIndex((t) => t.id === updated.id);
                if (idx >= 0) state.tasks[idx] = updated;
                await loadManagerTasks();
                if (window.OplixDashboard?.reloadLocations) await OplixDashboard.reloadLocations();
            }, "Saving review…");
            state.status = approved ? "Approved." : "Disapproved.";
            state.statusKind = "success";
            closePhotoModal();
            renderPanel();
        } catch (err) {
            state.status = err.message || "Review failed.";
            state.statusKind = "error";
            renderPanel();
        }
    }

    function goLocations() {
        state.view = "locations";
        state.locationId = "";
        state.category = "";
        state.listMode = "current";
        state.status = "";
        closePhotoModal();
        renderPanel();
    }

    function goLocation(locId) {
        state.view = "location";
        state.locationId = locId;
        state.category = "";
        state.listMode = "current";
        loadLocationData();
    }

    function goCategory(categoryId) {
        state.view = "category";
        state.category = categoryId;
        state.listMode = "current";
        state.expandedHistoryDate = null;
        renderPanel();
    }

    function toggleHistoryDate(key) {
        if (state.expandedHistoryDate === key) {
            state.expandedHistoryDate = null;
        } else {
            state.expandedHistoryDate = key;
        }
    }

    function scrollToHistoryGroup(key) {
        const el = rootEl()?.querySelector(`[data-tc-date-group="${key}"]`);
        el?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }

    function resetToRoot() {
        goLocations();
    }

    async function openManageTask(locId, categoryId, taskId) {
        if (typeof window.showDashboardPanel === "function") {
            showDashboardPanel("facilities");
        }
        if (window.OplixFacilities?.openLocation) {
            await OplixFacilities.openLocation(locId, { sectionId: "tasks" });
        }
        if (window.OplixTasksUI?.openEmbeddedCategory) {
            await OplixTasksUI.openEmbeddedCategory(locId, categoryId, taskId);
        }
    }

    function ensureBind() {
        const root = rootEl();
        if (!root || root.dataset.tcBound) return;
        root.dataset.tcBound = "1";
        root.addEventListener("click", handleClick);
        root.addEventListener("change", handleChange);
    }

    function bind() {
        ensureBind();
    }

    async function handleClick(e) {
            const locBtn = e.target.closest("[data-tc-loc]");
            if (locBtn) {
                goLocation(locBtn.dataset.tcLoc);
                return;
            }
            if (e.target.id === "tc-back-locations") {
                goLocations();
                return;
            }
            if (e.target.id === "tc-back-location") {
                state.view = "location";
                state.category = "";
                renderPanel();
                return;
            }
            const catBtn = e.target.closest("[data-tc-category]");
            if (catBtn) {
                goCategory(catBtn.dataset.tcCategory);
                return;
            }
            const modeBtn = e.target.closest("[data-tc-mode]");
            if (modeBtn) {
                state.listMode = modeBtn.dataset.tcMode;
                if (state.listMode === "history") {
                    state.expandedHistoryDate = dayKey(new Date());
                }
                renderPanel();
                if (state.listMode === "history" && state.expandedHistoryDate != null) {
                    scrollToHistoryGroup(state.expandedHistoryDate);
                }
                return;
            }
            const dateTile = e.target.closest("[data-tc-history-date]");
            if (dateTile) {
                const key = Number(dateTile.dataset.tcHistoryDate);
                toggleHistoryDate(key);
                renderPanel();
                if (state.expandedHistoryDate === key) {
                    scrollToHistoryGroup(key);
                }
                return;
            }
            const photoBtn = e.target.closest("[data-tc-photo]");
            if (photoBtn) {
                openPhotoModal(
                    photoBtn.dataset.tcPhoto,
                    photoBtn.dataset.tcEmp,
                    photoBtn.dataset.tcTs
                );
                return;
            }
            if (e.target.id === "tc-photo-close" || e.target.closest("[data-tc-photo-overlay]") === e.target) {
                closePhotoModal();
                return;
            }
            const thumbBtn = e.target.closest("[data-tc-img-idx]");
            if (thumbBtn && state.photoModal) {
                state.photoModal.imageIndex = Number(thumbBtn.dataset.tcImgIdx);
                renderPanel();
                return;
            }
            if (e.target.id === "tc-photo-approve") {
                await submitReview(true);
                return;
            }
            if (e.target.id === "tc-photo-disapprove") {
                await submitReview(false);
                return;
            }
            if (e.target.id === "tc-done") {
                goLocations();
                return;
            }
            if (e.target.id === "tc-add-task") {
                await openManageTask(state.locationId, state.category);
                return;
            }
            const editBtn = e.target.closest("[data-tc-edit]");
            if (editBtn) {
                await openManageTask(state.locationId, state.category, editBtn.dataset.tcEdit);
            }
    }

    function handleChange(e) {
        if (e.target.id === "tc-history-date-input") {
            const parsed = parseDateInput(e.target.value);
            if (parsed) {
                const key = dayKey(parsed);
                state.expandedHistoryDate = key;
                renderPanel();
                scrollToHistoryGroup(key);
            }
        }
    }

    async function init(uid, locs) {
        userId = uid;
        reviewerUserId = uid;
        locations = locs || [];
        currentRootId = "tasks-root";
        state.view = "locations";
        state.locationId = "";
        state.category = "";
        const root = rootEl();
        if (root) root.dataset.tcBound = "";
        bind();
        await loadManagerTasks();
        renderPanel();
    }

    async function onShow() {
        if (!userId) return;
        await loadManagerTasks();
        if (state.view === "location" || state.view === "category") {
            await loadLocationData();
        } else {
            renderPanel();
        }
    }

    async function setLocations(locs) {
        locations = locs || [];
        await loadManagerTasks();
        if (state.locationId && state.view !== "locations") {
            await loadLocationData();
        } else {
            renderPanel();
        }
    }

    window.OplixTaskCheckUI = { init, onShow, setLocations, resetToRoot };
})();
