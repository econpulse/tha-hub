# ============================================================================
# LUKB Investment Office Hub (v2) – Build- & Trigger-Hilfsfunktionen (R_shared)
# ============================================================================
# Stösst den Rebuild der statischen Quarto-Hub-Seite an:
# - Auf Posit Connect Advanced via REST API / `connectapi`
# - Lokal im Entwicklungsmodus via direktem `quarto render` Aufruf
# ============================================================================

trigger_static_hub_build <- function(user = "Redakteur") {
  connect_server  <- Sys.getenv("CONNECT_SERVER", unset = "")
  connect_api_key <- Sys.getenv("CONNECT_API_KEY", unset = "")
  hub_guid        <- Sys.getenv("HUB_CONTENT_GUID", unset = "")

  if (nzchar(connect_server) && nzchar(connect_api_key) && nzchar(hub_guid)) {
    tryCatch({
      if (requireNamespace("connectapi", quietly = TRUE)) {
        client  <- connectapi::connect(server = connect_server, api_key = connect_api_key)
        item    <- connectapi::content_item(client, hub_guid)
        variant <- connectapi::get_variant_default(item)
        connectapi::variant_render(variant)
      } else {
        url <- paste0(sub("/+$", "", connect_server), "/__api__/v1/content/", hub_guid, "/build")
        req <- curl::new_handle()
        curl::handle_setheaders(req, "Authorization" = paste("Key", connect_api_key), "Content-Type" = "application/json")
        curl::handle_setopt(req, customrequest = "POST")
        curl::curl_fetch_memory(url, handle = req)
      }
      return(list(
        success = TRUE,
        mode = "posit_connect",
        timestamp = format(Sys.time(), "%H:%M:%S"),
        message = paste0("Posit Connect Build (GUID ", hub_guid, ") erfolgreich ausgelöst.")
      ))
    }, error = function(e) {
      return(list(
        success = FALSE,
        mode = "posit_connect",
        timestamp = format(Sys.time(), "%H:%M:%S"),
        message = paste("Posit Connect API Fehler:", conditionMessage(e))
      ))
    })
  } else {
    root <- get_project_root()
    qmd_path <- file.path(root, "static_hub", "index.qmd")
    if (!file.exists(qmd_path)) {
      return(list(
        success = FALSE,
        mode = "local",
        timestamp = format(Sys.time(), "%H:%M:%S"),
        message = paste("Quarto-Datei nicht gefunden:", qmd_path)
      ))
    }

    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(file.path(root, "static_hub"))

    res <- system2("quarto", args = c("render", "index.qmd"), stdout = TRUE, stderr = TRUE)
    status <- attr(res, "status")
    if (is.null(status) || status == 0) {
      return(list(
        success = TRUE,
        mode = "local",
        timestamp = format(Sys.time(), "%H:%M:%S"),
        output_file = file.path(root, "static_hub", "index.html"),
        message = "Statische Seite (static_hub/index.html) erfolgreich neu gerendert."
      ))
    } else {
      return(list(
        success = FALSE,
        mode = "local",
        timestamp = format(Sys.time(), "%H:%M:%S"),
        message = paste("Quarto Render Fehler:", paste(res, collapse = "\n"))
      ))
    }
  }
}
