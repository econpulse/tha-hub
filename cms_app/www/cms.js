// ============================================================================
// LUKB Investment Office Hub (v2) – High-Reactivity Client-Side Engine
// ============================================================================
// Features:
// - Unterstützt Zins-Spannen bei Zentralbanken (z.B. "3.75-4%" oder "4.25 - 4.50")
//   und berechnet Veränderungen automatisch anhand des Mittelwerts (Trennzeichen
//   "-" oder " - ").
// - Tab-basierte Darstellung der Sektionen.
// - Jede Sektion besitzt sowohl einen Gesamtkommentar als auch einen Kommentar
//   pro Zeile. Wenn in einer Sektion kein einziger Zeilenkommentar ausgefüllt
//   ist, wird die Kommentarspalte in der Public-Ansicht automatisch ausgeblendet.
// ============================================================================

(function () {
  let state = null;
  let viewMode = "edit"; // 'edit' | 'preview'
  let activeFilter = "cb"; // 'cb' | 'macro' | 'alloc' | 'json'
  let isDirty = false;

  const STANCE_LABELS = {
    "-2": "Stark untergewichtet",
    "-1": "Untergewichtet",
    "0":  "Neutral",
    "1":  "Übergewichtet",
    "2":  "Stark übergewichtet"
  };

  const CHANGE_LABELS = {
    "-1": "↓ Abgestuft",
    "0":  "→ Unverändert",
    "1":  "↑ Hochgestuft"
  };

  function markDirty(flag) {
    isDirty = flag;
    const dot = document.getElementById("sync-dot");
    const txt = document.getElementById("sync-text");
    if (!dot || !txt) return;
    if (isDirty) {
      dot.classList.add("dirty");
      txt.textContent = "Ungespeicherte Änderungen";
    } else {
      dot.classList.remove("dirty");
      const ver = state && state.meta && state.meta.version ? `v${state.meta.version}` : "";
      txt.textContent = `Gespeichert ${ver}`;
    }
  }

  function showToast(msg, isError = false) {
    const t = document.getElementById("cms-toast");
    if (!t) return;
    t.textContent = msg;
    t.style.borderLeftColor = isError ? "#EF4444" : "#C59B27";
    t.classList.add("visible");
    clearTimeout(window.__toastTimer);
    window.__toastTimer = setTimeout(() => t.classList.remove("visible"), 3600);
  }

  /**
   * Parst Einzelwerte oder Spannen (z.B. "3.75-4%", "4.25 - 4.50", "-0.25")
   * und gibt { mid: Number|null, isRange: Boolean, n1: Number, n2: Number } zurück.
   */
  function parseRateInfo(raw) {
    if (raw === null || raw === undefined) return { mid: null, isRange: false };
    if (typeof raw === "number") {
      return isNaN(raw) ? { mid: null, isRange: false } : { mid: raw, isRange: false };
    }
    const clean = String(raw).replace(/%/g, "").replace(/,/g, ".").trim();
    if (!clean) return { mid: null, isRange: false };

    // Prüfe auf Spanne: Zahl1 gefolgt von "-" oder " - " und Zahl2
    const rangeMatch = clean.match(/^([+-]?\d+(?:\.\d+)?)\s*-\s*([+-]?\d+(?:\.\d+)?)$/);
    if (rangeMatch) {
      const n1 = parseFloat(rangeMatch[1]);
      const n2 = parseFloat(rangeMatch[2]);
      if (!isNaN(n1) && !isNaN(n2)) {
        return { mid: (n1 + n2) / 2.0, isRange: true, n1: n1, n2: n2 };
      }
    }

    const single = parseFloat(clean);
    if (!isNaN(single)) {
      return { mid: single, isRange: false };
    }
    return { mid: null, isRange: false };
  }

  function formatRateDisplay(raw, digits = 2) {
    const info = parseRateInfo(raw);
    if (info.mid === null) return "–";
    if (info.isRange) {
      return `${info.n1.toFixed(digits)}–${info.n2.toFixed(digits)} %`;
    }
    return `${info.mid.toFixed(digits)} %`;
  }

  function formatBpDelta(currRaw, targetRaw) {
    const cInfo = parseRateInfo(currRaw);
    const tInfo = parseRateInfo(targetRaw);
    if (cInfo.mid === null || tInfo.mid === null) return { text: "–", cls: "delta-flat" };
    const bp = Math.round((tInfo.mid - cInfo.mid) * 100);
    if (bp > 0) return { text: `+${bp} Bp.`, cls: "delta-pos" };
    if (bp < 0) return { text: `${bp} Bp.`, cls: "delta-neg" };
    return { text: "0 Bp.", cls: "delta-flat" };
  }

  function formatNum(val, digits = 2) {
    const n = parseFloat(val);
    if (isNaN(n)) return "–";
    return n.toFixed(digits);
  }

  function hasAnyRowComment(rows) {
    if (!Array.isArray(rows)) return false;
    return rows.some((r) => r && typeof r.comment === "string" && r.comment.trim().length > 0);
  }

  function escapeAttr(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  // --------------------------------------------------------------------------
  // RENDERING DER 3 KERNBEREICHE (Zero-Latency DOM)
  // --------------------------------------------------------------------------

  function renderAll() {
    if (!state) return;

    const dateInput = document.getElementById("meta-committee-date");
    if (dateInput && state.meta) {
      dateInput.value = state.meta.committee_date || "";
      dateInput.disabled = viewMode === "preview";
    }
    const dbBadge = document.getElementById("meta-db-badge");
    if (dbBadge && state.meta) {
      dbBadge.textContent = state.meta.db_mode === "mssql" ? "MS SQL Server" : "SQLite (Local)";
    }
    const userBadge = document.getElementById("meta-user-badge");
    if (userBadge && state.meta) {
      userBadge.textContent = state.meta.updated_by || "Redakteur";
    }

    renderCentralBanks();
    renderMacro();
    renderAllocation();
    updateJsonInspector();
    applySectionVisibility();
  }

  // 1. ZENTRALBANKPROGNOSEN (inkl. Spannen-Parser & Zeilenkommentare)
  function renderCentralBanks() {
    const container = document.getElementById("sec-cb-content");
    if (!container || !state.central_banks) return;

    const rows = state.central_banks.rows || [];
    const isEdit = viewMode === "edit";
    const showCommentCol = isEdit || hasAnyRowComment(rows);

    let tbodyHtml = rows
      .map((r, idx) => {
        const d3 = formatBpDelta(r.current, r.m3);
        const d12 = formatBpDelta(r.current, r.m12);
        const cInfo = parseRateInfo(r.current);
        const m3Info = parseRateInfo(r.m3);
        const m12Info = parseRateInfo(r.m12);

        if (isEdit) {
          return `
            <tr>
              <td>
                <span class="code-pill">${r.currency}</span>
                <strong>${r.name}</strong>
                <span style="color:var(--ink-muted); font-size:0.78rem; margin-left:0.4rem;">${r.full_name || ""}</span>
              </td>
              <td class="num">
                <input type="text" class="cell-input-rate cb-input" data-idx="${idx}" data-field="current" value="${escapeAttr(r.current)}" placeholder="z.B. 3.75-4.00" />
                <span id="cb-mid-current-${idx}" class="midpoint-hint">${cInfo.isRange ? `Ø ${cInfo.mid.toFixed(3)} %` : ""}</span>
              </td>
              <td class="num">
                <input type="text" class="cell-input-rate cb-input" data-idx="${idx}" data-field="m3" value="${escapeAttr(r.m3)}" placeholder="z.B. 3.50-3.75" />
                <span id="cb-mid-m3-${idx}" class="midpoint-hint">${m3Info.isRange ? `Ø ${m3Info.mid.toFixed(3)} %` : ""}</span>
              </td>
              <td class="num">
                <span id="cb-d3-${idx}" class="delta-pill ${d3.cls}">${d3.text}</span>
              </td>
              <td class="num">
                <input type="text" class="cell-input-rate cb-input" data-idx="${idx}" data-field="m12" value="${escapeAttr(r.m12)}" placeholder="z.B. 3.25-3.50" />
                <span id="cb-mid-m12-${idx}" class="midpoint-hint">${m12Info.isRange ? `Ø ${m12Info.mid.toFixed(3)} %` : ""}</span>
              </td>
              <td class="num">
                <span id="cb-d12-${idx}" class="delta-pill ${d12.cls}">${d12.text}</span>
              </td>
              <td>
                <input type="text" class="cell-input-text cb-comm-input" data-idx="${idx}" value="${escapeAttr(r.comment || "")}" placeholder="Optionaler Zeilenkommentar..." />
              </td>
            </tr>
          `;
        } else {
          return `
            <tr>
              <td>
                <span class="code-pill">${r.currency}</span>
                <strong>${r.name}</strong>
                <span style="color:var(--ink-muted); font-size:0.78rem; margin-left:0.4rem;">${r.full_name || ""}</span>
              </td>
              <td class="num" style="font-family:var(--font-mono); font-weight:600;">${formatRateDisplay(r.current, 2)}</td>
              <td class="num" style="font-family:var(--font-mono); font-weight:600;">${formatRateDisplay(r.m3, 2)}</td>
              <td class="num"><span class="delta-pill ${d3.cls}">${d3.text}</span></td>
              <td class="num" style="font-family:var(--font-mono); font-weight:700; color:var(--lukb-navy);">${formatRateDisplay(r.m12, 2)}</td>
              <td class="num"><span class="delta-pill ${d12.cls}">${d12.text}</span></td>
              ${showCommentCol ? `<td style="color:var(--ink-secondary);">${escapeAttr(r.comment || "")}</td>` : ""}
            </tr>
          `;
        }
      })
      .join("");

    const commentBlock = isEdit
      ? `<textarea id="cb-commentary-input" class="commentary-textarea" rows="3" placeholder="Übergreifende Einschätzung des Ökonomen zur Geldpolitik...">${state.central_banks.commentary || ""}</textarea>`
      : `<p class="commentary-readonly">${state.central_banks.commentary || ""}</p>`;

    container.innerHTML = `
      <div class="data-grid-wrap">
        <table class="editorial-table">
          <thead>
            <tr>
              <th style="width:26%;">Zentralbank / Referenzsatz</th>
              <th class="num" style="width:12%;">Aktuell (%)</th>
              <th class="num" style="width:12%;">In 3M (%)</th>
              <th class="num" style="width:10%;">Δ 3M (Bp.)</th>
              <th class="num" style="width:12%;">In 12M (%)</th>
              <th class="num" style="width:10%;">Δ 12M (Bp.)</th>
              ${showCommentCol ? `<th style="width:18%;">Kommentar (Zeile)</th>` : ""}
            </tr>
          </thead>
          <tbody>${tbodyHtml}</tbody>
        </table>
      </div>
      <div class="commentary-box">
        <div class="commentary-label">
          <span>Gesamtkommentar Geldpolitik & Zentralbanken</span>
          <span>Tipp: Zinsbänder wie „3.75-4%“ oder „4.25 - 4.50“ werden automatisch über den Mittelwert in Bp. umgerechnet</span>
        </div>
        ${commentBlock}
      </div>
    `;

    if (isEdit) {
      container.querySelectorAll(".cb-input").forEach((inp) => {
        inp.addEventListener("input", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          const f = this.getAttribute("data-field");
          state.central_banks.rows[i][f] = this.value;

          const row = state.central_banks.rows[i];
          const fInfo = parseRateInfo(this.value);
          const midEl = document.getElementById(`cb-mid-${f}-${i}`);
          if (midEl) {
            midEl.textContent = fInfo.isRange ? `Ø ${fInfo.mid.toFixed(3)} %` : "";
          }

          const d3 = formatBpDelta(row.current, row.m3);
          const d12 = formatBpDelta(row.current, row.m12);
          const el3 = document.getElementById(`cb-d3-${i}`);
          const el12 = document.getElementById(`cb-d12-${i}`);
          if (el3) { el3.textContent = d3.text; el3.className = `delta-pill ${d3.cls}`; }
          if (el12) { el12.textContent = d12.text; el12.className = `delta-pill ${d12.cls}`; }

          markDirty(true);
          updateJsonInspector();
        });
      });

      container.querySelectorAll(".cb-comm-input").forEach((inp) => {
        inp.addEventListener("input", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          state.central_banks.rows[i].comment = this.value;
          markDirty(true);
          updateJsonInspector();
        });
      });

      const commInp = document.getElementById("cb-commentary-input");
      if (commInp) {
        commInp.addEventListener("input", function () {
          state.central_banks.commentary = this.value;
          markDirty(true);
          updateJsonInspector();
        });
      }
    }
  }

  // 2. MAKROPROGNOSEN (Wachstum & Inflation für t-1, t, t+1 + optionale Zeilenkommentare)
  function renderMacro() {
    const container = document.getElementById("sec-macro-content");
    const yearSlot = document.getElementById("macro-year-control");
    if (!container || !state.macro) return;

    const baseYear = parseInt(state.macro.base_year, 10) || new Date().getFullYear();
    const yPrev = baseYear - 1;
    const yCurr = baseYear;
    const yNext = baseYear + 1;
    const isEdit = viewMode === "edit";
    const rows = state.macro.rows || [];
    const showCommentCol = isEdit || hasAnyRowComment(rows);

    if (yearSlot) {
      if (isEdit) {
        const yearOpts = [baseYear - 1, baseYear, baseYear + 1]
          .map((y) => `<option value="${y}" ${y === baseYear ? "selected" : ""}>${y} (Jahr t)</option>`)
          .join("");
        yearSlot.innerHTML = `
          <div class="year-selector-box">
            <span>Prognose-Basisjahr (t):</span>
            <select id="macro-base-year-select">${yearOpts}</select>
            <span style="font-family:var(--font-mono); font-size:0.74rem; color:#785A0A;">
              [t-1 = ${yPrev} | t = ${yCurr}E | t+1 = ${yNext}E]
            </span>
          </div>
        `;
        const sel = document.getElementById("macro-base-year-select");
        if (sel) {
          sel.addEventListener("change", function () {
            state.macro.base_year = parseInt(this.value, 10);
            markDirty(true);
            renderMacro();
            updateJsonInspector();
          });
        }
      } else {
        yearSlot.innerHTML = `
          <div class="year-selector-box">
            <span>Horizont: <strong>${yPrev} (t-1)</strong> · <strong>${yCurr}E (t)</strong> · <strong>${yNext}E (t+1)</strong></span>
          </div>
        `;
      }
    }

    let tbodyHtml = rows
      .map((r, idx) => {
        if (isEdit) {
          return `
            <tr>
              <td>
                <span class="code-pill">${r.code}</span>
                <strong>${r.country}</strong>
              </td>
              <td class="num" style="border-left:1px solid var(--line-hairline);">
                <input type="number" step="0.1" class="cell-input-num macro-input" data-idx="${idx}" data-field="gdp_t_minus_1" value="${r.gdp_t_minus_1}" />
              </td>
              <td class="num" style="background:#FAF9F5;">
                <input type="number" step="0.1" class="cell-input-num macro-input" data-idx="${idx}" data-field="gdp_t" value="${r.gdp_t}" />
              </td>
              <td class="num">
                <input type="number" step="0.1" class="cell-input-num macro-input" data-idx="${idx}" data-field="gdp_t_plus_1" value="${r.gdp_t_plus_1}" />
              </td>
              <td class="num" style="border-left:1px solid var(--line-strong);">
                <input type="number" step="0.1" class="cell-input-num macro-input" data-idx="${idx}" data-field="cpi_t_minus_1" value="${r.cpi_t_minus_1}" />
              </td>
              <td class="num" style="background:#FAF9F5;">
                <input type="number" step="0.1" class="cell-input-num macro-input" data-idx="${idx}" data-field="cpi_t" value="${r.cpi_t}" />
              </td>
              <td class="num">
                <input type="number" step="0.1" class="cell-input-num macro-input" data-idx="${idx}" data-field="cpi_t_plus_1" value="${r.cpi_t_plus_1}" />
              </td>
              <td style="border-left:1px solid var(--line-strong);">
                <input type="text" class="cell-input-text macro-comm-input" data-idx="${idx}" value="${escapeAttr(r.comment || "")}" placeholder="Optionaler Länderkommentar..." />
              </td>
            </tr>
          `;
        } else {
          return `
            <tr>
              <td>
                <span class="code-pill">${r.code}</span>
                <strong>${r.country}</strong>
              </td>
              <td class="num" style="border-left:1px solid var(--line-hairline); font-family:var(--font-mono); color:var(--ink-secondary);">${formatNum(r.gdp_t_minus_1, 1)} %</td>
              <td class="num" style="background:#FAF9F5; font-family:var(--font-mono); font-weight:700; color:var(--lukb-navy);">${formatNum(r.gdp_t, 1)} %</td>
              <td class="num" style="font-family:var(--font-mono); font-weight:600;">${formatNum(r.gdp_t_plus_1, 1)} %</td>
              <td class="num" style="border-left:1px solid var(--line-strong); font-family:var(--font-mono); color:var(--ink-secondary);">${formatNum(r.cpi_t_minus_1, 1)} %</td>
              <td class="num" style="background:#FAF9F5; font-family:var(--font-mono); font-weight:700; color:var(--lukb-navy);">${formatNum(r.cpi_t, 1)} %</td>
              <td class="num" style="font-family:var(--font-mono); font-weight:600;">${formatNum(r.cpi_t_plus_1, 1)} %</td>
              ${showCommentCol ? `<td style="border-left:1px solid var(--line-strong); color:var(--ink-secondary);">${escapeAttr(r.comment || "")}</td>` : ""}
            </tr>
          `;
        }
      })
      .join("");

    const commentBlock = isEdit
      ? `<textarea id="macro-commentary-input" class="commentary-textarea" rows="3" placeholder="Übergreifender Kommentar zu Konjunktur & Inflation...">${state.macro.commentary || ""}</textarea>`
      : `<p class="commentary-readonly">${state.macro.commentary || ""}</p>`;

    container.innerHTML = `
      <div class="data-grid-wrap">
        <table class="editorial-table">
          <thead>
            <tr>
              <th rowspan="2" style="width:18%; vertical-align:bottom;">Land / Wirtschaftsraum</th>
              <th colspan="3" class="group-header">Reales BIP-Wachstum (J/J in %)</th>
              <th colspan="3" class="group-header">Inflation / Konsumentenpreise (J/J in %)</th>
              ${showCommentCol ? `<th rowspan="2" style="width:22%; vertical-align:bottom; border-left:1px solid var(--line-strong);">Kommentar (Zeile)</th>` : ""}
            </tr>
            <tr>
              <th class="num" style="border-left:1px solid var(--line-hairline);">${yPrev} <span style="font-weight:400; color:var(--ink-muted);">(t-1)</span></th>
              <th class="num" style="background:#EFECE4; color:var(--lukb-navy);">${yCurr}E <span style="font-weight:400;">(t)</span></th>
              <th class="num">${yNext}E <span style="font-weight:400; color:var(--ink-muted);">(t+1)</span></th>
              <th class="num" style="border-left:1px solid var(--line-strong);">${yPrev} <span style="font-weight:400; color:var(--ink-muted);">(t-1)</span></th>
              <th class="num" style="background:#EFECE4; color:var(--lukb-navy);">${yCurr}E <span style="font-weight:400;">(t)</span></th>
              <th class="num">${yNext}E <span style="font-weight:400; color:var(--ink-muted);">(t+1)</span></th>
            </tr>
          </thead>
          <tbody>${tbodyHtml}</tbody>
        </table>
      </div>
      <div class="commentary-box">
        <div class="commentary-label">
          <span>Gesamtkommentar Makroökonomie</span>
          <span>Basisjahr t = ${yCurr} · Wenn alle Zeilenkommentare leer sind, wird die Kommentarspalte in der Public-Ansicht ausgeblendet</span>
        </div>
        ${commentBlock}
      </div>
    `;

    if (isEdit) {
      container.querySelectorAll(".macro-input").forEach((inp) => {
        inp.addEventListener("input", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          const f = this.getAttribute("data-field");
          const val = parseFloat(this.value);
          state.macro.rows[i][f] = isNaN(val) ? 0 : val;
          markDirty(true);
          updateJsonInspector();
        });
      });

      container.querySelectorAll(".macro-comm-input").forEach((inp) => {
        inp.addEventListener("input", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          state.macro.rows[i].comment = this.value;
          markDirty(true);
          updateJsonInspector();
        });
      });

      const commInp = document.getElementById("macro-commentary-input");
      if (commInp) {
        commInp.addEventListener("input", function () {
          state.macro.commentary = this.value;
          markDirty(true);
          updateJsonInspector();
        });
      }
    }
  }

  // 3. ALLOKATIONSTABELLE MIT PROGNOSEN
  function renderAllocation() {
    const container = document.getElementById("sec-alloc-content");
    if (!container || !state.allocation) return;

    const rows = state.allocation.rows || [];
    const isEdit = viewMode === "edit";
    const showCommentCol = isEdit || hasAnyRowComment(rows);

    let tbodyHtml = rows
      .map((r, idx) => {
        const stanceKey = String(r.stance);
        const stanceText = STANCE_LABELS[stanceKey] || "Neutral";
        const chgKey = String(r.change);
        const chgText = CHANGE_LABELS[chgKey] || "→ Unverändert";

        if (isEdit) {
          const stepBtns = [-2, -1, 0, 1, 2]
            .map((v) => {
              const lbl = v === -2 ? "--" : v === -1 ? "-" : v === 0 ? "N" : v === 1 ? "+" : "++";
              const act = parseInt(r.stance, 10) === v ? "active" : "";
              return `<button type="button" class="stance-step-btn ${act}" data-idx="${idx}" data-val="${v}" title="${STANCE_LABELS[String(v)]}">${lbl}</button>`;
            })
            .join("");

          const chgBtns = [-1, 0, 1]
            .map((c) => {
              const sym = c === -1 ? "↓" : c === 0 ? "→" : "↑";
              const act = parseInt(r.change, 10) === c ? "active" : "";
              return `<button type="button" class="change-btn ${act}" data-idx="${idx}" data-chg="${c}">${sym}</button>`;
            })
            .join("");

          return `
            <tr>
              <td><strong>${r.asset_class}</strong></td>
              <td>
                <div style="display:flex; align-items:center;">
                  <div class="stance-selector">${stepBtns}</div>
                  <span id="stance-lbl-${idx}" class="stance-label-readout">${stanceText}</span>
                </div>
              </td>
              <td>
                <div class="change-selector">${chgBtns}</div>
              </td>
              <td class="num">
                <input type="number" step="0.1" class="cell-input-num alloc-fc-input" data-idx="${idx}" value="${r.forecast_12m}" />
              </td>
              <td>
                <input type="text" class="cell-input-text alloc-comm-input" data-idx="${idx}" value="${escapeAttr(r.comment || "")}" placeholder="Optionaler Zeilenkommentar..." />
              </td>
            </tr>
          `;
        } else {
          const fcVal = parseFloat(r.forecast_12m);
          const fcCls = fcVal > 0 ? "delta-pos" : fcVal < 0 ? "delta-neg" : "delta-flat";
          const fcStr = (fcVal > 0 ? "+" : "") + formatNum(fcVal, 1) + " %";

          const stepDots = [-2, -1, 0, 1, 2]
            .map((v) => {
              const isAct = parseInt(r.stance, 10) === v;
              const bg = !isAct
                ? "#CBD5E1"
                : v === -2
                ? "#B91C1C"
                : v === -1
                ? "#D97706"
                : v === 0
                ? "#475569"
                : v === 1
                ? "#0066B3"
                : "#003366";
              const size = isAct ? "12px" : "8px";
              return `<span style="display:inline-block; width:${size}; height:${size}; border-radius:50%; background:${bg}; margin:0 3px;"></span>`;
            })
            .join("");

          return `
            <tr>
              <td><strong>${r.asset_class}</strong></td>
              <td>
                <div style="display:flex; align-items:center; gap:0.65rem;">
                  <div style="display:inline-flex; align-items:center; background:var(--bg-subtle); padding:4px 8px; border-radius:999px;">${stepDots}</div>
                  <span style="font-weight:600; font-size:0.8rem;">${stanceText}</span>
                </div>
              </td>
              <td style="font-weight:600; font-size:0.8rem; color:var(--ink-secondary);">${chgText}</td>
              <td class="num"><span class="delta-pill ${fcCls}">${fcStr}</span></td>
              ${showCommentCol ? `<td style="color:var(--ink-secondary);">${escapeAttr(r.comment || "")}</td>` : ""}
            </tr>
          `;
        }
      })
      .join("");

    const commentBlock = isEdit
      ? `<textarea id="alloc-commentary-input" class="commentary-textarea" rows="2" placeholder="Übergreifender Kommentar zur taktischen Allokation...">${state.allocation.commentary || ""}</textarea>`
      : `<p class="commentary-readonly">${state.allocation.commentary || ""}</p>`;

    container.innerHTML = `
      <div class="data-grid-wrap">
        <table class="editorial-table">
          <thead>
            <tr>
              <th style="width:16%;">Haupt-Assetklasse</th>
              <th style="width:32%;">Aktuelle Empfehlung (-- / - / N / + / ++)</th>
              <th style="width:13%;">Veränderung</th>
              <th class="num" style="width:13%;">Prognose 12M (%)</th>
              ${showCommentCol ? `<th style="width:26%;">Kommentar (Zeile)</th>` : ""}
            </tr>
          </thead>
          <tbody>${tbodyHtml}</tbody>
        </table>
      </div>
      <div class="commentary-box">
        <div class="commentary-label">
          <span>Gesamtkommentar Anlagepolitik</span>
          <span>Cash · Obligationen · Aktien · Immobilien · Gold · Rohstoffe</span>
        </div>
        ${commentBlock}
      </div>
    `;

    if (isEdit) {
      container.querySelectorAll(".stance-step-btn").forEach((btn) => {
        btn.addEventListener("click", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          const v = parseInt(this.getAttribute("data-val"), 10);
          state.allocation.rows[i].stance = v;
          markDirty(true);
          renderAllocation();
          updateJsonInspector();
        });
      });

      container.querySelectorAll(".change-btn").forEach((btn) => {
        btn.addEventListener("click", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          const c = parseInt(this.getAttribute("data-chg"), 10);
          state.allocation.rows[i].change = c;
          markDirty(true);
          renderAllocation();
          updateJsonInspector();
        });
      });

      container.querySelectorAll(".alloc-fc-input").forEach((inp) => {
        inp.addEventListener("input", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          const val = parseFloat(this.value);
          state.allocation.rows[i].forecast_12m = isNaN(val) ? 0 : val;
          markDirty(true);
          updateJsonInspector();
        });
      });

      container.querySelectorAll(".alloc-comm-input").forEach((inp) => {
        inp.addEventListener("input", function () {
          const i = parseInt(this.getAttribute("data-idx"), 10);
          state.allocation.rows[i].comment = this.value;
          markDirty(true);
          updateJsonInspector();
        });
      });

      const commInp = document.getElementById("alloc-commentary-input");
      if (commInp) {
        commInp.addEventListener("input", function () {
          state.allocation.commentary = this.value;
          markDirty(true);
          updateJsonInspector();
        });
      }
    }
  }

  function updateJsonInspector() {
    const pre = document.getElementById("json-live-pre");
    if (!pre || !state) return;
    pre.textContent = JSON.stringify(state, null, 2);
  }

  function applySectionVisibility() {
    const secCb = document.getElementById("card-sec-cb");
    const secMacro = document.getElementById("card-sec-macro");
    const secAlloc = document.getElementById("card-sec-alloc");
    const secJson = document.getElementById("card-sec-json");

    if (!secCb || !secMacro || !secAlloc || !secJson) return;

    secCb.style.display = activeFilter === "cb" ? "block" : "none";
    secMacro.style.display = activeFilter === "macro" ? "block" : "none";
    secAlloc.style.display = activeFilter === "alloc" ? "block" : "none";
    secJson.style.display = activeFilter === "json" ? "block" : "none";
  }

  // --------------------------------------------------------------------------
  // SHINY WEBSOCKET BINDINGS & EVENT HANDLERS
  // --------------------------------------------------------------------------

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-view-mode]").forEach((btn) => {
      btn.addEventListener("click", function () {
        document.querySelectorAll("[data-view-mode]").forEach((b) => b.classList.remove("active"));
        this.classList.add("active");
        viewMode = this.getAttribute("data-view-mode");
        renderAll();
      });
    });

    document.querySelectorAll("[data-sec-tab]").forEach((btn) => {
      btn.addEventListener("click", function () {
        document.querySelectorAll("[data-sec-tab]").forEach((b) => b.classList.remove("active"));
        this.classList.add("active");
        activeFilter = this.getAttribute("data-sec-tab");
        applySectionVisibility();
      });
    });

    const dateInput = document.getElementById("meta-committee-date");
    if (dateInput) {
      dateInput.addEventListener("change", function () {
        if (!state) return;
        state.meta.committee_date = this.value;
        markDirty(true);
        updateJsonInspector();
      });
    }

    const btnSave = document.getElementById("btn-save-db");
    if (btnSave) {
      btnSave.addEventListener("click", function () {
        if (!state || !window.Shiny) return;
        showToast("Speichere JSON-Dokument in Datenbank...");
        window.Shiny.setInputValue(
          "cms_save_payload",
          {
            payload_json: JSON.stringify(state),
            trigger_build: false,
            nonce: Date.now()
          },
          { priority: "event" }
        );
      });
    }

    const btnPublish = document.getElementById("btn-save-publish");
    if (btnPublish) {
      btnPublish.addEventListener("click", function () {
        if (!state || !window.Shiny) return;
        showToast("Speichere & starte Quarto-Build der Public-Seite...");
        window.Shiny.setInputValue(
          "cms_save_payload",
          {
            payload_json: JSON.stringify(state),
            trigger_build: true,
            nonce: Date.now()
          },
          { priority: "event" }
        );
      });
    }
  });

  if (window.Shiny) {
    registerShinyHandlers();
  } else {
    document.addEventListener("shiny:connected", registerShinyHandlers);
  }

  function registerShinyHandlers() {
    window.Shiny.addCustomMessageHandler("init_hub_state", function (msg) {
      state = typeof msg.payload === "string" ? JSON.parse(msg.payload) : msg.payload;
      markDirty(false);
      renderAll();
    });

    window.Shiny.addCustomMessageHandler("save_Order_ack", function (msg) {
      if (msg.success) {
        if (state && state.meta) {
          state.meta.version = msg.version;
          state.meta.updated_at = msg.updated_at;
          state.meta.updated_by = msg.updated_by;
        }
        markDirty(false);
        updateJsonInspector();
        showToast(msg.message || "Erfolgreich gespeichert.");
      } else {
        showToast(msg.message || "Fehler beim Speichern.", true);
      }
    });
  }
})();
