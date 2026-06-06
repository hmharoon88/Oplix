/**
 * Facility Compliance — licenses, registrations, permits, renewals & expiry dates.
 */
(function () {
    const M = () => window.OplixComplianceModel;
    const Store = () => window.OplixComplianceStore;

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

    function renderSummary(items) {
        const c = M().summaryCounts(items);
        if (!c.total) return "";
        return `
            <div class="comp-summary" role="status">
                <span class="comp-summary-stat"><strong>${c.total}</strong> total</span>
                ${c.active ? `<span class="comp-summary-stat comp-summary-stat--active">${c.active} active</span>` : ""}
                ${c.expiring ? `<span class="comp-summary-stat comp-summary-stat--expiring">${c.expiring} expiring</span>` : ""}
                ${c.pending ? `<span class="comp-summary-stat comp-summary-stat--pending">${c.pending} renewal</span>` : ""}
                ${c.expired ? `<span class="comp-summary-stat comp-summary-stat--expired">${c.expired} expired</span>` : ""}
            </div>`;
    }

    function renderAttachmentCell(item) {
        if (!item.attachmentUrl) return "—";
        const label = M().attachmentLabel(item) || "View file";
        const isImg = M().isImageAttachment(item.attachmentFileType, item.attachmentFileName);
        if (isImg) {
            return `
                <a class="comp-attach-thumb" href="${escapeHtml(item.attachmentUrl)}" target="_blank" rel="noopener noreferrer" title="${escapeHtml(label)}">
                    <img src="${escapeHtml(item.attachmentUrl)}" alt="" loading="lazy">
                </a>`;
        }
        return `<a class="comp-attach-link" href="${escapeHtml(item.attachmentUrl)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`;
    }

    function renderTableRow(item) {
        const title = item.title || M().categoryLabel(item.category);
        const disp = M().displayStatus(item);
        const hint = M().expiryHint(item);
        const rowClass = needsRowClass(disp.id);
        return `
            <tr class="comp-table-row${rowClass ? ` ${rowClass}` : ""}" data-comp-id="${escapeHtml(item.id)}">
                <td>${escapeHtml(M().recordTypeLabel(item.recordType))}</td>
                <td>
                    <strong class="comp-table-title">${escapeHtml(title)}</strong>
                    <span class="comp-table-meta">${escapeHtml(M().categoryLabel(item.category))}</span>
                </td>
                <td class="comp-table-mono">${item.identifier ? escapeHtml(item.identifier) : "—"}</td>
                <td>${item.issuingAuthority ? escapeHtml(item.issuingAuthority) : "—"}</td>
                <td class="comp-table-date">
                    ${item.expiryDate ? `<span>${escapeHtml(formatDate(item.expiryDate))}</span>` : "—"}
                    ${hint ? `<span class="comp-expiry-hint">${escapeHtml(hint)}</span>` : ""}
                </td>
                <td class="comp-table-attach">${renderAttachmentCell(item)}</td>
                <td>
                    <span class="comp-status-pill ${disp.className}">${escapeHtml(disp.label)}</span>
                </td>
                <td class="comp-table-actions">
                    <button type="button" class="dir-btn-edit" data-comp-edit="${escapeHtml(item.id)}">Edit</button>
                </td>
            </tr>`;
    }

    function needsRowClass(statusId) {
        if (statusId === "expired") return "comp-table-row--expired";
        if (statusId === "expiring_soon") return "comp-table-row--expiring";
        return "";
    }

    function renderTable(items) {
        if (!items.length) return "";
        return `
            <div class="comp-table-wrap home-card">
                <table class="home-cc-table comp-table">
                    <thead>
                        <tr>
                            <th>Type</th>
                            <th>Name</th>
                            <th>License #</th>
                            <th>Issuing authority</th>
                            <th>Expires</th>
                            <th>File</th>
                            <th>Status</th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>${items.map(renderTableRow).join("")}</tbody>
                </table>
            </div>`;
    }

    function selectOptions(list, selectedId) {
        return list
            .map(
                (o) =>
                    `<option value="${o.id}"${o.id === selectedId ? " selected" : ""}>${escapeHtml(o.label)}</option>`
            )
            .join("");
    }

    function renderAttachmentBlock(item) {
        const v = M().normalizeItem(item);
        if (!v.attachmentUrl) {
            return `
                <div class="comp-attachment" data-comp-attachment>
                    <label class="books-label">License / registration file
                        <input type="file" class="comp-file-input" data-comp-file accept="image/*,.pdf,application/pdf" />
                    </label>
                    <p class="books-hint comp-file-hint">Photo or PDF, max 10 MB. Stored securely for this facility.</p>
                </div>`;
        }
        const label = M().attachmentLabel(v);
        const isImg = M().isImageAttachment(v.attachmentFileType, v.attachmentFileName);
        const preview = isImg
            ? `<a class="comp-attach-preview" href="${escapeHtml(v.attachmentUrl)}" target="_blank" rel="noopener noreferrer"><img src="${escapeHtml(v.attachmentUrl)}" alt=""></a>`
            : `<a class="comp-attach-link" href="${escapeHtml(v.attachmentUrl)}" target="_blank" rel="noopener noreferrer">Open ${escapeHtml(label)}</a>`;
        return `
            <div class="comp-attachment" data-comp-attachment data-has-attachment="1">
                <span class="books-label">Current file</span>
                <div class="comp-attach-current">${preview}</div>
                <div class="comp-attach-actions">
                    <label class="btn btn-nav-outline comp-file-replace">
                        Replace file
                        <input type="file" class="comp-file-input" data-comp-file accept="image/*,.pdf,application/pdf" hidden />
                    </label>
                    <button type="button" class="btn btn-nav-outline" data-comp-remove-file>Remove file</button>
                </div>
                <p class="books-hint comp-file-hint" data-comp-pending-name hidden></p>
            </div>`;
    }

    function renderForm(item, id) {
        const v = M().normalizeItem(item);
        return `
            <form class="dir-form comp-form" data-comp-form data-comp-id="${escapeHtml(id)}"
                data-attachment-url="${escapeHtml(v.attachmentUrl)}"
                data-attachment-name="${escapeHtml(v.attachmentFileName)}"
                data-attachment-type="${escapeHtml(v.attachmentFileType)}">
                <div class="books-grid-2">
                    <label class="books-label">Record type
                        <select class="books-select" name="recordType">${selectOptions(M().RECORD_TYPES, v.recordType)}</select>
                    </label>
                    <label class="books-label">Category
                        <select class="books-select" name="category">${selectOptions(M().CATEGORIES, v.category)}</select>
                    </label>
                    <label class="books-label">Name *
                        <input class="books-input" name="title" required placeholder="e.g. Tobacco retail license" value="${escapeHtml(v.title)}">
                    </label>
                    <label class="books-label">License / ID number
                        <input class="books-input" name="identifier" placeholder="Permit or certificate #" value="${escapeHtml(v.identifier)}">
                    </label>
                    <label class="books-label">Issuing authority
                        <input class="books-input" name="issuingAuthority" placeholder="State, city, agency…" value="${escapeHtml(v.issuingAuthority)}">
                    </label>
                    <label class="books-label">Status
                        <select class="books-select" name="status">${selectOptions(M().STATUSES, v.status)}</select>
                    </label>
                    <label class="books-label">Issue date
                        <input class="books-input" name="issueDate" type="date" value="${escapeHtml(v.issueDate)}">
                    </label>
                    <label class="books-label">Expiry date
                        <input class="books-input" name="expiryDate" type="date" value="${escapeHtml(v.expiryDate)}">
                    </label>
                    <label class="books-label">Renewal due (start renewal by)
                        <input class="books-input" name="renewalDueDate" type="date" value="${escapeHtml(v.renewalDueDate)}">
                    </label>
                    <label class="books-label">Last renewed
                        <input class="books-input" name="lastRenewedDate" type="date" value="${escapeHtml(v.lastRenewedDate)}">
                    </label>
                </div>
                <label class="books-label">Notes
                    <textarea class="books-input dir-textarea" name="notes" rows="3" placeholder="Renewal contacts, filing requirements, fees…">${escapeHtml(v.notes)}</textarea>
                </label>
                ${renderAttachmentBlock(v)}
                <div class="dir-form-actions">
                    <button type="submit" class="btn">Save</button>
                    <button type="button" class="btn btn-nav-outline" data-comp-cancel>Cancel</button>
                    ${id ? `<button type="button" class="btn fac-btn-delete" data-comp-delete>Delete</button>` : ""}
                    <span class="dir-status" data-comp-form-status></span>
                </div>
            </form>`;
    }

    function readForm(form, attachmentFields) {
        const fd = new FormData(form);
        const att = attachmentFields || {};
        return M().normalizeItem({
            active: true,
            recordType: fd.get("recordType"),
            category: fd.get("category"),
            title: fd.get("title"),
            identifier: fd.get("identifier"),
            issuingAuthority: fd.get("issuingAuthority"),
            status: fd.get("status"),
            issueDate: fd.get("issueDate"),
            expiryDate: fd.get("expiryDate"),
            renewalDueDate: fd.get("renewalDueDate"),
            lastRenewedDate: fd.get("lastRenewedDate"),
            notes: fd.get("notes"),
            attachmentUrl: att.attachmentUrl ?? form.dataset.attachmentUrl ?? "",
            attachmentFileName: att.attachmentFileName ?? form.dataset.attachmentName ?? "",
            attachmentFileType: att.attachmentFileType ?? form.dataset.attachmentType ?? "",
        });
    }

    function bindAttachmentControls(form, state) {
        const pendingHint = form.querySelector("[data-comp-pending-name]");
        form.querySelectorAll("[data-comp-file]").forEach((input) => {
            input.addEventListener("change", () => {
                const file = input.files?.[0];
                state.pendingFile = file || null;
                state.removeAttachment = false;
                if (pendingHint) {
                    if (file) {
                        pendingHint.hidden = false;
                        pendingHint.textContent = `Ready to upload: ${file.name}`;
                    } else {
                        pendingHint.hidden = true;
                        pendingHint.textContent = "";
                    }
                }
            });
        });
        form.querySelector("[data-comp-remove-file]")?.addEventListener("click", () => {
            state.pendingFile = null;
            state.removeAttachment = true;
            form.querySelectorAll("[data-comp-file]").forEach((el) => {
                el.value = "";
            });
            const block = form.querySelector("[data-comp-attachment]");
            if (block) {
                block.innerHTML = `
                    <label class="books-label">License / registration file
                        <input type="file" class="comp-file-input" data-comp-file accept="image/*,.pdf,application/pdf" />
                    </label>
                    <p class="books-hint comp-file-hint">File will be removed when you save. Photo or PDF, max 10 MB.</p>`;
                bindAttachmentControls(form, state);
            }
        });
    }

    async function resolveAttachmentOnSave(form, state, docId, existingItem) {
        const prevUrl =
            existingItem?.attachmentUrl || form.dataset.attachmentUrl || "";
        if (state.removeAttachment) {
            if (prevUrl) await Store().deleteAttachment(prevUrl);
            return {
                attachmentUrl: "",
                attachmentFileName: "",
                attachmentFileType: "",
            };
        }
        if (!state.pendingFile) {
            return {
                attachmentUrl: prevUrl,
                attachmentFileName:
                    existingItem?.attachmentFileName || form.dataset.attachmentName || "",
                attachmentFileType:
                    existingItem?.attachmentFileType || form.dataset.attachmentType || "",
            };
        }
        if (prevUrl) await Store().deleteAttachment(prevUrl);
        const url = await Store().uploadAttachment(
            state.userId,
            state.locationId,
            docId,
            state.pendingFile
        );
        return {
            attachmentUrl: url,
            attachmentFileName: state.pendingFile.name,
            attachmentFileType:
                state.pendingFile.type ||
                (state.pendingFile.name.toLowerCase().endsWith(".pdf")
                    ? "application/pdf"
                    : "application/octet-stream"),
        };
    }

    function renderSection(ctx) {
        const items = M().sortItems((ctx.data.complianceItems || []).filter((i) => i.active !== false));
        const attention = M().needsAttentionCount(items);
        const hint =
            attention > 0
                ? `<p class="books-hint dir-hint comp-hint-warn">${attention} registration${attention === 1 ? "" : "s"} need attention — expired, expiring within ${M().EXPIRING_SOON_DAYS} days, or renewal overdue.</p>`
                : `<p class="books-hint dir-hint">Track licenses, registrations, permits, and insurance with expiry dates. Attach a photo or PDF of each license when you add or edit a record.</p>`;

        return `
            <div class="comp-section" data-comp-section>
                <h2 class="loc-section-heading">Compliance</h2>
                <p class="comp-lead">Registrations, licenses & renewals</p>
                ${hint}
                ${renderSummary(items)}
                <div class="dir-toolbar">
                    <button type="button" class="btn" data-comp-add>Add license / registration</button>
                    <span class="dir-status" data-comp-status></span>
                </div>
                <div class="dir-form-slot" data-comp-form-slot hidden></div>
                ${
                    items.length
                        ? renderTable(items)
                        : `<p class="data-list-empty">No licenses or registrations yet. Add your business license, tobacco permit, lottery license, insurance certificates, and other renewals with expiry dates.</p>`
                }
            </div>`;
    }

    function bind(container, ctx) {
        if (!container || container.dataset.compBound) return;
        container.dataset.compBound = "1";

        const slot = container.querySelector("[data-comp-form-slot]");
        const statusEl = container.querySelector("[data-comp-status]");
        let compSaveReady = null;

        function setStatus(msg) {
            if (statusEl) statusEl.textContent = msg || "";
        }

        function closeForm() {
            compSaveReady?.detach();
            compSaveReady = null;
            if (slot) {
                slot.hidden = true;
                slot.innerHTML = "";
            }
        }

        function openForm(item, id) {
            if (!slot) return;
            compSaveReady?.detach();
            const existingItem = id
                ? (ctx.data.complianceItems || []).find((i) => i.id === id)
                : null;
            slot.hidden = false;
            slot.innerHTML = renderForm(existingItem || item, id);
            slot.scrollIntoView({ behavior: "smooth", block: "nearest" });
            const form = slot.querySelector("[data-comp-form]");
            if (window.OplixFormSaveReady) {
                compSaveReady = OplixFormSaveReady.watch(slot, { mode: id ? "edit" : "new" });
            }
            const attachState = {
                userId: ctx.userId,
                locationId: ctx.locationId,
                pendingFile: null,
                removeAttachment: false,
            };
            bindAttachmentControls(form, attachState);

            form?.querySelector("[data-comp-cancel]")?.addEventListener("click", closeForm);
            form?.querySelector("[data-comp-delete]")?.addEventListener("click", async () => {
                if (!id || !confirm("Delete this license / registration record?")) return;
                const st = form.querySelector("[data-comp-form-status]");
                if (st) st.textContent = "Deleting…";
                try {
                    await Store().remove(ctx.userId, ctx.locationId, id, existingItem);
                    closeForm();
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Delete failed.";
                }
            });
            form?.addEventListener("submit", async (e) => {
                e.preventDefault();
                const st = form.querySelector("[data-comp-form-status]");
                if (!String(form.querySelector('[name="title"]')?.value || "").trim()) {
                    if (st) st.textContent = "Name is required.";
                    return;
                }
                if (st) st.textContent = attachState.pendingFile ? "Uploading file…" : "Saving…";
                try {
                    const docId = id || Store().newId();
                    const attachmentFields = await resolveAttachmentOnSave(
                        form,
                        attachState,
                        docId,
                        existingItem
                    );
                    const payload = readForm(form, attachmentFields);
                    if (st) st.textContent = "Saving…";
                    await Store().save(ctx.userId, ctx.locationId, docId, payload);
                    closeForm();
                    setStatus("Saved.");
                    await ctx.onRefresh();
                } catch (err) {
                    if (st) st.textContent = err.message || "Save failed.";
                }
            });
        }

        container.addEventListener("click", (e) => {
            if (e.target.matches("[data-comp-add]")) {
                openForm(M().defaultItem(), "");
                return;
            }
            const editId = e.target.closest("[data-comp-edit]")?.dataset.compEdit;
            if (editId) {
                const item = (ctx.data.complianceItems || []).find((i) => i.id === editId);
                openForm(item || M().defaultItem(), editId);
            }
        });
    }

    window.OplixFacilityCompliance = {
        renderSection,
        bind,
        isComplianceSection(sectionId) {
            return sectionId === "compliance";
        },
    };
})();
