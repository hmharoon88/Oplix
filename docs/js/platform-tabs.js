function initPlatformTabs() {
    const tabsRoot = document.getElementById("platform-tabs");
    const panelRoot = document.getElementById("platform-panel");
    if (!tabsRoot || !panelRoot || typeof PLATFORM_MODULES === "undefined") return;

    PLATFORM_MODULES.forEach((module, index) => {
        const tab = document.createElement("button");
        tab.type = "button";
        tab.className = "platform-tab" + (index === 0 ? " active" : "");
        tab.textContent = module.tab;
        tab.setAttribute("aria-selected", index === 0 ? "true" : "false");
        tab.dataset.moduleId = module.id;
        tab.addEventListener("click", () => selectModule(module.id));
        tabsRoot.appendChild(tab);
    });

    selectModule(PLATFORM_MODULES[0].id);
}

function selectModule(moduleId) {
    const module = PLATFORM_MODULES.find((m) => m.id === moduleId);
    if (!module) return;

    document.querySelectorAll(".platform-tab").forEach((tab) => {
        const isActive = tab.dataset.moduleId === moduleId;
        tab.classList.toggle("active", isActive);
        tab.setAttribute("aria-selected", isActive ? "true" : "false");
    });

    const panel = document.getElementById("platform-panel");
    panel.innerHTML = `
        <div class="platform-panel-inner">
            <div class="platform-panel-copy">
                <span class="platform-panel-icon" aria-hidden="true">${module.icon}</span>
                <h3>${module.title}</h3>
                <p>${module.description}</p>
                <ul>
                    ${module.bullets.map((b) => `<li>${b}</li>`).join("")}
                </ul>
            </div>
            <div class="platform-panel-visual" aria-hidden="true">
                <div class="mock-screen">
                    <div class="mock-screen-bar"></div>
                    <div class="mock-screen-body">
                        <div class="mock-line wide"></div>
                        <div class="mock-line"></div>
                        <div class="mock-line"></div>
                        <div class="mock-card-row">
                            <div class="mock-card"></div>
                            <div class="mock-card"></div>
                        </div>
                        <div class="mock-line short"></div>
                    </div>
                </div>
            </div>
        </div>
    `;
}

function initHowItWorks() {
    const root = document.getElementById("how-it-works");
    if (!root || typeof HOW_IT_WORKS === "undefined") return;

    root.innerHTML = HOW_IT_WORKS.map(
        (item) => `
        <article class="step-card">
            <span class="step-number">${item.step}</span>
            <p class="step-label">${item.title}</p>
            <h3>${item.headline}</h3>
            <ul>
                ${item.points.map((p) => `<li>${p}</li>`).join("")}
            </ul>
        </article>
    `
    ).join("");
}

document.addEventListener("DOMContentLoaded", () => {
    initPlatformTabs();
    initHowItWorks();
});
