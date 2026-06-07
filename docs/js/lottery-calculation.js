/**
 * Lottery sold/books/dollars and shift summary — mirrors iOS LotteryCalculationService.
 */
(function () {
    function parseCashAmount(amount) {
        if (amount == null || amount === "") return null;
        const clean = String(amount).replace(/\$/g, "").replace(/,/g, "");
        const n = parseFloat(clean);
        return Number.isFinite(n) ? n : null;
    }

    function calculateSoldAndBooks(beginning, ending, tickets, reverseOrder) {
        const ticketsInt = parseInt(tickets, 10) || 0;
        if (ticketsInt <= 0) return { sold: 0, books: 0 };

        const maxTicketNumber = ticketsInt - 1;
        if (!beginning || !ending) return { sold: 0, books: 0 };

        const normalizedBeginning = beginning === "0" ? "00" : beginning;
        const normalizedEnding = ending === "0" ? "00" : ending;

        const beginningIs00 = normalizedBeginning === "00";
        const endingIs00 = normalizedEnding === "00";

        const beginningNum = beginningIs00 ? null : parseInt(normalizedBeginning, 10);
        const endingNum = endingIs00 ? null : parseInt(normalizedEnding, 10);

        if (beginningNum != null && (beginningNum < 1 || beginningNum > maxTicketNumber)) {
            return { sold: 0, books: 0 };
        }
        if (endingNum != null && (endingNum < 1 || endingNum > maxTicketNumber)) {
            return { sold: 0, books: 0 };
        }

        if (
            (beginningIs00 && endingIs00) ||
            (beginningNum != null && endingNum != null && beginningNum === endingNum)
        ) {
            return { sold: 0, books: 0 };
        }

        function getPosition(is00, num, reverse) {
            if (is00) return reverse ? 0 : -1;
            return num ?? 0;
        }

        const beginPos = getPosition(beginningIs00, beginningNum, reverseOrder);
        const endPos = getPosition(endingIs00, endingNum, reverseOrder);

        if (reverseOrder) {
            if (beginPos > endPos) {
                let sold;
                if (beginningIs00) return { sold: 0, books: 0 };
                if (endingIs00) sold = beginningNum;
                else sold = beginningNum - endingNum;
                return { sold, books: 0 };
            }
            let sold;
            if (beginningIs00) sold = 1 + (maxTicketNumber - endingNum);
            else if (endingIs00) sold = beginningNum + 1;
            else sold = beginningNum + (maxTicketNumber - endingNum) + 1;
            return { sold, books: 1 };
        }

        if (beginPos < endPos) {
            let sold;
            if (beginningIs00) sold = endingNum;
            else if (endingIs00) return { sold: 0, books: 0 };
            else sold = endingNum - beginningNum;
            return { sold, books: 0 };
        }
        let sold;
        if (beginningIs00) sold = endingNum;
        else if (endingIs00) sold = maxTicketNumber - beginningNum + 1;
        else sold = maxTicketNumber - beginningNum + endingNum + 1;
        return { sold, books: 1 };
    }

    function calculateDollars(sold, value) {
        const cleanValue = String(value || "").replace(/\$/g, "");
        const valueInt = parseInt(cleanValue, 10) || 0;
        return sold * valueInt;
    }

    function calculateTemplateTotals(rows, reverseOrder) {
        let totalSold = 0;
        let totalDollars = 0;
        let totalBooks = 0;

        for (const row of rows || []) {
            const hasBeginningOrEnding = row.beginningNumber || row.endingNumber;
            const hasTickets = row.tickets;
            const hasValue = row.value;
            if (!hasBeginningOrEnding && !(hasTickets && hasValue)) continue;
            if (!row.beginningNumber || !row.endingNumber || !row.tickets || !row.value) continue;

            const normalizedBeginning = row.beginningNumber === "0" ? "00" : row.beginningNumber;
            const normalizedEnding = row.endingNumber === "0" ? "00" : row.endingNumber;

            const { sold, books } = calculateSoldAndBooks(
                normalizedBeginning,
                normalizedEnding,
                row.tickets,
                reverseOrder
            );
            const dollars = calculateDollars(sold, row.value);

            totalSold += sold;
            totalDollars += dollars;
            totalBooks += books;
        }

        return { totalSold, totalDollars, totalBooks };
    }

    function calculateShiftSummary(templateTotals, onlineTotal, onlineCashes, instantCashes, registerCash) {
        const instantTotal = templateTotals.totalDollars;
        const onlineTotalValue = onlineTotal ?? 0;
        const totalSoldAmount = instantTotal + onlineTotalValue;
        const registerCashValue = parseCashAmount(registerCash) ?? 0;
        const totalCash = totalSoldAmount + registerCashValue;

        const onlineCashesTotal = (onlineCashes || [])
            .map(parseCashAmount)
            .filter((n) => n != null)
            .reduce((s, n) => s + n, 0);
        const instantCashesTotal = (instantCashes || [])
            .map(parseCashAmount)
            .filter((n) => n != null)
            .reduce((s, n) => s + n, 0);
        const totalCashes = onlineCashesTotal + instantCashesTotal;
        const cashInBag = totalCash - totalCashes;
        const cashInBagNet = cashInBag - registerCashValue;

        return {
            totalSold: templateTotals.totalSold,
            totalDollars: templateTotals.totalDollars,
            totalBooks: templateTotals.totalBooks,
            instantTotal,
            onlineTotal: onlineTotalValue,
            totalSoldAmount,
            registerCash: registerCashValue,
            totalCash,
            onlineCashes: onlineCashesTotal,
            instantCashes: instantCashesTotal,
            totalCashes,
            cashInBag,
            cashInBagNet,
        };
    }

    function rowCalculated(row, reverseOrder) {
        if (!row.beginningNumber || !row.endingNumber || !row.tickets) {
            return { sold: 0, dollars: 0, books: 0 };
        }
        const { sold, books } = calculateSoldAndBooks(
            row.beginningNumber === "0" ? "00" : row.beginningNumber,
            row.endingNumber === "0" ? "00" : row.endingNumber,
            row.tickets,
            reverseOrder
        );
        const dollars = row.value ? calculateDollars(sold, row.value) : 0;
        return { sold, dollars, books };
    }

    window.OplixLotteryCalc = {
        parseCashAmount,
        calculateSoldAndBooks,
        calculateDollars,
        calculateTemplateTotals,
        calculateShiftSummary,
        rowCalculated,
    };
})();
