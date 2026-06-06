/**
 * Sidebar Vendors tab — all supplier contacts across facilities.
 */
(function () {
    const M = () => window.OplixLocationDirectoryModel;
    const Store = () => window.OplixLocationDirectoryStore;
    const DirUI = () => window.OplixFacilityDirectory;

    let userId = null;
    let locations = [];
    let vendors = [];
    let filterLocationId = "";
    let editing = null;
    let saveReadyHandle = null;

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

    async function loadVendors() {
        if (!userId || !locations.length) {
            vendors = [];
            return;
        }
        const rows = await Promise.all(
            locations.map(async (loc) => {
                const list = await Store().list(userId, loc.id, M().COLLECTIONS.vendors);
                return list
                    .filter((v) => v.active !== false)
                    .map((v) => ({
                        ...M().normalizeVendor(v),
                        id: v.id,
                        locationId: loc.id,
                        locationName: loc.name || "Facility",
                    }));
            })
        );
        vendors = rows.flat().sort((a, b) => {
            const loc = a.locationName.localeCompare(b.locationName);
            if (loc !== 0) return loc;
            return (a.name || "").localeCompare(b.name || "");
        });
    }

    function filteredVendors() {
        if (!filterLocationId) return vendors;
        return vendors.filter((v) => v.locationId === filterLocationId);
    }

    function renderVendorRow(v) {
        const sub = [v.category, v.phone, v.email].filter(Boolean).join(" · ");
        return `
            <li class="loc-row-card dir-row vendors-hub-row">
                <div class="vendors-hub-row-main">
                    <strong>${escapeHtml(v.name || "Unnamed vendor")}</strong>
                    ${sub ? `<span class="data-list-meta">${escapeHtml(sub)}</span>` : ""}
                    ${!filterLocationId ? `<span class="vendors-hub-loc">${escapeHtml(v.locationName)}</span>` : ""}
                </div>
                <div class="dir-row-actions">
                    <button type="button" class="dir-btn-edit" data-vendor-edit="${escapeHtml(v.id)}" data-vendor-loc="${escapeHtml(v.locationId)}">Edit</button>
                    <button type="button" class="btn btn-nav-outline vendors-open-fac" data-vendor-open="${escapeHtml(v.locationId)}" title="Open facility">Open</button>
                </div>
            </li>`;
    }

    function renderAddForm(defaultLocationId) {
        const locId = defaultLocationId || locations[0]?.id || "";
        const locOptions = locations
            .map(
                (l) =>
                    `<option value="${escapeHtml(l.id)}"${l.id === locId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            )
            .join("");
        return `
            <div class="books-panel vendors-hub-form">
                <h3 class="books-subtitle">${editing ? "Edit vendor" : "Add vendor"}</h3>
                <label class="books-label">Facility
                    <select class="books-select" id="vendors-form-location"${editing ? " disabled" : ""}>${locOptions}</select>
                </label>
                <div id="vendors-form-fields"></div>
                <div class="dir-form-actions">
                    <button type="button" class="btn" id="vendors-form-save">Save</button>
                    <button type="button" class="btn btn-nav-outline" id="vendors-form-cancel">Cancel</button>
                    ${
                        editing
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

        let grouped = "";
        if (!filterLocationId) {
            const byLoc = {};
            list.forEach((v) => {
                if (!byLoc[v.locationId]) byLoc[v.locationId] = [];
                byLoc[v.locationId].push(v);
            });
            grouped = Object.entries(byLoc)
                .map(
                    ([locId, items]) => `
                <section class="vendors-hub-group">
                    <h2 class="vendors-hub-group-title">${escapeHtml(locationName(locId))}</h2>
                    <ul class="loc-row-list dir-list">${items.map(renderVendorRow).join("")}</ul>
                </section>`
                )
                .join("");
        } else {
            grouped =
                list.length > 0
                    ? `<ul class="loc-row-list dir-list">${list.map(renderVendorRow).join("")}</ul>`
                    : `<p class="data-list-empty">No vendors for this facility yet.</p>`;
        }

        root.innerHTML = `
            <div class="vendors-hub" data-vendors-hub>
                <p class="books-hint">Supplier contacts saved per facility — same data as <strong>Facilities → Vendors</strong>.</p>
                <div class="vendors-hub-toolbar">
                    <label class="books-label vendors-hub-filter">
                        <span class="vendors-hub-filter-label">Facility</span>
                        <select class="books-select" id="vendors-filter-loc">${locOptions}</select>
                    </label>
                    <button type="button" class="btn" id="vendors-add-btn"${locations.length ? "" : " disabled"}>Add vendor</button>
                </div>
                <div id="vendors-form-slot" hidden></div>
                ${
                    list.length
                        ? grouped
                        : `<p class="data-list-empty">No vendors yet.${locations.length ? " Add one above or open a facility." : ""}</p>`
                }
            </div>`;
    }

    async function refresh() {
        await loadVendors();
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
        const locId = record?.locationId || filterLocationId || locations[0]?.id;
        slot.hidden = false;
        slot.innerHTML = renderAddForm(locId);
        mountVendorFields(record || {});
        slot.scrollIntoView({ behavior: "smooth", block: "nearest" });
        if (window.OplixFormSaveReady) {
            saveReadyHandle = OplixFormSaveReady.watch(slot, {
                saveButton: "#vendors-form-save",
                mode: record?.id ? "edit" : "new",
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
            const editBtn = e.target.closest("[data-vendor-edit]");
            if (editBtn) {
                const v = vendors.find(
                    (x) => x.id === editBtn.dataset.vendorEdit && x.locationId === editBtn.dataset.vendorLoc
                );
                if (v) showForm(v);
                return;
            }
            const openBtn = e.target.closest("[data-vendor-open]");
            if (openBtn) {
                const locId = openBtn.dataset.vendorOpen;
                if (typeof window.showDashboardPanel === "function") {
                    showDashboardPanel("facilities");
                }
                if (window.OplixFacilities?.openLocation) {
                    await OplixFacilities.openLocation(locId, { sectionId: "vendors" });
                }
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

    async function saveForm() {
        const status = $("vendors-form-status");
        const form = $("vendors-form-fields")?.querySelector("form");
        if (!form || !DirUI()?.readVendorForm) return;

        const locationId =
            editing?.locationId || $("vendors-form-location")?.value || locations[0]?.id;
        if (!locationId) return;

        const payload = DirUI().readVendorForm(form);
        if (!payload.name.trim()) {
            if (status) status.textContent = "Name is required.";
            return;
        }

        let id = editing?.id;
        if (id) {
            const existing = vendors.find((v) => v.id === id && v.locationId === locationId);
            if (existing?.createdAt) payload.createdAt = existing.createdAt;
        } else {
            id = Store().newId();
        }

        if (status) status.textContent = "Saving…";
        try {
            await Store().save(userId, locationId, M().COLLECTIONS.vendors, id, payload);
            hideForm();
            await refresh();
        } catch (err) {
            if (status) status.textContent = err.message || "Failed to save.";
        }
    }

    async function deleteForm() {
        if (!editing?.id || !editing.locationId) return;
        if (!confirm("Delete this vendor?")) return;

        const status = $("vendors-form-status");
        if (status) status.textContent = "Deleting…";
        try {
            await Store().remove(
                userId,
                editing.locationId,
                M().COLLECTIONS.vendors,
                editing.id
            );
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
