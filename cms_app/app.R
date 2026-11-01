# ============================================================================
# DEPLOYMENT 1: LUKB Investment Office – High-Reactivity JSON CMS (v2)
# ============================================================================
# Architektur:
# - Kein bslib, kein Bootstrap-Overhead, keine langsamen Server-Render-Loops.
# - Das Frontend besteht aus reinem, zeitgemässem Editorial-Financial HTML/CSS/JS
#   (`www/cms.css` & `www/cms.js`).
# - Shiny fungiert als reines High-Speed Backend (Authentifizierung via
#   Posit Connect `session$user`, Laden/Speichern des JSON-Dokuments in
#   MS SQL Server / SQLite und Auslösen des Quarto-Renders).
# ============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(htmltools)
  library(DBI)
  library(jsonlite)
})

# Lade lokale R-Hilfsdateien direkt aus dem autarken Deployment-Ordner (cms_app/R/)
local_r_dir <- if (dir.exists("R")) "R" else if (dir.exists("cms_app/R")) "cms_app/R" else "../R_shared"
source(file.path(local_r_dir, "db_connection.R"))
source(file.path(local_r_dir, "hub_helpers.R"))

ui <- htmltools::tagList(
  tags$head(
    tags$meta(charset = "utf-8"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0"),
    tags$title("LUKB Investment Office · Editorial Studio (CMS)"),
    tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
    tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = "anonymous"),
    tags$link(
      href = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600;700&family=Newsreader:opsz,wght@6..72,500;6..72,600&display=swap",
      rel = "stylesheet"
    ),
    tags$link(rel = "stylesheet", type = "text/css", href = "cms.css"),
    tags$script(src = "cms.js")
  ),

  # 1. Sticky Top Command Bar
  tags$header(
    class = "cms-topbar",
    tags$div(
      class = "cms-topbar-inner",
      tags$div(
        class = "brand-cluster",
        tags$div(class = "brand-monogram", "LUKB"),
        tags$div(
          class = "brand-titles",
          tags$span(class = "brand-kicker", "Luzerner Kantonalbank · Investment Office"),
          tags$span(class = "brand-main", "Editorial Studio & Prognose-Desk")
        )
      ),

      # Umschalter: Editier-Modus vs. Public-Ansicht (Live-Preview)
      tags$div(
        class = "mode-switch",
        tags$button(
          type = "button",
          class = "mode-btn active",
          `data-view-mode` = "edit",
          "Eingabemaske (Editieren)"
        ),
        tags$button(
          type = "button",
          class = "mode-btn",
          `data-view-mode` = "preview",
          "Public-Ansicht (Live-Vorschau)"
        )
      ),

      # Speicher-Status & Aktionen
      tags$div(
        class = "action-cluster",
        tags$div(
          class = "status-indicator",
          tags$span(id = "sync-dot", class = "status-dot"),
          tags$span(id = "sync-text", "Verbunden")
        ),
        tags$button(
          id = "btn-save-db",
          type = "button",
          class = "btn-action btn-save",
          "Nur in DB speichern"
        ),
        tags$button(
          id = "btn-save-publish",
          type = "button",
          class = "btn-action btn-publish",
          "Speichern & Public-Seite bauen"
        )
      )
    )
  ),

  # 2. Sub-Navigation & Meta-Informationen
  tags$div(
    class = "cms-subbar",
    tags$div(
      class = "cms-subbar-inner",
      tags$div(
        class = "nav-tabs-custom",
        tags$button(type = "button", class = "nav-tab-btn active", `data-sec-tab` = "cb", "01 · Zentralbankprognosen"),
        tags$button(type = "button", class = "nav-tab-btn", `data-sec-tab` = "macro", "02 · Makroprognosen (t-1 / t / t+1)"),
        tags$button(type = "button", class = "nav-tab-btn", `data-sec-tab` = "alloc", "03 · Allokation & Prognosen"),
        tags$button(type = "button", class = "nav-tab-btn", `data-sec-tab` = "json", "{ } JSON-Struktur")
      ),
      tags$div(
        class = "meta-inline-inputs",
        tags$label(`for` = "meta-committee-date", "Stichtag / Beschluss:"),
        tags$input(id = "meta-committee-date", type = "date"),
        tags$span("·"),
        tags$span("Backend: ", tags$strong(id = "meta-db-badge", "...")),
        tags$span("·"),
        tags$span("User: ", tags$strong(id = "meta-user-badge", "..."))
      )
    )
  ),

  # 3. Haupt-Arbeitsbereich (3 Sektionen + JSON-Inspector)
  tags$main(
    class = "workspace-shell",

    # SEKTION 1: ZENTRALBANKPROGNOSEN
    tags$section(
      id = "card-sec-cb",
      class = "editorial-section",
      tags$div(
        class = "section-head",
        tags$div(
          tags$span(class = "section-index", "Sektion 01 · Geldpolitik & Zinsausblick"),
          tags$h2(class = "section-title", "Zentralbankprognosen"),
          tags$div(class = "section-subtitle", "Leitzinsen Aktuell, in 3 Monaten und in 12 Monaten inkl. automatischer Basispunkte-Differenz")
        )
      ),
      tags$div(id = "sec-cb-content", class = "section-body")
    ),

    # SEKTION 2: MAKROPROGNOSEN (Wachstum & Inflation für t-1, t, t+1)
    tags$section(
      id = "card-sec-macro",
      class = "editorial-section",
      tags$div(
        class = "section-head",
        tags$div(
          tags$span(class = "section-index", "Sektion 02 · Konjunktur & Teuerung"),
          tags$h2(class = "section-title", "Makroprognosen für Wachstum (BIP) und Inflation"),
          tags$div(class = "section-subtitle", "10 Kernregionen · Explizite Jahreszuordnung für t-1, t und t+1")
        ),
        tags$div(id = "macro-year-control")
      ),
      tags$div(id = "sec-macro-content", class = "section-body")
    ),

    # SEKTION 3: ALLOKATIONSTABELLE MIT PROGNOSEN
    tags$section(
      id = "card-sec-alloc",
      class = "editorial-section",
      tags$div(
        class = "section-head",
        tags$div(
          tags$span(class = "section-index", "Sektion 03 · Anlagepolitik & Positionierung"),
          tags$h2(class = "section-title", "Allokationstabelle mit 12M-Prognosen"),
          tags$div(class = "section-subtitle", "Haupt-Assetklassen: Cash, Obligationen, Aktien, Immobilien, Gold, Rohstoffe")
        )
      ),
      tags$div(id = "sec-alloc-content", class = "section-body")
    ),

    # SEKTION 4: FLEXIBLE JSON-PAYLOAD VORSCHAU (Datenbank-Dokument)
    tags$section(
      id = "card-sec-json",
      class = "editorial-section",
      tags$div(
        class = "section-head",
        tags$div(
          tags$span(class = "section-index", "Datenarchitektur · Persistenz-Payload"),
          tags$h2(class = "section-title", "Live JSON-Dokument (MS SQL / SQLite)"),
          tags$div(class = "section-subtitle", "Dieses JSON-Objekt wird 1:1 in der Datenbank gespeichert und beim Quarto-Build der Public-Seite konsumiert.")
        )
      ),
      tags$div(
        class = "section-body",
        tags$pre(id = "json-live-pre", class = "json-inspector-card")
      )
    )
  ),

  # Toast Notification Element
  tags$div(id = "cms-toast", class = "cms-toast")
)

