# ============================================================================
# LUKB Investment Office Hub (v2) – JSON-First Persistenz-Layer
# ============================================================================
# Diese Datei liegt sowohl in `R_shared/` als auch direkt in den beiden
# unabhängigen Deployment-Ordnern (`cms_app/R/` und `static_hub/R/`), damit
# jedes Bundle auf Posit Connect komplett eigenständig (ohne `../`-Zugriffe)
# veröffentlicht werden kann.
# ============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(jsonlite)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

#' Ermittelt das Projekt-Root-Verzeichnis (für lokale SQLite-Entwicklung)
get_project_root <- function() {
  candidates <- c(".", "..", "../..", "d:/Projekte/LUKB/Hub-Seite")
  for (cand in candidates) {
    if (dir.exists(file.path(cand, "cms_app")) && dir.exists(file.path(cand, "static_hub"))) {
      return(normalizePath(cand, winslash = "/", mustWork = FALSE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = FALSE)
}

#' Gibt den aktiven Datenbank-Modus zurück ("mssql" oder "sqlite")
get_db_mode <- function() {
  srv <- Sys.getenv("MSSQL_SERVER", unset = "")
  if (nzchar(srv) && requireNamespace("odbc", quietly = TRUE)) {
    return("mssql")
  }
  "sqlite"
}

#' Parst Einzelwerte oder Zins-Spannen (z.B. "4.25-4.50", "3.75 - 4%", "-0.25")
#' und gibt den numerischen Wert bzw. den Mittelwert der Spanne zurück.
parse_rate_midpoint <- function(val) {
  if (is.null(val) || length(val) == 0 || is.na(val)) return(NA_real_)
  if (is.numeric(val)) return(as.numeric(val))
  s <- gsub("%", "", as.character(val))
  s <- gsub(",", ".", s)
  s <- trimws(s)
  if (!nzchar(s)) return(NA_real_)

  m <- regexec("^([+-]?\\d+(?:\\.\\d+)?)\\s*-\\s*([+-]?\\d+(?:\\.\\d+)?)$", s)
  parts <- regmatches(s, m)[[1]]
  if (length(parts) == 3) {
    n1 <- suppressWarnings(as.numeric(parts[2]))
    n2 <- suppressWarnings(as.numeric(parts[3]))
    if (!is.na(n1) && !is.na(n2)) return((n1 + n2) / 2.0)
  }

  nums_str <- regmatches(s, gregexpr("[+-]?\\d+(?:\\.\\d+)?", s))[[1]]
  if (length(nums_str) == 1) {
    return(suppressWarnings(as.numeric(nums_str[1])))
  } else if (length(nums_str) >= 2 && grepl("\\d\\s*-\\s*\\d", s)) {
    n1 <- suppressWarnings(as.numeric(nums_str[1]))
    n2 <- suppressWarnings(as.numeric(nums_str[2]))
    return((n1 + n2) / 2.0)
  }
  suppressWarnings(as.numeric(s))
}

#' Formatiert eine Zinsangabe (Einzelwert oder Spanne) sauber für die Anzeige
format_rate_display <- function(val, digits = 2) {
  if (is.null(val) || length(val) == 0 || is.na(val)) return("–")
  s <- trimws(gsub("%", "", as.character(val)))
  if (!nzchar(s)) return("–")
  s_dot <- gsub(",", ".", s)
  m <- regexec("^([+-]?\\d+(?:\\.\\d+)?)\\s*-\\s*([+-]?\\d+(?:\\.\\d+)?)$", s_dot)
  parts <- regmatches(s_dot, m)[[1]]
  if (length(parts) == 3) {
    n1 <- as.numeric(parts[2])
    n2 <- as.numeric(parts[3])
    return(sprintf("%.*f–%.*f %%", digits, n1, digits, n2))
  }
  num <- suppressWarnings(as.numeric(s_dot))
  if (!is.na(num)) {
    return(sprintf("%.*f %%", digits, num))
  }
  paste0(s, " %")
}

#' Prüft, ob in einer Liste von Zeilen mindestens ein nicht-leerer Zeilenkommentar existiert
has_any_row_comment <- function(rows_list) {
  if (is.null(rows_list) || length(rows_list) == 0) return(FALSE)
  any(vapply(rows_list, function(r) {
    c_txt <- trimws(as.character(r$comment %||% ""))
    nzchar(c_txt)
  }, logical(1)))
}

#' Erstellt eine Datenbankverbindung (MSSQL oder lokales SQLite-Fallback)
get_db_connection <- function() {
  if (get_db_mode() == "mssql") {
    driver   <- Sys.getenv("MSSQL_DRIVER", unset = "ODBC Driver 17 for SQL Server")
    server   <- Sys.getenv("MSSQL_SERVER")
    database <- Sys.getenv("MSSQL_DB", unset = "LUKB_IO_Hub")
    uid      <- Sys.getenv("MSSQL_UID", unset = "")
    pwd      <- Sys.getenv("MSSQL_PWD", unset = "")

    if (nzchar(uid)) {
      return(DBI::dbConnect(
        odbc::odbc(),
        Driver = driver, Server = server, Database = database,
        UID = uid, PWD = pwd, encoding = "UTF-8"
      ))
    } else {
      return(DBI::dbConnect(
        odbc::odbc(),
        Driver = driver, Server = server, Database = database,
        Trusted_Connection = "Yes", encoding = "UTF-8"
      ))
    }
  } else {
    # Optionaler expliziter Pfad über Umgebungsvariable SQLITE_DB_PATH
    custom_sqlite <- Sys.getenv("SQLITE_DB_PATH", unset = "")
    if (nzchar(custom_sqlite)) {
      db_path <- custom_sqlite
      data_dir <- dirname(db_path)
    } else {
      root <- get_project_root()
      data_dir <- file.path(root, "data")
      db_path <- file.path(data_dir, "io_hub_v2.sqlite")
    }
    if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
    con <- DBI::dbConnect(RSQLite::SQLite(), dbname = db_path)
    if (!("io_hub_state" %in% DBI::dbListTables(con))) {
      init_v2_database(con)
    }
    return(con)
  }
}

#' Liefert das Standard-JSON-Dokument (Initial-Seed) für die 3 Kernbereiche
get_default_hub_payload <- function() {
  curr_year <- as.integer(format(Sys.Date(), "%Y"))
  list(
    meta = list(
      title = "LUKB Investment Office – Markt- & Konjunkturüberblick",
      committee_date = format(Sys.Date(), "%Y-%m-%d"),
      updated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      updated_by = "Dr. M. Kaufmann (CIO)"
    ),
    central_banks = list(
      commentary = "Die grossen Notenbanken befinden sich in einer fortgeschrittenen Phase der geldpolitischen Normalisierung. Während die SNB bei einem Leitzins von 0.50 % verharrt und auf Sicht von 12 Monaten keine Anpassung signalisiert, erwarten wir von der US-Notenbank (Fed) und der EZB noch schrittweise Zinssenkungen in Richtung des neutralen Zinsniveaus. Die Bank of Japan (BoJ) setzt ihren vorsichtigen Zinserhöhungspfad fort.",
      rows = list(
        list(id = "SNB", name = "SNB", full_name = "Schweizerische Nationalbank",           currency = "CHF", current = "0.50",      m3 = "0.50",      m12 = "0.50",      comment = "SNB sieht aktuell keinen Bedarf für Negativzinsen."),
        list(id = "FED", name = "Fed", full_name = "US Federal Reserve (Target Range)",     currency = "USD", current = "4.25-4.50", m3 = "4.00-4.25", m12 = "3.50-3.75", comment = "Schrittweise Senkung des Zielbands in Richtung neutrales Niveau."),
        list(id = "EZB", name = "EZB", full_name = "Europäische Zentralbank (Einlagesatz)", currency = "EUR", current = "2.50",      m3 = "2.25",      m12 = "2.00",      comment = "Nachlassende Dienstleistungsinflation erlaubt weitere Schritte."),
        list(id = "BOE", name = "BoE", full_name = "Bank of England (Bank Rate)",           currency = "GBP", current = "4.00",      m3 = "3.75",      m12 = "3.25",      comment = "Vorsichtiger Lockerungspfad angesichts robuster Lohnentwicklung."),
        list(id = "BOJ", name = "BoJ", full_name = "Bank of Japan (Overnight Call Rate)",   currency = "JPY", current = "0.50",      m3 = "0.75",      m12 = "1.00",      comment = "Graduelle Zinsnormalisierung bei anhaltendem Lohnwachstum.")
      )
    ),
    macro = list(
      base_year = curr_year,
      commentary = "Die Weltwirtschaft wächst nahe ihrem langfristigen Potenzial von knapp über 3 %. In der Schweiz stützen der private Konsum und die robuste Pharmabranche das Wachstum, während die Inflation mit 0.8 % tief im Zielband der SNB verankert bleibt. Indien führt das Wachstum der grossen Volkswirtschaften weiter an.",
      rows = list(
        list(id = "CH", country = "Schweiz",   code = "CH", gdp_t_minus_1 = 1.3, gdp_t = 1.5, gdp_t_plus_1 = 1.7, cpi_t_minus_1 = 1.1, cpi_t = 0.8, cpi_t_plus_1 = 1.0, comment = ""),
        list(id = "EU", country = "Euroraum",  code = "EU", gdp_t_minus_1 = 0.9, gdp_t = 1.2, gdp_t_plus_1 = 1.4, cpi_t_minus_1 = 2.2, cpi_t = 1.9, cpi_t_plus_1 = 2.0, comment = ""),
        list(id = "UK", country = "UK",        code = "GB", gdp_t_minus_1 = 1.1, gdp_t = 1.3, gdp_t_plus_1 = 1.4, cpi_t_minus_1 = 2.6, cpi_t = 2.2, cpi_t_plus_1 = 2.0, comment = ""),
        list(id = "US", country = "USA",       code = "US", gdp_t_minus_1 = 2.5, gdp_t = 2.1, gdp_t_plus_1 = 1.9, cpi_t_minus_1 = 2.8, cpi_t = 2.4, cpi_t_plus_1 = 2.1, comment = ""),
        list(id = "JP", country = "Japan",     code = "JP", gdp_t_minus_1 = 0.7, gdp_t = 1.0, gdp_t_plus_1 = 0.9, cpi_t_minus_1 = 2.5, cpi_t = 2.0, cpi_t_plus_1 = 1.8, comment = ""),
        list(id = "BR", country = "Brasilien", code = "BR", gdp_t_minus_1 = 2.9, gdp_t = 2.2, gdp_t_plus_1 = 2.4, cpi_t_minus_1 = 4.4, cpi_t = 4.1, cpi_t_plus_1 = 3.8, comment = ""),
        list(id = "RU", country = "Russland",  code = "RU", gdp_t_minus_1 = 3.4, gdp_t = 1.5, gdp_t_plus_1 = 1.2, cpi_t_minus_1 = 8.1, cpi_t = 6.8, cpi_t_plus_1 = 5.5, comment = ""),
        list(id = "IN", country = "Indien",    code = "IN", gdp_t_minus_1 = 6.8, gdp_t = 6.5, gdp_t_plus_1 = 6.6, cpi_t_minus_1 = 4.7, cpi_t = 4.3, cpi_t_plus_1 = 4.1, comment = ""),
        list(id = "CN", country = "China",     code = "CN", gdp_t_minus_1 = 4.8, gdp_t = 4.5, gdp_t_plus_1 = 4.2, cpi_t_minus_1 = 0.6, cpi_t = 1.1, cpi_t_plus_1 = 1.5, comment = ""),
        list(id = "WL", country = "Welt",      code = "WL", gdp_t_minus_1 = 3.2, gdp_t = 3.1, gdp_t_plus_1 = 3.2, cpi_t_minus_1 = 4.1, cpi_t = 3.4, cpi_t_plus_1 = 3.1, comment = "")
      )
    ),
    allocation = list(
      commentary = "In unserer taktischen Vermögensallokation bevorzugen wir Sachwerte mit verlässlichen Cashflows. Aktien, Schweizer Immobilien und Gold sind übergewichtet, finanziert über eine Untergewichtung der niedrig verzinsten Liquidität.",
      rows = list(
        list(id = "CASH",  asset_class = "Cash",         stance = -1L, change =  0L, forecast_12m = 0.5, comment = "Nach Zinssenkungen am kurzen Ende unattraktive Realverzinsung in CHF."),
        list(id = "BONDS", asset_class = "Obligationen", stance =  0L, change =  1L, forecast_12m = 2.1, comment = "Fokus auf mittlere Duration und erstklassige Unternehmensanleihen (IG)."),
        list(id = "EQ",    asset_class = "Aktien",       stance =  1L, change =  0L, forecast_12m = 6.8, comment = "Solides Gewinnwachstum; Fokus auf Qualitätswerte Schweiz und USA."),
        list(id = "RE",    asset_class = "Immobilien",   stance =  1L, change =  1L, forecast_12m = 5.2, comment = "Tiefes Zinsumfeld und hohes Mietwachstum stützen Schweizer Immobilienfonds."),
        list(id = "GOLD",  asset_class = "Gold",         stance =  1L, change =  0L, forecast_12m = 5.5, comment = "Strukturelle Käufe der Zentralbanken und geopolitische Portfolioversicherung."),
        list(id = "COMM",  asset_class = "Rohstoffe",    stance =  0L, change = -1L, forecast_12m = 1.5, comment = "Industriemetalle unterstützt, Energiesektor durch reichliches Angebot gedeckelt.")
      )
    )
  )
}

#' Initialisiert die Tabellen und schreibt das Seed-JSON-Dokument
init_v2_database <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS io_hub_state (
      doc_key      TEXT PRIMARY KEY,
      schema_ver   INTEGER NOT NULL DEFAULT 2,
      payload_json TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      updated_by   TEXT NOT NULL,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS io_hub_history (
      history_id   INTEGER PRIMARY KEY AUTOINCREMENT,
      doc_key      TEXT NOT NULL,
      version      INTEGER NOT NULL,
      action_type  TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      changed_by   TEXT NOT NULL,
      changed_at   TEXT NOT NULL
    )
  ")

  seed_payload <- get_default_hub_payload()
  json_str <- as.character(jsonlite::toJSON(seed_payload, auto_unbox = TRUE, pretty = TRUE))
  now_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  DBI::dbExecute(
    con,
    "INSERT OR REPLACE INTO io_hub_state (doc_key, schema_ver, payload_json, updated_at, updated_by, version)
     VALUES ('hub_main_payload', 2, ?, ?, 'Dr. M. Kaufmann (CIO)', 1)",
    params = list(json_str, now_str)
  )

  DBI::dbExecute(
    con,
    "INSERT INTO io_hub_history (doc_key, version, action_type, payload_json, changed_by, changed_at)
     VALUES ('hub_main_payload', 1, 'INIT', ?, 'System Setup', ?)",
    params = list(json_str, now_str)
  )
}

#' Lädt das gesamte Hub-JSON-Dokument aus der Datenbank
load_hub_payload <- function(doc_key = "hub_main_payload", con = NULL) {
  close_on_exit <- FALSE
  if (is.null(con)) {
    con <- get_db_connection()
    close_on_exit <- TRUE
  }
  on.exit(if (close_on_exit) DBI::dbDisconnect(con), add = TRUE)

  res <- DBI::dbGetQuery(
    con,
    "SELECT doc_key, schema_ver, payload_json, updated_at, updated_by, version FROM io_hub_state WHERE doc_key = ?",
    params = list(doc_key)
  )
  if (nrow(res) == 0) {
    init_v2_database(con)
    res <- DBI::dbGetQuery(
      con,
      "SELECT doc_key, schema_ver, payload_json, updated_at, updated_by, version FROM io_hub_state WHERE doc_key = ?",
      params = list(doc_key)
    )
  }

  payload <- jsonlite::fromJSON(res$payload_json[1], simplifyVector = FALSE)
  payload$meta$version    <- as.integer(res$version[1])
  payload$meta$updated_at <- as.character(res$updated_at[1])
  payload$meta$updated_by <- as.character(res$updated_by[1])
  payload$meta$db_mode    <- get_db_mode()
  payload
}

#' Speichert das gesamte Hub-JSON-Dokument atomar in der Datenbank + Audit-History
save_hub_payload <- function(payload, user = "Redakteur", action_type = "SAVE", doc_key = "hub_main_payload", con = NULL) {
  close_on_exit <- FALSE
  if (is.null(con)) {
    con <- get_db_connection()
    close_on_exit <- TRUE
  }
  on.exit(if (close_on_exit) DBI::dbDisconnect(con), add = TRUE)

  now_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  curr <- DBI::dbGetQuery(con, "SELECT version FROM io_hub_state WHERE doc_key = ?", params = list(doc_key))
  new_ver <- if (nrow(curr) > 0) as.integer(curr$version[1]) + 1L else 1L

  if (is.null(payload$meta)) payload$meta <- list()
  payload$meta$updated_at <- now_str
  payload$meta$updated_by <- user
  payload$meta$version    <- new_ver

  json_str <- as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, null = "null"))

  if (get_db_mode() == "mssql") {
    if (nrow(curr) > 0) {
      DBI::dbExecute(
        con,
        "UPDATE dbo.io_hub_state SET payload_json = ?, updated_at = SYSUTCDATETIME(), updated_by = ?, version = ? WHERE doc_key = ?",
        params = list(json_str, user, new_ver, doc_key)
      )
    } else {
      DBI::dbExecute(
        con,
        "INSERT INTO dbo.io_hub_state (doc_key, schema_ver, payload_json, updated_by, version) VALUES (?, 2, ?, ?, ?)",
        params = list(doc_key, json_str, user, new_ver)
      )
    }
    DBI::dbExecute(
      con,
      "INSERT INTO dbo.io_hub_history (doc_key, version, action_type, payload_json, changed_by) VALUES (?, ?, ?, ?, ?)",
      params = list(doc_key, new_ver, action_type, json_str, user)
    )
  } else {
    DBI::dbExecute(
      con,
      "INSERT OR REPLACE INTO io_hub_state (doc_key, schema_ver, payload_json, updated_at, updated_by, version)
       VALUES (?, 2, ?, ?, ?, ?)",
      params = list(doc_key, json_str, now_str, user, new_ver)
    )
    DBI::dbExecute(
      con,
      "INSERT INTO io_hub_history (doc_key, version, action_type, payload_json, changed_by, changed_at)
       VALUES (?, ?, ?, ?, ?, ?)",
      params = list(doc_key, new_ver, action_type, json_str, user, now_str)
    )
  }

  list(version = new_ver, updated_at = now_str, updated_by = user)
}

#' Lädt die letzten Versions-Einträge aus io_hub_history
load_hub_history <- function(limit = 15L, con = NULL) {
  close_on_exit <- FALSE
  if (is.null(con)) {
    con <- get_db_connection()
    close_on_exit <- TRUE
  }
  on.exit(if (close_on_exit) DBI::dbDisconnect(con), add = TRUE)

  if (get_db_mode() == "mssql") {
    sql <- sprintf("SELECT TOP %d history_id, version, action_type, changed_by, changed_at FROM dbo.io_hub_history ORDER BY history_id DESC", as.integer(limit))
    DBI::dbGetQuery(con, sql)
  } else {
    DBI::dbGetQuery(
      con,
      "SELECT history_id, version, action_type, changed_by, changed_at FROM io_hub_history ORDER BY history_id DESC LIMIT ?",
      params = list(as.integer(limit))
    )
  }
}
