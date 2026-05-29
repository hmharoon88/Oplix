/**
 * Facility section UI — vendors, utility providers, servicers (web-only screens; shared Firestore paths).
 */
(function () {
    const M = () => window.OplixLocationDirectoryModel;
    const Store = () => window.OplixLocationDirectoryStore;

    const SECTION_TO_COLLECTION = {
        vendors: "vendors",
        "utility-providers": "utilityProviders",
        servicers: "servicers",
    };

    function escapeHtml(t) {
        const d = document.createElement("div");
        d.textContent = t == null ? "" : String(t);
        return d.innerHTML;
    }

    function isDirectorySection(sectionId) {
        return sectionId in SECTION_TO_COLLECTION;
    }

    function collectionKey(sectionId) {
        return SECTION_TO_COLLECTION[sectionId];
    }

    function itemsForSection(sectionId, data) {
        const key = collectionKey(sectionId);
        return data[key] || [];
    }

    function sectionTitle(sectionId) {
        if (sectionId === "vendors") return "Vendors";
        if (sectionId === "utility-providers") return "Utilities";
        if (sectionId === "servicers") return "Servicers";
        return sectionId;
    }

    function renderListRow(sectionId, item) {
        if (sectionId === "vendors") {
            const sub = [item.category, item.phone, item.email].filter(Boolean).join(" · ");
            return `
                <li class="loc-row-card dir-row" data-dir-id="${escapeHtml(item.id)}">
                    <div>
                        <strong>${escapeHtml(item.name || "Unnamed vendor")}</strong>
                        ${sub ? `<span class="data-list-meta">${escapeHtml(sub)}</span>` : ""}
                    </div>
                    <div class="dir-row-actions">
                        <button type="button" class="dir-btn-edit" data-dir-edit="${escapeHtml(item.id)}">Edit</button>
                    </div>
                </li>`;
        }
        if (sectionId === "utility-providers") {
            const typeLabel = M().utilityDisplayLabel(item);
            const sub = [
                item.providerName,
                item.accountNumber ? `Acct ${item.accountNumber}` : "",
                item.phone,
            ]
                .filter(Boolean)
                .join(" · ");
            return `
                <li class="loc-row-card dir-row" data-dir-id="${escapeHtml(item.id)}">
                    <div>
                        <strong>${escapeHtml(typeLabel)}</strong>
                        ${
                            sub
                                ? `<span class="data-list-meta">${escapeHtml(sub)}</span>`
                                : item.isDefault
                                  ? `<span class="data-list-meta">Add provider details (optional)</span>`
                                  : ""
                        }
                    </div>
                    <div class="dir-row-actions">
                        <button type="button" class="dir-btn-edit" data-dir-edit="${escapeHtml(item.id)}">Edit</button>
                    </div>
                </li>`;
        }
        const sub = [item.serviceType, item.phone, item.email].filter(Boolean).join(" · ");
        return `
            <li class="loc-row-card dir-row" data-dir-id="${escapeHtml(item.id)}">
                <div>
                    <strong>${escapeHtml(item.name || "Unnamed servicer")}</strong>
                    ${sub ? `<span class="data-list-meta">${escapeHtml(sub)}</span>` : ""}
                </div>
                <div class="dir-row-actions">
                    <button type="button" class="dir-btn-edit" data-dir-edit="${escapeHtml(item.id)}">Edit</button>
                </div>
            </li>`;
    }

    function renderVendorForm(item, id) {
        const v = M().normalizeVendor(item);
        return `
            <form class="dir-form" data-dir-form="vendors" data-dir-id="${escapeHtml(id)}">
                <div class="books-grid-2">
                    <label class="books-label">Name *
                        <input class="books-input" name="name" required value="${escapeHtml(v.name)}">
                    </label>
                    <label class="books-label">Category
                        <input class="books-input" name="category" placeholder="e.g. Grocery, Lottery" value="${escapeHtml(v.category)}">
                    </label>
                    <label class="books-label">Contact
                        <input class="books-input" name="contactName" value="${escapeHtml(v.contactName)}">
                    </label>
                    <label class="books-label">Phone
                        <input class="books-input" name="phone" type="tel" value="${escapeHtml(v.phone)}">
                    </label>
                    <label class="books-label">Email
                        <input class="books-input" name="email" type="email" value="${escapeHtml(v.email)}">
                    </label>
                    <label class="books-label">Account #
                        <input class="books-input" name="accountNumber" value="${escapeHtml(v.accountNumber)}">
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="2">${escapeHtml(v.notes)}</textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-dir-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn dir-btn-delete" data-dir-delete>Delete</button>` : ""}
                </div>
            </form>`;
    }

    function renderUtilityForm(item, id) {
        const v = M().normalizeUtilityProvider(item);
        const B = window.OplixBooksModel;
        const isNewCustom = !!item.isCustom && !id;

        if (isNewCustom) {
            return `
            <form class="dir-form" data-dir-form="utilityProviders" data-dir-custom="1" data-dir-id="">
                <p class="books-hint">Creates a new line in <strong>Data input → Utilities & payroll</strong> for this facility.</p>
                <div class="books-grid-2">
                    <label class="books-label">Utility name *
                        <input class="books-input" name="customLabel" required placeholder="e.g. Propane, Phone">
                    </label>
                    <label class="books-label">Provider / company
                        <input class="books-input" name="providerName" value="">
                    </label>
                    <label class="books-label">Account #
                        <input class="books-input" name="accountNumber" value="">
                    </label>
                    <label class="books-label">Phone
                        <input class="books-input" name="phone" type="tel" value="">
                    </label>
                    <label class="books-label">Email
                        <input class="books-input" name="email" type="email" value="">
                    </label>
                    <label class="books-label">Billing contact
                        <input class="books-input" name="billingContact" value="">
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="2"></textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-dir-cancel>Cancel</button>
                </div>
            </form>`;
        }

        const typeLabel = M().utilityDisplayLabel(v);
        const typeField = v.isDefault
            ? `<input type="hidden" name="utilityType" value="${escapeHtml(v.utilityType)}">
               <p class="dir-type-pill">${escapeHtml(typeLabel)}</p>`
            : `<label class="books-label">Utility name
                <input class="books-input" name="customLabel" value="${escapeHtml(v.customLabel || typeLabel)}">
               </label>
               <input type="hidden" name="utilityType" value="${escapeHtml(v.utilityType)}">`;

        return `
            <form class="dir-form" data-dir-form="utilityProviders" data-dir-id="${escapeHtml(id)}">
                <div class="books-grid-2">
                    ${typeField}
                    <label class="books-label">Provider / company
                        <input class="books-input" name="providerName" value="${escapeHtml(v.providerName)}">
                    </label>
                    <label class="books-label">Account #
                        <input class="books-input" name="accountNumber" value="${escapeHtml(v.accountNumber)}">
                    </label>
                    <label class="books-label">Phone
                        <input class="books-input" name="phone" type="tel" value="${escapeHtml(v.phone)}">
                    </label>
                    <label class="books-label">Email
                        <input class="books-input" name="email" type="email" value="${escapeHtml(v.email)}">
                    </label>
                    <label class="books-label">Billing contact
                        <input class="books-input" name="billingContact" value="${escapeHtml(v.billingContact)}">
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="2">${escapeHtml(v.notes)}</textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-dir-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn dir-btn-delete" data-dir-delete>Delete</button>` : ""}
                </div>
            </form>`;
    }

    function renderServicerForm(item, id) {
        const v = M().normalizeServicer(item);
        const opts = M().SERVICE_TYPES.map(
            (t) =>
                `<option value="${escapeHtml(t)}"${t === v.serviceType ? " selected" : ""}>${escapeHtml(t)}</option>`
        ).join("");
        return `
            <form class="dir-form" data-dir-form="servicers" data-dir-id="${escapeHtml(id)}">
                <div class="books-grid-2">
                    <label class="books-label">Company name *
                        <input class="books-input" name="name" required value="${escapeHtml(v.name)}">
                    </label>
                    <label class="books-label">Service type
                        <select class="books-select" name="serviceType">${opts}</select>
                    </label>
                    <label class="books-label">Phone
                        <input class="books-input" name="phone" type="tel" value="${escapeHtml(v.phone)}">
                    </label>
                    <label class="books-label">Email
                        <input class="books-input" name="email" type="email" value="${escapeHtml(v.email)}">
                    </label>
                    <label class="books-label">Contract end
                        <input class="books-input" name="contractEnd" type="date" value="${escapeHtml(v.contractEnd)}">
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="2">${escapeHtml(v.notes)}</textarea>
                </label>
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-dir-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn dir-btn-delete" data-dir-delete>Delete</button>` : ""}
                </div>
            </form>`;
    }

    function renderForm(sectionId, item, id) {
        if (sectionId === "vendors") return renderVendorForm(item, id);
        if (sectionId === "utility-providers") return renderUtilityForm(item, id);
        return renderServicerForm(item, id);
    }

    function renderSection(sectionId, ctx) {
        const title = sectionTitle(sectionId);
        let items = itemsForSection(sectionId, ctx.data).filter((i) => i.active !== false);
        if (sectionId === "utility-providers") {
            items = M().sortUtilityProviders(items);
        } else {
            items = [...items].sort((a, b) => {
                const an = (a.name || a.providerName || "").toLowerCase();
                const bn = (b.name || b.providerName || "").toLowerCase();
                return an.localeCompare(bn);
            });
        }

        const utilHint =
            sectionId === "utility-providers"
                ? `<p class="books-hint dir-hint">Default types match <strong>Data input</strong> (Internet, Water, Electric, Trash, Gas, Alarm, Rent). Custom utilities you add here also appear in Data input for this facility.</p>`
                : `<p class="books-hint dir-hint">Saved for this facility in Firestore — same paths when the iOS app adds support.</p>`;

        const toolbarBtn =
            sectionId === "utility-providers"
                ? `<button type="button" class="btn" data-dir-add-custom>Add custom utility</button>`
                : `<button type="button" class="btn" data-dir-add>Add ${escapeHtml(title.replace(/s$/, ""))}</button>`;

        return `
            <div class="dir-section" data-dir-section="${escapeHtml(sectionId)}">
                <h2 class="loc-section-heading">${escapeHtml(title)}</h2>
                ${utilHint}
                <div class="dir-toolbar">
                    ${toolbarBtn}
                    <span class="dir-status" data-dir-status></span>
                </div>
                <div class="dir-form-slot" data-dir-form-slot hidden></div>
                ${
                    items.length
                        ? `<ul class="loc-row-list dir-list">${items.map((i) => renderListRow(sectionId, i)).join("")}</ul>`
                        : `<p class="data-list-empty">No ${escapeHtml(title.toLowerCase())} yet.</p>`
                }
            </div>`;
    }

    function readForm(form) {
        const kind = form.dataset.dirForm;
        const fd = new FormData(form);
        const base = { active: true };
        if (kind === "vendors") {
            return M().normalizeVendor({
                ...base,
                name: fd.get("name"),
                category: fd.get("category"),
                contactName: fd.get("contactName"),
                phone: fd.get("phone"),
                email: fd.get("email"),
                accountNumber: fd.get("accountNumber"),
                notes: fd.get("notes"),
            });
        }
        if (kind === "utilityProviders") {
            const B = window.OplixBooksModel;
            if (form.dataset.dirCustom === "1") {
                const customLabel = String(fd.get("customLabel") || "").trim();
                const utilityType = B.slugUtilityKey(customLabel);
                return M().normalizeUtilityProvider({
                    ...base,
                    utilityType,
                    customLabel,
                    isDefault: false,
                    providerName: fd.get("providerName"),
                    accountNumber: fd.get("accountNumber"),
                    phone: fd.get("phone"),
                    email: fd.get("email"),
                    billingContact: fd.get("billingContact"),
                    notes: fd.get("notes"),
                });
            }
            const utilityType = fd.get("utilityType");
            const customLabel = String(fd.get("customLabel") || "").trim();
            const isDefault = B.isStandardUtilityKey(utilityType);
            return M().normalizeUtilityProvider({
                ...base,
                utilityType,
                customLabel: isDefault ? "" : customLabel,
                isDefault,
                providerName: fd.get("providerName"),
                accountNumber: fd.get("accountNumber"),
                phone: fd.get("phone"),
                email: fd.get("email"),
                billingContact: fd.get("billingContact"),
                notes: fd.get("notes"),
            });
        }
        return M().normalizeServicer({
            ...base,
            name: fd.get("name"),
            serviceType: fd.get("serviceType"),
            phone: fd.get("phone"),
            email: fd.get("email"),
            contractEnd: fd.get("contractEnd"),
            notes: fd.get("notes"),
        });
    }

    function bind(container, sectionId, ctx) {
        if (!container || container.dataset.dirBound) return;
        container.dataset.dirBound = "1";

        const section = container.querySelector(`[data-dir-section="${sectionId}"]`);
        if (!section) return;

        const formSlot = section.querySelector("[data-dir-form-slot]");
        const statusEl = section.querySelector("[data-dir-status]");

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function hideForm() {
            if (formSlot) {
                formSlot.hidden = true;
                formSlot.innerHTML = "";
            }
        }

        function showForm(item, id) {
            formSlot.innerHTML = renderForm(sectionId, item, id);
            formSlot.hidden = false;
            formSlot.scrollIntoView({ behavior: "smooth", block: "nearest" });
        }

        section.addEventListener("click", async (e) => {
            if (e.target.matches("[data-dir-add-custom]")) {
                showForm({ isCustom: true }, "");
                return;
            }
            if (e.target.matches("[data-dir-add]")) {
                showForm({}, "");
                return;
            }
            const editId = e.target.closest("[data-dir-edit]")?.dataset.dirEdit;
            if (editId) {
                const item = itemsForSection(sectionId, ctx.data).find((i) => i.id === editId);
                showForm(item || {}, editId);
                return;
            }
            if (e.target.matches("[data-dir-cancel]")) {
                hideForm();
                return;
            }
            if (e.target.matches("[data-dir-delete]")) {
                const form = formSlot.querySelector("form");
                const id = form?.dataset.dirId;
                if (!id || !confirm("Delete this entry?")) return;
                const existing = itemsForSection(sectionId, ctx.data).find((i) => i.id === id);
                if (sectionId === "utility-providers" && existing?.isDefault) {
                    setStatus("Default utilities cannot be deleted.");
                    return;
                }
                setStatus("Deleting…");
                await Store().remove(
                    ctx.userId,
                    ctx.locationId,
                    M().COLLECTIONS[collectionKey(sectionId)],
                    id
                );
                hideForm();
                setStatus("Deleted.");
                await ctx.onRefresh();
                return;
            }
        });

        section.addEventListener("submit", async (e) => {
            const form = e.target.closest("[data-dir-form]");
            if (!form || !section.contains(form)) return;
            e.preventDefault();
            const kind = form.dataset.dirForm;
            let id = form.dataset.dirId;
            const payload = readForm(form);
            if (kind === "vendors" && !payload.name.trim()) return;
            if (kind === "utilityProviders" && form.dataset.dirCustom === "1" && !payload.customLabel.trim()) {
                return;
            }
            if (kind === "servicers" && !payload.name.trim()) return;

            if (kind === "utilityProviders") {
                id = payload.utilityType;
            } else if (!id) {
                id = Store().newId();
            }
            else {
                const existing = itemsForSection(sectionId, ctx.data).find((i) => i.id === id);
                if (existing?.createdAt) payload.createdAt = existing.createdAt;
            }

            setStatus("Saving…");
            await Store().save(ctx.userId, ctx.locationId, kind, id, payload);
            hideForm();
            setStatus("Saved.");
            setTimeout(() => setStatus(""), 2000);
            await ctx.onRefresh();
        });
    }

    window.OplixFacilityDirectory = {
        isDirectorySection,
        renderSection,
        bind,
    };
})();
