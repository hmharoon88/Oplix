/**
 * Links between Daily books month docs, facility payables, and facility receivables.
 */
(function () {
    const BM = () => window.OplixBooksModel;
    const RM = () => window.OplixReceivablesModel;

    function monthIdFromTimestamp(ts) {
        if (!ts || !RM()) return null;
        const d = RM().toDate(ts);
        if (!d) return null;
        return BM().monthIdFromDate(d);
    }

    function upsertMonthReceivableFromFacility(month, receivable) {
        const monthDoc = month || BM().defaultMonthDoc();
        if (!monthDoc.receivables) monthDoc.receivables = [];
        const linkedId = receivable.id;
        if (!linkedId) return monthDoc;

        const line = {
            id: `mrec_${linkedId}`,
            linkedReceivableId: linkedId,
            description: String(receivable.receiveFrom || "").trim() || "Receivable",
            amount: BM().num(receivable.amount),
        };

        const idx = monthDoc.receivables.findIndex((r) => r.linkedReceivableId === linkedId);
        if (idx >= 0) {
            monthDoc.receivables[idx] = { ...monthDoc.receivables[idx], ...line };
        } else {
            monthDoc.receivables.push(line);
        }
        return monthDoc;
    }

    function removeMonthReceivableLink(month, linkedReceivableId) {
        const monthDoc = month || BM().defaultMonthDoc();
        if (!linkedReceivableId || !monthDoc.receivables) return monthDoc;
        monthDoc.receivables = monthDoc.receivables.filter(
            (r) => r.linkedReceivableId !== linkedReceivableId
        );
        return monthDoc;
    }

    /** Sync facility receivable received state into the month doc that hits Books Net. */
    function syncReceivableToMonthBooks(month, receivable) {
        const monthDoc = { ...(month || BM().defaultMonthDoc()) };
        if (!receivable?.isReceived) {
            return removeMonthReceivableLink(monthDoc, receivable?.id);
        }
        const targetMonthId = monthIdFromTimestamp(receivable.receivedAt);
        if (!targetMonthId) return monthDoc;
        return upsertMonthReceivableFromFacility(monthDoc, receivable);
    }

    function openPayablesForPick(payables) {
        return (payables || []).filter((p) => !p.isPaid);
    }

    function payablePickLabel(p) {
        const amt = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
            parseFloat(p.amount) || 0
        );
        return `${p.payTo || "Payable"} — ${amt}`;
    }

    async function persistReceivableBooksSync(userId, locationId, receivable, preferredMonthId) {
        const Store = window.OplixBooksStore;
        if (!Store || !BM()) return null;
        const monthId = receivable?.isReceived
            ? monthIdFromTimestamp(receivable.receivedAt) ||
              preferredMonthId ||
              BM().monthIdFromDate(new Date())
            : preferredMonthId || BM().monthIdFromDate(new Date());
        const { month } = await Store.loadMonth(userId, locationId, monthId);
        const updated = receivable?.isReceived
            ? syncReceivableToMonthBooks(month, receivable)
            : removeMonthReceivableLink(month, receivable?.id);
        await Store.saveMonth(userId, locationId, monthId, updated);
        window.OplixAnalytics?.invalidateCache?.();
        return { monthId, month: updated };
    }

    window.OplixBooksLinks = {
        monthIdFromTimestamp,
        upsertMonthReceivableFromFacility,
        removeMonthReceivableLink,
        syncReceivableToMonthBooks,
        openPayablesForPick,
        payablePickLabel,
        persistReceivableBooksSync,
    };
})();
