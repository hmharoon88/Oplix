/**
 * Sidebar Compliance tab — licenses, certs & renewals across all facilities.
 */
(function () {
    const M = () => window.OplixComplianceModel;
    const Store = () => window.OplixComplianceStore;

    let userId = null;
    let locations = [];
    let items = [];
    let filterLocationId = "";
    let filterStatus = "all";
    let loading = false;

    function $(id) {
        return document.getElementById(id);
    }

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function formatDate(iso) {
        if (!iso) return "—";
        const d = M().parseISODate(iso);
        if (!d) return iso;
        return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    }

    function locationName(locationId) {
        return locations.find((l) => l.id === locationId)?.name || "Facility";
    }

    function statusRank(item) {
        const d = M().displayStatus(item);
        if (d.id === "expired") return 0;
        if (d.id === "pending_renewal" && M().isRenewalOverdue(item)) return 1;
        if (d.id === "expiring_soon") return 2;
        if (d.id === "pending_renewal") return 3;
        return 4;
    }

    function matchesStatusFilter(item) {
        if (filterStatus === "all") return true;
        const d = M().displayStatus(item);
        if (filterStatus === "attention") return M().needsAttention(item);
        if (filterStatus === "expired") return d.id === "expired";
        if (filterStatus === "expiring_soon") return d.id === "expiring_soon";
        if (filterStatus === "pending_renewal") return d.id === "pending_renewal";
        if (filterStatus === "active") return d.id === "active";
        return true;
    }

    function filteredItems() {
        let list = items.filter(matchesStatusFilter);
        if (filterLocationId) {
            list = list.filter((i) => i.locationId === filterLocationId);
        }
        return list.sort((a, b) => {
            const ra = statusRank(a);
            const rb = statusRank(b);
            if (ra !== rb) return ra - rb;
            const loc = (a.locationName || "").localeCompare(b.locationName || "");
            if (loc !== 0) return loc;
            const da = M().daysUntilExpiry(a);
            const db = M().daysUntilExpiry(b);
            if (da != null && db != null) return da - db;
            if (da != null) return -1;
            if (db != null) return 1;
            return (a.title || M().categoryLabel(a.category)).localeCompare(
                b.title || M().categoryLabel(b.category)
            );
        });
    }

    async function loadItems() {
        if (!userId || !locations.length) {
            items = [];
            return;
        }
        items = await Store().listAll(userId, locations);
    }

    function renderGlobalSummary(list) {
        const c = M().summaryCounts(list);
        if (!c.total) {
            return `<p class="books-hint comp-hub-empty-hint">No licenses or registrations tracked yet. Add records inside each facility under <strong>Compliance</strong>, or open a facility below.</p>`;
        }
        return `
            <div class="comp-summary comp-hub-summary" role="status">
                <span class="comp-summary-stat"><strong>${c.total}</strong> total</span>
                ${c.active ? `<span class="comp-summary-stat comp-summary-stat--active">${c.active} active</span>` : ""}
                ${c.expiring ? `<span class="comp-summary-stat comp-summary-stat--expiring">${c.expiring} expiring soon</span>` : ""}
                ${c.pending ? `<span class="comp-summary-stat comp-summary-stat--pending">${c.pending} renewal</span>` : ""}
                ${c.expired ? `<span class="comp-summary-stat comp-summary-stat--expired">${c.expired} expired</span>` : ""}
            </div>`;
    }

    function renderTableRow(item, showLocation) {
        const title = item.title || M().categoryLabel(item.category);
        const disp = M().displayStatus(item);
        const hint = M().expiryHint(item);
        const rowClass =
            disp.id === "expired"
                ? "comp-table-row--expired"
                : disp.id === "expiring_soon"
                  ? "comp-table-row--expiring"
                  : "";
        const renewed = item.lastRenewedDate ? formatDate(item.lastRenewedDate) : "—";
        const renewalDue = item.renewalDueDate ? formatDate(item.renewalDueDate) : "—";

        return `
            <tr class="comp-table-row${rowClass ? ` ${rowClass}` : ""}" data-comp-hub-loc="${escapeHtml(item.locationId)}">
                ${
                    showLocation
                        ? `<td class="comp-hub-loc-cell"><strong>${escapeHtml(item.locationName)}</strong></td>`
                        : ""
                }
                <td>${escapeHtml(M().recordTypeLabel(item.recordType))}</td>
                <td>
                    <strong class="comp-table-title">${escapeHtml(title)}</strong>
                    <span class="comp-table-meta">${escapeHtml(M().categoryLabel(item.category))}</span>
                </td>
                <td class="comp-table-mono">${item.identifier ? escapeHtml(item.identifier) : "—"}</td>
                <td class="comp-table-date">${renewed}</td>
                <td class="comp-table-date">
                    ${item.expiryDate ? `<span>${escapeHtml(formatDate(item.expiryDate))}</span>` : "—"}
                    ${hint ? `<span class="comp-expiry-hint">${escapeHtml(hint)}</span>` : ""}
                </td>
                <td class="comp-table-date">${renewalDue}</td>
                <td>
                    <span class="comp-status-pill ${disp.className}">${escapeHtml(disp.label)}</span>
                </td>
                <td class="comp-table-actions">
                    <button type="button" class="btn btn-nav-outline comp-hub-open" data-comp-open="${escapeHtml(item.locationId)}" title="Manage at facility">Open</button>
                </td>
            </tr>`;
    }

    function renderTable(list, showLocation) {
        if (!list.length) return "";
        return `
            <div class="comp-table-wrap home-card">
                <table class="home-cc-table comp-table comp-hub-table">
                    <thead>
                        <tr>
                            ${showLocation ? "<th>Facility</th>" : ""}
                            <th>Type</th>
                            <th>Name</th>
                            <th>License #</th>
                            <th>Last renewed</th>
                            <th>Expires</th>
                            <th>Renewal due</th>
                            <th>Status</th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>${list.map((item) => renderTableRow(item, showLocation)).join("")}</tbody>
                </table>
            </div>`;
    }

    function renderLocationGroup(locId, groupItems) {
        const locItems = M().sortItems(groupItems);
        const attention = M().needsAttentionCount(locItems);
        const c = M().summaryCounts(locItems);
        const badges = [
            c.total ? `${c.total} record${c.total === 1 ? "" : "s"}` : "",
            c.expired ? `${c.expired} expired` : "",
            c.expiring ? `${c.expiring} expiring` : "",
            c.pending ? `${c.pending} renewal` : "",
        ]
            .filter(Boolean)
            .join(" · ");

        const tableBlock =
            locItems.length > 0
                ? renderTable(locItems, false)
                : `<p class="data-list-empty comp-hub-loc-empty">No licenses or registrations tracked for this facility yet.</p>`;

        return `
            <section class="comp-hub-group" data-comp-hub-group="${escapeHtml(locId)}">
                <header class="comp-hub-group-head">
                    <div>
                        <h2 class="comp-hub-group-title">${escapeHtml(locationName(locId))}</h2>
                        ${badges ? `<p class="comp-hub-group-meta">${escapeHtml(badges)}</p>` : `<p class="comp-hub-group-meta">No records yet</p>`}
                    </div>
                    <div class="comp-hub-group-actions">
                        ${
                            locItems.length
                                ? attention
                                    ? `<span class="comp-hub-attention">${attention} need${attention === 1 ? "s" : ""} attention</span>`
                                    : `<span class="comp-hub-ok">Up to date</span>`
                                : ""
                        }
                        <button type="button" class="btn btn-nav-outline comp-hub-open" data-comp-open="${escapeHtml(locId)}">${locItems.length ? "Manage" : "Add records"}</button>
                    </div>
                </header>
                ${tableBlock}
            </section>`;
    }

    function renderGrouped(list) {
        const byLoc = {};
        list.forEach((item) => {
            if (!byLoc[item.locationId]) byLoc[item.locationId] = [];
            byLoc[item.locationId].push(item);
        });

        const orderedLocIds = filterLocationId
            ? [filterLocationId]
            : locations.map((l) => l.id);

        if (!orderedLocIds.length) {
            return `<p class="data-list-empty">Add a facility first to track compliance.</p>`;
        }

        const sections = orderedLocIds.map((locId) =>
            renderLocationGroup(locId, byLoc[locId] || [])
        );

        if (filterStatus !== "all" && !list.length) {
            return `<p class="data-list-empty">No records match your filters.</p>`;
        }

        return sections.join("");
    }

    function renderPanel() {
        const root = $("compliance-root");
        if (!root) return;

        const list = filteredItems();
        const locOptions = [
            `<option value="">All facilities</option>`,
            ...locations.map(
                (l) =>
                    `<option value="${escapeHtml(l.id)}"${l.id === filterLocationId ? " selected" : ""}>${escapeHtml(l.name)}</option>`
            ),
        ].join("");

        const statusOptions = [
            { id: "all", label: "All statuses" },
            { id: "attention", label: "Needs attention" },
            { id: "expired", label: "Expired" },
            { id: "expiring_soon", label: "Expiring soon (60 days)" },
            { id: "pending_renewal", label: "Pending renewal" },
            { id: "active", label: "Active" },
        ]
            .map(
                (o) =>
                    `<option value="${o.id}"${o.id === filterStatus ? " selected" : ""}>${escapeHtml(o.label)}</option>`
            )
            .join("");

        const body =
            loading
                ? `<p class="data-list-empty">Loading compliance records…</p>`
                : filterLocationId
                  ? list.length
                      ? renderTable(list, false)
                      : `<p class="data-list-empty">${
                            items.some((i) => i.locationId === filterLocationId)
                                ? "No records match your filters."
                                : "No licenses or registrations tracked for this facility yet."
                        }</p>`
                  : renderGrouped(list)

        root.innerHTML = `
            <div class="comp-hub" data-comp-hub>
                <p class="books-hint">Licenses, certifications, permits, and insurance across every facility — same data as <strong>Facilities → Compliance</strong>. Expiry dates within ${M().EXPIRING_SOON_DAYS} days are flagged as expiring soon.</p>
                ${renderGlobalSummary(filterLocationId ? list : items)}
                <div class="comp-hub-toolbar">
                    <label class="books-label comp-hub-filter">
                        <span class="comp-hub-filter-label">Facility</span>
                        <select class="books-select" id="comp-hub-filter-loc">${locOptions}</select>
                    </label>
                    <label class="books-label comp-hub-filter">
                        <span class="comp-hub-filter-label">Status</span>
                        <select class="books-select" id="comp-hub-filter-status">${statusOptions}</select>
                    </label>
                </div>
                ${body}
            </div>`;
    }

    async function refresh() {
        loading = true;
        renderPanel();
        await loadItems();
        loading = false;
        renderPanel();
    }

    async function setLocations(locs) {
        locations = locs || [];
        await refresh();
    }

    async function openFacilityCompliance(locationId) {
        if (!locationId) return;
        if (typeof window.showDashboardPanel === "function") {
            showDashboardPanel("facilities");
        }
        if (window.OplixFacilities?.openLocation) {
            await OplixFacilities.openLocation(locationId, { sectionId: "compliance" });
        }
    }

    function bind() {
        const root = $("compliance-root");
        if (!root || root.dataset.compHubBound) return;
        root.dataset.compHubBound = "1";

        root.addEventListener("click", async (e) => {
            const openBtn = e.target.closest("[data-comp-open]");
            if (openBtn) {
                await openFacilityCompliance(openBtn.dataset.compOpen);
            }
        });

        root.addEventListener("change", (e) => {
            if (e.target.id === "comp-hub-filter-loc") {
                filterLocationId = e.target.value;
                renderPanel();
                return;
            }
            if (e.target.id === "comp-hub-filter-status") {
                filterStatus = e.target.value;
                renderPanel();
            }
        });
    }

    async function init(uid, locs) {
        userId = uid;
        locations = locs || [];
        filterLocationId = "";
        filterStatus = "all";
        const hubRoot = $("compliance-root");
        if (hubRoot) hubRoot.dataset.compHubBound = "";
        bind();
        await refresh();
    }

    async function onShow() {
        if (!userId) return;
        await refresh();
    }

    function resetToRoot() {
        filterLocationId = "";
        filterStatus = "all";
        renderPanel();
    }

    window.OplixComplianceHubUI = { init, onShow, refresh, setLocations, resetToRoot };
})();
