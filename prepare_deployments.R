# ============================================================================
# LUKB Investment Office Hub – Synchronisierung & Deployment-Vorbereitung
# ============================================================================
# Dieses Skript stellt sicher, dass die gemeinsamen R-Module aus `R_shared/`
# in beide unabhängigen Deployment-Ordner (`cms_app/R/` und `static_hub/R/`)
# kopiert werden und (falls `rsconnect` installiert ist) die `manifest.json`
# Dateien für Posit Connect aktualisiert werden.
# ============================================================================

cat("=== 1. Synchronisiere R_shared Module in beide Deployment-Ordner ===\n")

if (!dir.exists("cms_app/R")) dir.create("cms_app/R", recursive = TRUE)
if (!dir.exists("static_hub/R")) dir.create("static_hub/R", recursive = TRUE)

file.copy("R_shared/db_connection.R", "cms_app/R/db_connection.R", overwrite = TRUE)
file.copy("R_shared/hub_helpers.R",   "cms_app/R/hub_helpers.R",   overwrite = TRUE)
file.copy("R_shared/db_connection.R", "static_hub/R/db_connection.R", overwrite = TRUE)

cat("-> cms_app/R/db_connection.R aktualisiert\n")
cat("-> cms_app/R/hub_helpers.R aktualisiert\n")
cat("-> static_hub/R/db_connection.R aktualisiert\n")

if (requireNamespace("rsconnect", quietly = TRUE)) {
  cat("\n=== 2. Erzeuge manifest.json für Posit Connect ===\n")
  rsconnect::writeManifest(appDir = "cms_app", appPrimaryDoc = "app.R")
  cat("-> cms_app/manifest.json erstellt\n")

  quarto_bin <- Sys.which("quarto")
  if (nzchar(quarto_bin)) {
    rsconnect::writeManifest(appDir = "static_hub", appPrimaryDoc = "index.qmd", quarto = quarto_bin)
  } else {
    rsconnect::writeManifest(appDir = "static_hub", appPrimaryDoc = "index.qmd")
  }
  cat("-> static_hub/manifest.json erstellt\n")
} else {
  cat("\nHinweis: Paket 'rsconnect' ist lokal noch nicht installiert.\n")
  cat("Für Push-Button-Deployment aus RStudio / Posit Workbench oder Git-Deployment:\n")
  cat("  install.packages('rsconnect')\n")
  cat("  source('prepare_deployments.R')\n")
}

cat("\nBeide Deployment-Ordner ('cms_app/' und 'static_hub/') sind vollständig autark und bereit für Posit Connect!\n")
