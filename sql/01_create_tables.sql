-- ============================================================================
-- LUKB Investment Office Hub (v2) – Schlankes JSON-first Datenbankschema
-- ============================================================================
-- Architekturprinzip:
-- Alle 3 Informationsbereiche (`central_banks`, `macro`, `allocation`) sowie
-- künftige Erweiterungen werden als versionierte JSON-Dokumente in einer
-- einzigen Zustandstabelle `dbo.io_hub_state` abgelegt. Jede Speicherung legt
-- zudem automatisch einen unveränderlichen Snapshot in `dbo.io_hub_history` an.
-- ============================================================================

IF OBJECT_ID('dbo.io_hub_state', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.io_hub_state (
        doc_key      VARCHAR(64)   NOT NULL PRIMARY KEY, -- z.B. 'hub_main_payload'
        schema_ver   INT           NOT NULL DEFAULT 2,
        payload_json NVARCHAR(MAX) NOT NULL,
        updated_at   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_by   NVARCHAR(128) NOT NULL DEFAULT 'system',
        version      INT           NOT NULL DEFAULT 1,
        CONSTRAINT CK_io_hub_state_isjson CHECK (ISJSON(payload_json) = 1)
    );
END;
GO

IF OBJECT_ID('dbo.io_hub_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.io_hub_history (
        history_id   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        doc_key      VARCHAR(64)   NOT NULL,
        version      INT           NOT NULL,
        action_type  VARCHAR(32)   NOT NULL, -- 'SAVE', 'PUBLISH', 'INIT'
        payload_json NVARCHAR(MAX) NOT NULL,
        changed_by   NVARCHAR(128) NOT NULL,
        changed_at   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO
