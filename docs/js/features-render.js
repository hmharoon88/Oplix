const CATEGORY_ICONS = {
    "Executive Dashboard": "📊",
    "Sales & Revenue": "💵",
    "Fuel": "⛽",
    "Inventory": "📦",
    "Vendors": "🚚",
    "Expenses": "🧾",
    "Accounting & Financials": "📒",
    "Employees": "👥",
    "Operations": "⚙️",
    "Maintenance": "🔧",
    "Compliance & Audits": "✅",
    "Food Service": "🍽️",
    "Lottery": "🎫",
    "Security & Loss Prevention": "🛡️",
    "Multi-Store": "🏪",
    "Communication System": "💬",
    "Reporting & Analytics": "📈",
    "AI & Automation": "🤖",
    "Mobile Features": "📱",
    "Integrations": "🔗"
};

function renderFeatureSections(rootId) {
    const root = document.getElementById(rootId);
    if (!root) return;

    const grid = document.createElement("div");
    grid.className = "category-cards-grid";
    grid.setAttribute("role", "list");

    FEATURE_SECTIONS.forEach((section) => {
        const icon = CATEGORY_ICONS[section.title] || "◆";
        const card = document.createElement("article");
        card.className = "category-card";
        card.setAttribute("role", "listitem");
        card.innerHTML = `
            <span class="category-card-icon" aria-hidden="true">${icon}</span>
            <h3 class="category-card-title">${section.title}</h3>
        `;
        grid.appendChild(card);
    });

    root.appendChild(grid);
}

function initFeaturesUI(rootId) {
    renderFeatureSections(rootId);
}
