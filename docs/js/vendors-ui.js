/**
 * Sidebar Vendors tab — organization-wide supplier directory (all facilities).
 */
(function () {
    const M = () => window.OplixLocationDirectoryModel;
    const GlobalStore = () => window.OplixGlobalVendorsStore;
    const DirUI = () => window.OplixFacilityDirectory;

    let userId = null;
    let locations = [];
    let vendors = [];
    let filterLocationId = "";
    let editing = null;
    let saveReadyHandle = null;
    let loadingList = false;
    let loadError = "";

    function $(id) {
        return document.getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function locationName(locationId) {
        return locations.find((l) => l.id === locationId)?.name || "Facility";
    }

    function vendorKey(name) {
        return GlobalStore()?.vendorKey(name) || String(name || "").trim().toLowerCase();
    }

    function recentMonthIds(count) {
        const BM = window.OplixBooksModel;
        if (!BM) return [];
        const now = new Date();
        const ids = [];
        for (let i = 0; i < count; i++) {
            ids.push(BM.monthIdFromDate(new Date(now.getFullYear(), now.getMonth() - i, 1)));
        }
        return ids;
    }

    function money(v) {
        return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
            parseFloat(v) || 0
        );
    }

    function shortDayLabel(dayId) {
        const [y, m, d] = String(dayId || "").split("-").map(Number);
        if (!y || !m || !d) return "";
        return new Date(y, m - 1, d).toLocaleDateString("en-US", {
            month: "short",
            day: "numeric",
            year: "numeric",
        });
    }

    async function loadDirectoryVendors() {
        const GS = GlobalStore();
        if (!userId || !GS) return [];
        return (await GS.list(userId))
            .filter((v) => v.active !== false)
            .map((v) => ({
                ...M().normalizeVendor(v),
                id: v.id,
                fromDirectory: true,
                fromBooks: false,
                usage: {},
            }));
    }

    async function loadBooksPayees() {
        const RS = window.OplixReportsStore;
        if (!userId || !locations.length || !RS?.loadVendorExpenseLines) return [];
        const months = recentMonthIds(12);
        const batches = await Promise.all(
            months.map((monthId) => RS.loadVendorExpenseLines(userId, locations, monthId))
        );
        const byName = new Map();
        batches.flat().forEach((line) => {
            const name = String(line.description || "").trim();
            if (!name) return;
            const key = vendorKey(name);
            const prev = byName.get(key) || {
                name,
                fromDirectory: false,
                fromBooks: true,
                usage: {},
            };
            const locId = line.locationId;
            const usage = prev.usage[locId] || {
                locationId: locId,
                locationName: line.locationName,
                booksEntries: 0,
                booksTotal: 0,
                lastDayId: line.dayId,
            };
            usage.booksEntries += 1;
            usage.booksTotal += parseFloat(line.amount) || 0;
            if (String(line.dayId) > String(usage.lastDayId || "")) usage.lastDayId = line.dayId;
            prev.usage[locId] = usage;
            byName.set(key, prev);
        });
        return [...byName.values()];
    }

    async function loadVendors() {
        loadError = "";
        if (!userId) {
            vendors = [];
            return;
        }
        try {
            if (GlobalStore()?.ensureMigrated) {
                await GlobalStore().ensureMigrated(userId, locations);
            }
            const [directory, payees] = await Promise.all([
                loadDirectoryVendors(),
                loadBooksPayees(),
            ]);
            const byKey = new Map();
            directory.forEach((v) => {
                byKey.set(vendorKey(v.name), { ...v, usage: { ...v.usage } });
            });
            payees.forEach((p) => {
                const key = vendorKey(p.name);
                const existing = byKey.get(key);
                if (existing) {
                    existing.fromBooks = true;
                    Object.entries(p.usage).forEach(([locId, u]) => {
                        const prev = existing.usage[locId];
                        if (!prev) {
                            existing.usage[locId] = { ...u };
                            return;
                        }
                        prev.booksEntries += u.booksEntries;
                        prev.booksTotal += u.booksTotal;
                        if (String(u.lastDayId) > String(prev.lastDayId || "")) {
                            prev.lastDayId = u.lastDayId;
                        }
                    });
                } else {
                    byKey.set(key, {
                        ...p,
                        id: `books:${key}`,
                        category: "",
                        phone: "",
                        email: "",
                        active: true,
                    });
                }
            });
            vendors = [...byKey.values()].sort((a, b) =>
                (a.name || "").localeCompare(b.name || "", undefined, { sensitivity: "base" })
            );
        } catch (err) {
            console.error("[Oplix] Vendors load failed:", err);
            loadError = err.message || "Could not load vendors.";
            vendors = [];
        }
    }

    function usageSummary(v) {
        const rows = Object.values(v.usage || {});
        if (!rows.length) return null;
        const entries = rows.reduce((n, r) => n + (r.booksEntries || 0), 0);
        const total = rows.reduce((n, r) => n + (r.booksTotal || 0), 0);
        const locCount = rows.length;
        const last = rows.reduce((max, r) => (String(r.lastDayId) > String(max) ? r.lastDayId : max), "");
        return { entries, total, locCount, lastDayId: last };
    }

    function filteredVendors() {
        if (!filterLocationId) return vendors;
        return vendors.filter((v) => {
            if (v.fromDirectory) return true;
            return Boolean(v.usage?.[filterLocationId]);
        });
    }

    function renderUsageMeta(v) {
        const bits = [];
        if (filterLocationId) {
            const u = v.usage?.[filterLocationId];
            if (u?.booksEntries) {
                bits.push(
                    `${u.booksEntries} payment${u.booksEntries === 1 ? "" : "s"} at ${locationName(filterLocationId)} · ${money(u.booksTotal)}`
                );
                if (u.lastDayId) bits.push(`last ${shortDayLabel(u.lastDayId)}`);
            }
        } else {
            const summary = usageSummary(v);
            if (summary?.entries) {
                bits.push(
                    `${summary.entries} payment${summary.entries === 1 ? "" : "s"} · ${money(summary.total)}`
                );
                if (summary.locCount > 1) bits.push(`${summary.locCount} facilities`);
                else if (summary.locCount === 1) {
                    const locId = Object.keys(v.usage || {})[0];
                    if (locId) bits.push(locationName(locId));
                }
                if (summary.lastDayId) bits.push(`last ${shortDayLabel(summary.lastDayId)}`);
            }
        }
        if (v.fromBooks && !v.fromDirectory) bits.unshift("From Daily books");
        else if (v.fromBooks && v.fromDirectory) bits.unshift("Also in Daily books");
        return bits.filter(Boolean).join(" · ");
    }

    function renderVendorRow(v) {
        const bits = [v.category, v.phone, v.email].filter(Boolean);
        const usageMeta = renderUsageMeta(v);
        if (usageMeta) bits.push(usageMeta);
        const sub = bits.filter(Boolean).join(" · ");
        const booksOnly = v.fromBooks && !v.fromDirectory;
        return `
            <li class="loc-row-card dir-row vendors-hub-row">
                <div class="vendors-hub-row-main">
                    <strong>${escapeHtml(v.name || "Unnamed vendor")}</strong>
                    ${sub ? `<span class="data-list-meta">${escapeHtml(sub)}</span>` : ""}
                </div>
                <div class="dir-row-actions">
                    ${
                        booksOnly
                            ? `<button type="button" class="btn btn-nav-outline" data-vendor-save="${escapeHtml(v.id)}">Save contact</button>`
                            : `<button type="button" class="dir-btn-edit" data-vendor-edit="${escapeHtml(v.id)}">Edit</button>`
                    }
                </div>
            </li>`;
    }

    function renderAddForm() {
        return `
            <div class="books-panel vendors-hub-form">
                <h3 class="books-subtitle">${editing ? "Edit vendor" : "Add vendor"}</h3>
                <p class="books-hint">Saved to your organization directory — available at every facility.</p>
                <div id="vendors-form-fields"></div>
                <div class="dir-form-actions">
                    <button type="button" class="btn" id="vendors-form-save">Save</button>
                    <button type="button" class="btn btn-nav-outline" id="vendors-form-cancel">Cancel</button>
                    ${
                        editing?.fromDirectory
                            ? `<button type="button" class="btn dir-btn-delete" id="vendors-form-delete">Delete</button>`
                            : ""
                    }
                    <span class="dir-status" id="vendors-form-status"></span>
                </div>
            </div>`;
    }

    function mountVendorFields(vendor) {
        const slot = $("vendors-form-fields");
        if (!slot || !DirUI()?.renderVendorForm) return;
        slot.innerHTML = DirUI().renderVendorForm(vendor || {}, vendor?.id || "", {
            includeActions: false,
        });
    }

    function renderPanel() {
        const root = $("vendors-root");
        if (!root) return;

        const list = filteredVendors();
        const locOptions = [
            `<option value="">All facilities</option>`,
            ...locations.map(
                (l) =>
                    `<option value="${escapeHtml(l.id)}"${l.id === filterLocationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            ),
        ].join("");

        root.innerHTML = `
            <div class="vendors-hub" data-vendors-hub>
                <p class="books-hint">Global vendor directory for your organization. Names here appear in <strong>Daily books</strong> expense descriptions at every facility. Payees from the last 12 months are listed until you save contact details.</p>
                <div class="vendors-hub-toolbar">
                    <label class="books-label vendors-hub-filter">
                        <span class="vendors-hub-filter-label">Filter</span>
                        <select class="books-select" id="vendors-filter-loc">${locOptions}</select>
                    </label>
                    <button type="button" class="btn" id="vendors-add-btn">Add vendor</button>
                </div>
                <div id="vendors-form-slot" hidden></div>
                ${
                    loadingList
                        ? `<p class="data-list-empty">Loading vendor directory…</p>`
                        : loadError
                          ? `<p class="app-error">${escapeHtml(loadError)}</p>`
                          : list.length
                            ? `<ul class="loc-row-list dir-list">${list.map(renderVendorRow).join("")}</ul>`
                            : `<p class="data-list-empty">No vendors yet. Add one above, or names will appear after you enter them on Daily books expenses.</p>`
                }
            </div>`;
    }

    async function refresh() {
        loadingList = true;
        renderPanel();
        await loadVendors();
        loadingList = false;
        renderPanel();
    }

    async function setLocations(locs) {
        locations = locs || [];
        await refresh();
    }

    function showForm(record) {
        editing = record;
        const slot = $("vendors-form-slot");
        if (!slot) return;
        saveReadyHandle?.detach();
        slot.hidden = false;
        slot.innerHTML = renderAddForm();
        mountVendorFields(record || {});
        slot.scrollIntoView({ behavior: "smooth", block: "nearest" });
        if (window.OplixFormSaveReady) {
            saveReadyHandle = OplixFormSaveReady.watch(slot, {
                saveButton: "#vendors-form-save",
                mode: record?.fromDirectory && record?.id ? "edit" : "new",
            });
        }
    }

    function hideForm() {
        editing = null;
        saveReadyHandle?.detach();
        saveReadyHandle = null;
        const slot = $("vendors-form-slot");
        if (slot) {
            slot.hidden = true;
            slot.innerHTML = "";
        }
    }

    function bind() {
        const root = $("vendors-root");
        if (!root || root.dataset.vendorsBound) return;
        root.dataset.vendorsBound = "1";

        root.addEventListener("click", async (e) => {
            if (e.target.id === "vendors-add-btn") {
                showForm(null);
                return;
            }
            if (e.target.id === "vendors-form-cancel") {
                hideForm();
                return;
            }
            if (e.target.id === "vendors-form-save") {
                await saveForm();
                return;
            }
            if (e.target.id === "vendors-form-delete") {
                await deleteForm();
                return;
            }
            const saveBtn = e.target.closest("[data-vendor-save]");
            if (saveBtn) {
                await saveBooksPayee(saveBtn.dataset.vendorSave);
                return;
            }
            const editBtn = e.target.closest("[data-vendor-edit]");
            if (editBtn) {
                const v = vendors.find((x) => x.id === editBtn.dataset.vendorEdit);
                if (v) showForm(v);
                return;
            }
        });

        root.addEventListener("change", async (e) => {
            if (e.target.id === "vendors-filter-loc") {
                filterLocationId = e.target.value;
                hideForm();
                renderPanel();
                return;
            }
        });
    }

    async function saveBooksPayee(rowId) {
        const v = vendors.find((x) => x.id === rowId);
        const GS = GlobalStore();
        if (!v?.name || !GS) return;
        const payload = {
            ...M().defaultVendor(),
            name: v.name,
        };
        const id = GS.newId();
        try {
            await OplixSaveBusy.run(async () => {
                await GS.save(userId, id, payload);
            }, "Saving…");
            await refresh();
        } catch (err) {
            window.alert(err.message || "Could not save vendor contact.");
        }
    }

    async function saveForm() {
        const status = $("vendors-form-status");
        const form = $("vendors-form-fields")?.querySelector("form");
        const GS = GlobalStore();
        if (!form || !DirUI()?.readVendorForm || !GS) return;

        const payload = DirUI().readVendorForm(form);
        if (!payload.name.trim()) {
            if (status) status.textContent = "Name is required.";
            return;
        }

        let id = editing?.fromDirectory ? editing.id : null;
        if (id) {
            const existing = vendors.find((v) => v.id === id);
            if (existing?.createdAt) payload.createdAt = existing.createdAt;
        } else {
            id = GS.newId();
        }

        if (status) status.textContent = "Saving…";
        try {
            await OplixSaveBusy.run(async () => {
                await GS.save(userId, id, payload);
            }, "Saving…");
            hideForm();
            await refresh();
        } catch (err) {
            if (status) status.textContent = err.message || "Failed to save.";
        }
    }

    async function deleteForm() {
        const GS = GlobalStore();
        if (!editing?.fromDirectory || !editing.id || !GS) return;
        if (!confirm("Delete this vendor from the organization directory?")) return;

        const status = $("vendors-form-status");
        if (status) status.textContent = "Deleting…";
        try {
            await GS.remove(userId, editing.id);
            hideForm();
            await refresh();
        } catch (err) {
            if (status) status.textContent = err.message || "Failed to delete.";
        }
    }

    async function init(uid, locs) {
        userId = uid;
        locations = locs || [];
        filterLocationId = "";
        editing = null;
        const hubRoot = $("vendors-root");
        if (hubRoot) hubRoot.dataset.vendorsBound = "";
        bind();
        await refresh();
    }

    async function onShow() {
        if (!userId) return;
        hideForm();
        await refresh();
    }

    function resetToRoot() {
        hideForm();
        filterLocationId = "";
        renderPanel();
    }

    window.OplixVendorsUI = { init, onShow, refresh, setLocations, resetToRoot };
})();
