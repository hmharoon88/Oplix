/**
 * Firestore CRUD for per-location reminders (iOS parity).
 */
(function () {
    const COLLECTION = "reminders";

    function colRef(userId, locationId) {
        return window.oplixDb
            .collection("users")
            .doc(userId)
            .collection("locations")
            .doc(locationId)
            .collection(COLLECTION);
    }

    function toDate(value) {
        if (!value) return null;
        if (typeof value.toDate === "function") return value.toDate();
        if (value instanceof Date) return value;
        const d = new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    function isoDateInput(value) {
        const d = toDate(value);
        if (!d) return "";
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }

    function dueTimestampFromInput(isoDateStr) {
        if (!isoDateStr) return null;
        const d = new Date(isoDateStr + "T12:00:00");
        if (Number.isNaN(d.getTime())) return null;
        return firebase.firestore.Timestamp.fromDate(d);
    }

    function normalizeReminder(raw, locationId) {
        const r = raw || {};
        return {
            id: r.id || "",
            locationId: r.locationId || locationId || "",
            title: String(r.title || r.text || "").trim(),
            notes: r.notes ? String(r.notes).trim() : "",
            dueDate: r.dueDate || null,
            createdAt: r.createdAt || null,
            isCompleted: !!r.isCompleted,
            completedAt: r.completedAt || null,
            dueReminder: r.dueDate && window.OplixDueDateReminderModel
                ? OplixDueDateReminderModel.normalizeDueReminder(r.dueReminder)
                : null,
            dueReminderSentOn: r.dueReminderSentOn || null,
        };
    }

    function defaultReminder(locationId) {
        return {
            locationId: locationId || "",
            title: "",
            notes: "",
            dueDate: null,
            isCompleted: false,
            completedAt: null,
        };
    }

    function sortReminders(list) {
        return [...(list || [])].sort((a, b) => {
            if (a.isCompleted !== b.isCompleted) return a.isCompleted ? 1 : -1;
            const ad = toDate(a.dueDate)?.getTime() ?? Number.MAX_SAFE_INTEGER;
            const bd = toDate(b.dueDate)?.getTime() ?? Number.MAX_SAFE_INTEGER;
            if (ad !== bd) return ad - bd;
            return (toDate(b.createdAt)?.getTime() || 0) - (toDate(a.createdAt)?.getTime() || 0);
        });
    }

    async function list(userId, locationId) {
        const snap = await colRef(userId, locationId).get();
        return snap.docs.map((d) => normalizeReminder({ id: d.id, ...d.data() }, locationId));
    }

    async function save(userId, locationId, reminder) {
        const r = normalizeReminder(reminder, locationId);
        const id = r.id || newId();
        const payload = {
            id,
            locationId,
            title: r.title,
            notes: r.notes || null,
            isCompleted: r.isCompleted,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        };
        payload.dueDate = r.dueDate || null;
        if (r.dueReminder) {
            payload.dueReminder = r.dueReminder;
        } else {
            payload.dueReminder = firebase.firestore.FieldValue.delete();
        }
        if (r.dueReminderSentOn === null) {
            payload.dueReminderSentOn = firebase.firestore.FieldValue.delete();
        } else if (r.dueReminderSentOn) {
            payload.dueReminderSentOn = r.dueReminderSentOn;
        }
        if (r.isCompleted) {
            payload.completedAt = r.completedAt || firebase.firestore.FieldValue.serverTimestamp();
        } else {
            payload.completedAt = null;
        }
        if (r.createdAt) {
            payload.createdAt = r.createdAt;
        } else {
            payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
        }
        await colRef(userId, locationId).doc(id).set(payload, { merge: true });
        return id;
    }

    async function remove(userId, locationId, reminderId) {
        await colRef(userId, locationId).doc(reminderId).delete();
    }

    function newId() {
        return window.oplixDb.collection("users").doc().id;
    }

    window.OplixRemindersModel = {
        COLLECTION,
        defaultReminder,
        normalizeReminder,
        sortReminders,
        toDate,
        isoDateInput,
        dueTimestampFromInput,
    };

    window.OplixRemindersStore = {
        list,
        save,
        remove,
        newId,
    };

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function formatDue(r) {
        const d = toDate(r.dueDate);
        if (!d) return "";
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function renderRow(r) {
        const done = r.isCompleted;
        return `
            <li class="loc-row-card dir-row rem-row${done ? " rem-row--done" : ""}" data-rem-id="${escapeHtml(r.id)}">
                <button type="button" class="rem-check" data-rem-toggle="${escapeHtml(r.id)}" aria-label="${done ? "Mark incomplete" : "Mark complete"}">
                    ${done ? "✓" : ""}
                </button>
                <div class="rem-row-main">
                    <strong class="${done ? "rem-title--done" : ""}">${escapeHtml(r.title || "Reminder")}</strong>
                    ${r.dueDate ? `<span class="data-list-meta">Due ${escapeHtml(formatDue(r))}</span>` : ""}
                    ${r.notes ? `<span class="data-list-meta">${escapeHtml(r.notes)}</span>` : ""}
                </div>
                <div class="dir-row-actions">
                    <button type="button" class="dir-btn-edit" data-rem-edit="${escapeHtml(r.id)}">Edit</button>
                    <button type="button" class="dir-btn-edit fac-people-delete" data-rem-delete="${escapeHtml(r.id)}">Delete</button>
                </div>
            </li>`;
    }

    function renderForm(reminder, id, locationId) {
        const r = normalizeReminder(reminder, locationId);
        return `
            <form class="dir-form rem-form" data-rem-form data-rem-id="${escapeHtml(id)}">
                <label class="books-label">Title *
                    <input class="books-input" name="title" required maxlength="200" value="${escapeHtml(r.title)}">
                </label>
                <label class="books-label">Due date
                    <input class="books-input" name="dueDate" type="date" value="${escapeHtml(isoDateInput(r.dueDate))}">
                </label>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="3" maxlength="500">${escapeHtml(r.notes)}</textarea>
                </label>
                ${window.OplixDueDateReminderModel ? OplixDueDateReminderModel.renderDueReminderFields(r.dueReminder) : ""}
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save reminder</button>
                    <button type="button" class="btn btn-nav-outline" data-rem-cancel>Cancel</button>
                    <span class="dir-status" data-rem-form-status></span>
                </div>
            </form>`;
    }

    function renderSection(ctx) {
        const sorted = sortReminders(ctx.data?.reminders || []);
        const open = sorted.filter((r) => !r.isCompleted);
        const done = sorted.filter((r) => r.isCompleted);

        return `
            <div class="rem-section" data-rem-section>
                <h2 class="loc-section-heading">Reminders</h2>
                <p class="books-hint">To-dos for this facility — same list as the Oplix app. For org-wide items, use Home → To-Do.</p>
                <div class="dir-toolbar">
                    <button type="button" class="btn" data-rem-add>Add reminder</button>
                    <span class="dir-status" data-rem-status></span>
                </div>
                <div class="dir-form-slot" data-rem-form-slot hidden></div>
                ${
                    open.length
                        ? `<h3 class="loc-subheading">Open (${open.length})</h3><ul class="loc-row-list dir-list rem-list">${open.map(renderRow).join("")}</ul>`
                        : ""
                }
                ${
                    done.length
                        ? `<h3 class="loc-subheading">Completed (${done.length})</h3><ul class="loc-row-list dir-list rem-list">${done.map(renderRow).join("")}</ul>`
                        : ""
                }
                ${!open.length && !done.length ? `<p class="data-list-empty">No reminders yet.</p>` : ""}
            </div>`;
    }

    function bind(container, ctx) {
        if (!container || container.dataset.remBound) return;
        container.dataset.remBound = "1";

        const slot = container.querySelector("[data-rem-form-slot]");
        const statusEl = container.querySelector("[data-rem-status]");
        let saveReady = null;

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function closeForm() {
            saveReady?.detach();
            saveReady = null;
            if (slot) {
                slot.hidden = true;
                slot.innerHTML = "";
            }
        }

        function reminders() {
            return ctx.data?.reminders || [];
        }

        function openForm(item, id) {
            if (!slot) return;
            saveReady?.detach();
            slot.hidden = false;
            slot.innerHTML = renderForm(item, id, ctx.locationId);
            if (window.OplixFormSaveReady) {
                saveReady = OplixFormSaveReady.watch(slot, { mode: id ? "edit" : "new" });
            }
            const form = slot.querySelector("[data-rem-form]");
            form?.querySelector("[data-rem-cancel]")?.addEventListener("click", closeForm);
            if (form && window.OplixDueDateReminderModel) {
                OplixDueDateReminderModel.wireDueReminderForm(form);
            }
            form?.addEventListener("submit", async (e) => {
                e.preventDefault();
                const st = form.querySelector("[data-rem-form-status]");
                const title = String(form.querySelector('[name="title"]')?.value || "").trim();
                if (!title) {
                    if (st) st.textContent = "Title is required.";
                    return;
                }
                if (st) st.textContent = "Saving…";
                const fd = new FormData(form);
                const dueStr = String(fd.get("dueDate") || "").trim();
                const dueDate = dueTimestampFromInput(dueStr);
                const dueReminder = dueDate && window.OplixDueDateReminderModel
                    ? OplixDueDateReminderModel.readDueReminderFromForm(form)
                    : null;
                const existing = reminders().find((r) => r.id === id) || {};
                const existingNorm = normalizeReminder(existing, ctx.locationId);
                const resetSent = window.OplixDueDateReminderModel
                    ? OplixDueDateReminderModel.shouldClearSentFlag(
                          existingNorm.dueDate,
                          dueDate,
                          existingNorm.dueReminder,
                          dueReminder
                      )
                    : false;
                try {
                    await OplixSaveBusy.run(async () => {
                        const payload = {
                            ...existing,
                            id: id || newId(),
                            locationId: ctx.locationId,
                            title,
                            notes: String(fd.get("notes") || "").trim(),
                            dueDate,
                            dueReminder,
                            dueReminderSentOn: resetSent ? null : existingNorm.dueReminderSentOn,
                            isCompleted: existing.isCompleted || false,
                            completedAt: existing.completedAt || null,
                            createdAt: existing.createdAt,
                        };
                        await save(ctx.userId, ctx.locationId, payload);
                    }, "Saving…");
                    closeForm();
                    setStatus("Saved.");
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Save failed.";
                }
            });
        }

        container.addEventListener("click", async (e) => {
            if (e.target.matches("[data-rem-add]")) {
                openForm(defaultReminder(ctx.locationId), "");
                return;
            }
            const editId = e.target.closest("[data-rem-edit]")?.dataset.remEdit;
            if (editId) {
                const item = reminders().find((r) => r.id === editId);
                openForm(item || defaultReminder(ctx.locationId), editId);
                return;
            }
            const delId = e.target.closest("[data-rem-delete]")?.dataset.remDelete;
            if (delId) {
                if (!confirm("Delete this reminder?")) return;
                setStatus("Deleting…");
                try {
                    await remove(ctx.userId, ctx.locationId, delId);
                    setStatus("");
                    await ctx.onRefresh();
                } catch (err) {
                    setStatus(err.message || "Delete failed.");
                }
                return;
            }
            const toggleId = e.target.closest("[data-rem-toggle]")?.dataset.remToggle;
            if (toggleId) {
                const item = reminders().find((r) => r.id === toggleId);
                if (!item) return;
                const completed = !item.isCompleted;
                try {
                    await save(ctx.userId, ctx.locationId, {
                        ...item,
                        isCompleted: completed,
                        completedAt: completed
                            ? firebase.firestore.FieldValue.serverTimestamp()
                            : null,
                    });
                    await ctx.onRefresh();
                } catch (err) {
                    setStatus(err.message || "Update failed.");
                }
            }
        });
    }

    window.OplixFacilityReminders = {
        renderSection,
        bind,
        isRemindersSection(sectionId) {
            return sectionId === "reminders";
        },
    };
})();
