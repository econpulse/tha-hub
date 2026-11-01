// ============================================================================
// LUKB Investment Office Hub (v2) – Public Zero-Server JS
// ============================================================================
// Steuert die Tab-Umschaltung der 3 Sektionen sowie optionale Länderfilter
// komplett im Browser ohne Server-Abhängigkeit.
// ============================================================================

document.addEventListener("DOMContentLoaded", function () {
  const tabTriggers = document.querySelectorAll("[data-pub-tab]");
  const tabPanes = document.querySelectorAll(".pub-tab-pane");

  function activateTab(tabKey) {
    tabTriggers.forEach((btn) => {
      if (btn.getAttribute("data-pub-tab") === tabKey) {
        btn.classList.add("active");
      } else {
        btn.classList.remove("active");
      }
    });

    tabPanes.forEach((pane) => {
      if (pane.getAttribute("data-pane-key") === tabKey) {
        pane.style.display = "block";
      } else {
        pane.style.display = "none";
      }
    });
  }

  tabTriggers.forEach((btn) => {
    btn.addEventListener("click", function (e) {
      e.preventDefault();
      const targetKey = this.getAttribute("data-pub-tab");
      activateTab(targetKey);
    });
  });

  // Initial: Sektion 01 (Zentralbankprognosen) aktivieren
  activateTab("cb");
});
