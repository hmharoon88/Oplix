/**
 * Shared compare / trend legend copy for Books summary, Reports, and Home.
 */
(function () {
    const MODES = {
        day: {
            html: 'Trends compare each row to the <strong>previous calendar day</strong> (▲/▼ amount; hover for %).',
            title: "vs previous day",
        },
        month: {
            html: 'Trends compare to the <strong>previous month</strong> (▲/▼ amount; hover for %).',
            title: "vs previous month",
        },
        mtd: {
            html: 'Trends compare month-to-date to the <strong>same calendar days in the prior month</strong> (▲/▼ %).',
            title: "vs same days prior month",
        },
    };

    function legendHtml(mode) {
        const m = MODES[mode] || MODES.month;
        return `<p class="books-trend-legend">${m.html}</p>`;
    }

    function compareTitle(mode) {
        const m = MODES[mode] || MODES.month;
        return m.title;
    }

    window.OplixBooksTrendLegend = {
        legendHtml,
        compareTitle,
    };
})();