server <- function(input, output, session) {
  # Aktueller Benutzer (Posit Connect Login oder lokaler Fallback)
  get_active_user <- function() {
    u <- session$user
    if (!is.null(u) && nzchar(u)) return(u)
    Sys.getenv("USER", unset = Sys.getenv("USERNAME", unset = "lukb_oekonom"))
  }

  # Initiales Laden des JSON-Payloads beim Verbindungsaufbau
  session$onFlushed(function() {
    payload <- load_hub_payload()
    payload$meta$updated_by <- get_active_user()
    session$sendCustomMessage("init_hub_state", list(payload = payload))
  }, once = TRUE)

  # Speichern (und optionales Auslösen des Quarto-Builds) bei Klick im JS-Frontend
  shiny::observeEvent(input$cms_save_payload, {
    req_data <- input$cms_save_payload
    shiny::req(req_data$payload_json)

    user <- get_active_user()
    trigger_build <- isTRUE(req_data$trigger_build)

    tryCatch({
      parsed_payload <- jsonlite::fromJSON(req_data$payload_json, simplifyVector = FALSE)
      action_lbl <- if (trigger_build) "PUBLISH" else "SAVE"
      save_info <- save_hub_payload(parsed_payload, user = user, action_type = action_lbl)

      msg_text <- paste0("In Datenbank gespeichert (Version v", save_info$version, ").")

      if (trigger_build) {
        build_res <- trigger_static_hub_build(user = user)
        if (isTRUE(build_res$success)) {
          msg_text <- paste0("Gespeichert (v", save_info$version, ") & Public-Seite erfolgreich neu gebaut!")
        } else {
          msg_text <- paste0("In DB gespeichert (v", save_info$version, "), aber Build-Warnung: ", build_res$message)
        }
      }

      session$sendCustomMessage("save_Order_ack", list(
        success = TRUE,
        version = save_info$version,
        updated_at = save_info$updated_at,
        updated_by = save_info$updated_by,
        message = msg_text
      ))
    }, error = function(e) {
      session$sendCustomMessage("save_Order_ack", list(
        success = FALSE,
        message = paste("Fehler beim Speichern:", conditionMessage(e))
      ))
    })
  })
}

shiny::shinyApp(ui = ui, server = server)
