# LUKB Investment Office Hub (v2) – High-Reactivity JSON CMS & Static Quarto Hub

Zweiteiliges System für das Investment Office der Luzerner Kantonalbank (LUKB), vorbereitet für **zwei unabhängige Deployments auf Posit Connect (Advanced)**.

---

## Autarke Ordnerstruktur für Posit Connect

Beide Deployment-Ordner (`cms_app/` und `static_hub/`) enthalten ihre benötigten R-Hilfsfunktionen direkt in einem eigenen Unterordner `R/`. Dadurch ist kein Zugriff auf übergeordnete Verzeichnisse (`../`) nötig, und beide Ordner können komplett eigenständig als separate Bundles auf Posit Connect veröffentlicht werden:

```text
d:/Projekte/LUKB/Hub-Seite/
├── prepare_deployments.R       # Synchronisiert R_shared/ in beide Bundles & erstellt manifest.json
├── R_shared/                   # Zentrale Quelle für DB-Layer & Posit Connect API Trigger
│   ├── db_connection.R
│   └── hub_helpers.R
├── sql/                        # T-SQL Skripte für MS SQL Server
│   ├── 01_create_tables.sql
│   └── 02_seed_initial_data.sql
│
├── cms_app/                    # === DEPLOYMENT 1: SHINY REDAKTIONS-CMS (Mit Login) ===
│   ├── app.R                   # Reines JSON/WebSocket-Backend + Custom HTML UI
│   ├── R/
│   │   ├── db_connection.R     # Autarke Kopie des DB-Layers
│   │   └── hub_helpers.R       # Autarke Kopie des Posit Connect API Build-Triggers (Variante B)
│   └── www/
│       ├── cms.css             # Editorial Financial Design System
│       └── cms.js              # High-Speed Client-Engine (Spannen-Parser, 0ms Reaktivität)
│
└── static_hub/                 # === DEPLOYMENT 2: QUARTO PUBLIC HUB (Ohne Login) ===
    ├── _quarto.yml             # Quarto-Konfiguration
    ├── index.qmd               # Generiert beim Build die statische HTML-Seite aus dem DB-JSON
    ├── custom.scss             # Editorial Financial Styling für das Public-Dokument
    ├── index.html              # Fertig gerenderte statische Ausgabedatei
    ├── R/
    │   └── db_connection.R     # Autarke Kopie des DB-Layers
    └── assets/
        └── js/hub_interactivity.js # Client-seitige Tab-Umschaltung ohne Server
```

---

## Schritt-für-Schritt Deployment auf Posit Connect (Advanced)

### 1. Datenbank vorbereiten (MS SQL Server)
Führen Sie einmalig [01_create_tables.sql](file:///d:/Projekte/LUKB/Hub-Seite/sql/01_create_tables.sql) und [02_seed_initial_data.sql](file:///d:/Projekte/LUKB/Hub-Seite/sql/02_seed_initial_data.sql) auf Ihrer MS SQL Server Datenbank aus.

### 2. Deployment 2 veröffentlichen: `static_hub` (Public Quarto-Seite)
1. Veröffentlichen Sie den Ordner `static_hub/` (`index.qmd` inklusive Quellcode, damit Posit Connect das Dokument neu rendern kann) auf Posit Connect.
2. Setzen Sie im Tab **Access**:
   * *Who can view this content:* **"Anyone — no login required"**
3. Setzen Sie im Tab **Vars** (Umgebungsvariablen) die DB-Zugangsdaten:
   * `MSSQL_SERVER` = `<Ihr-SQL-Server>`
   * `MSSQL_DB` = `<Datenbankname>`
   * `MSSQL_UID` / `MSSQL_PWD` (falls nicht Integrated Windows Auth / Kerberos genutzt wird)
4. Aktivieren Sie im Tab **Schedule** den regulären automatischen Rebuild (z. B. täglich morgens).
5. Notieren Sie sich aus dem Tab **Info** die **Content GUID** dieses Quarto-Dokuments.

### 3. Deployment 1 veröffentlichen: `cms_app` (Shiny Eingabemaske + Variante B Trigger)
1. Veröffentlichen Sie den Ordner `cms_app/` (`app.R`) als separates Deployment auf Posit Connect.
2. Setzen Sie im Tab **Access**:
   * *Who can view this content:* **"Specific users or groups"** (Ihre berechtigten Ökonomen / Redakteure).
3. Setzen Sie im Tab **Vars** dieselben DB-Variablen (`MSSQL_SERVER`, `MSSQL_DB`, ...) **plus** die 3 Variablen für **Variante B (Direkter Rebuild-Trigger aus der Shiny-App)**:
   * `CONNECT_SERVER` = `https://ihre-posit-connect-url.lukb.ch`
   * `CONNECT_API_KEY` = `<API-Key eines Users mit Collaborator-Rechten auf static_hub>`
   * `HUB_CONTENT_GUID` = `<Content-GUID von static_hub aus Schritt 2.5>`

Sobald diese 3 Variablen in `cms_app` hinterlegt sind, löst ein Klick auf den goldenen Button **"Speichern & Public-Seite bauen"** in der Shiny-App automatisch über die Posit Connect API den sofortigen Rebuild des Quarto-Deployments `static_hub` aus.
