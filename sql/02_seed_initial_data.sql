-- ============================================================================
-- LUKB Investment Office Hub (v2) – Initiales JSON-Seed-Dokument (MS SQL Server)
-- ============================================================================

DELETE FROM dbo.io_hub_state WHERE doc_key = 'hub_main_payload';

INSERT INTO dbo.io_hub_state (doc_key, schema_ver, payload_json, updated_by, version)
VALUES (
    'hub_main_payload',
    2,
    N'{
      "meta": {
        "title": "LUKB Investment Office – Markt- & Konjunkturüberblick",
        "committee_date": "2026-10-30",
        "updated_at": "2026-11-01 12:20:00",
        "updated_by": "Dr. M. Kaufmann (CIO)"
      },
      "central_banks": {
        "commentary": "Die grossen Notenbanken befinden sich in einer fortgeschrittenen Phase der geldpolitischen Normalisierung. Während die SNB bei einem Leitzins von 0.50 % verharrt und auf Sicht von 12 Monaten keine Anpassung signalisiert, erwarten wir von der US-Notenbank (Fed) und der EZB noch schrittweise Zinssenkungen in Richtung des neutralen Zinsniveaus. Die Bank of Japan (BoJ) setzt ihren vorsichtigen Zinserhöhungspfad fort.",
        "rows": [
          {"id": "SNB", "name": "SNB", "full_name": "Schweizerische Nationalbank",           "currency": "CHF", "current": "0.50",      "m3": "0.50",      "m12": "0.50",      "comment": "SNB sieht aktuell keinen Bedarf für Negativzinsen."},
          {"id": "FED", "name": "Fed", "full_name": "US Federal Reserve (Target Range)",     "currency": "USD", "current": "4.25-4.50", "m3": "4.00-4.25", "m12": "3.50-3.75", "comment": "Schrittweise Senkung des Zielbands in Richtung neutrales Niveau."},
          {"id": "EZB", "name": "EZB", "full_name": "Europäische Zentralbank (Einlagesatz)", "currency": "EUR", "current": "2.50",      "m3": "2.25",      "m12": "2.00",      "comment": "Nachlassende Dienstleistungsinflation erlaubt weitere Schritte."},
          {"id": "BOE", "name": "BoE", "full_name": "Bank of England (Bank Rate)",           "currency": "GBP", "current": "4.00",      "m3": "3.75",      "m12": "3.25",      "comment": "Vorsichtiger Lockerungspfad angesichts robuster Lohnentwicklung."},
          {"id": "BOJ", "name": "BoJ", "full_name": "Bank of Japan (Overnight Call Rate)",   "currency": "JPY", "current": "0.50",      "m3": "0.75",      "m12": "1.00",      "comment": "Graduelle Zinsnormalisierung bei anhaltendem Lohnwachstum."}
        ]
      },
      "macro": {
        "base_year": 2026,
        "commentary": "Die Weltwirtschaft wächst nahe ihrem langfristigen Potenzial von knapp über 3 %. In der Schweiz stützen der private Konsum und die robuste Pharmabranche das Wachstum, während die Inflation mit 0.8 % im Jahr 2026 tief im Zielband der SNB verankert bleibt. Indien führt das Wachstum der grossen Volkswirtschaften weiter an.",
        "rows": [
          {"id": "CH", "country": "Schweiz",    "code": "CH", "gdp_t_minus_1": 1.3, "gdp_t": 1.5, "gdp_t_plus_1": 1.7, "cpi_t_minus_1": 1.1, "cpi_t": 0.8, "cpi_t_plus_1": 1.0, "comment": ""},
          {"id": "EU", "country": "Euroraum",   "code": "EU", "gdp_t_minus_1": 0.9, "gdp_t": 1.2, "gdp_t_plus_1": 1.4, "cpi_t_minus_1": 2.2, "cpi_t": 1.9, "cpi_t_plus_1": 2.0, "comment": ""},
          {"id": "UK", "country": "UK",         "code": "GB", "gdp_t_minus_1": 1.1, "gdp_t": 1.3, "gdp_t_plus_1": 1.4, "cpi_t_minus_1": 2.6, "cpi_t": 2.2, "cpi_t_plus_1": 2.0, "comment": ""},
          {"id": "US", "country": "USA",        "code": "US", "gdp_t_minus_1": 2.5, "gdp_t": 2.1, "gdp_t_plus_1": 1.9, "cpi_t_minus_1": 2.8, "cpi_t": 2.4, "cpi_t_plus_1": 2.1, "comment": ""},
          {"id": "JP", "country": "Japan",      "code": "JP", "gdp_t_minus_1": 0.7, "gdp_t": 1.0, "gdp_t_plus_1": 0.9, "cpi_t_minus_1": 2.5, "cpi_t": 2.0, "cpi_t_plus_1": 1.8, "comment": ""},
          {"id": "BR", "country": "Brasilien",  "code": "BR", "gdp_t_minus_1": 2.9, "gdp_t": 2.2, "gdp_t_plus_1": 2.4, "cpi_t_minus_1": 4.4, "cpi_t": 4.1, "cpi_t_plus_1": 3.8, "comment": ""},
          {"id": "RU", "country": "Russland",   "code": "RU", "gdp_t_minus_1": 3.4, "gdp_t": 1.5, "gdp_t_plus_1": 1.2, "cpi_t_minus_1": 8.1, "cpi_t": 6.8, "cpi_t_plus_1": 5.5, "comment": ""},
          {"id": "IN", "country": "Indien",     "code": "IN", "gdp_t_minus_1": 6.8, "gdp_t": 6.5, "gdp_t_plus_1": 6.6, "cpi_t_minus_1": 4.7, "cpi_t": 4.3, "cpi_t_plus_1": 4.1, "comment": ""},
          {"id": "CN", "country": "China",      "code": "CN", "gdp_t_minus_1": 4.8, "gdp_t": 4.5, "gdp_t_plus_1": 4.2, "cpi_t_minus_1": 0.6, "cpi_t": 1.1, "cpi_t_plus_1": 1.5, "comment": ""},
          {"id": "WL", "country": "Welt",       "code": "WL", "gdp_t_minus_1": 3.2, "gdp_t": 3.1, "gdp_t_plus_1": 3.2, "cpi_t_minus_1": 4.1, "cpi_t": 3.4, "cpi_t_plus_1": 3.1, "comment": ""}
        ]
      },
      "allocation": {
        "commentary": "In unserer taktischen Vermögensallokation bevorzugen wir Sachwerte mit verlässlichen Cashflows. Aktien, Schweizer Immobilien und Gold sind übergewichtet, finanziert über eine Untergewichtung der niedrig verzinsten Liquidität.",
        "rows": [
          {"id": "CASH",  "asset_class": "Cash",         "stance": -1, "change":  0, "forecast_12m": 0.5, "comment": "Nach Zinssenkungen am kurzen Ende unattraktive Realverzinsung in CHF."},
          {"id": "BONDS", "asset_class": "Obligationen", "stance":  0, "change":  1, "forecast_12m": 2.1, "comment": "Fokus auf mittlere Duration und erstklassige Unternehmensanleihen (IG)."},
          {"id": "EQ",    "asset_class": "Aktien",       "stance":  1, "change":  0, "forecast_12m": 6.8, "comment": "Solides Gewinnwachstum; Fokus auf Qualitätswerte Schweiz und USA."},
          {"id": "RE",    "asset_class": "Immobilien",   "stance":  1, "change":  1, "forecast_12m": 5.2, "comment": "Tiefes Zinsumfeld und hohes Mietwachstum stützen Schweizer Immobilienfonds."},
          {"id": "GOLD",  "asset_class": "Gold",         "stance":  1, "change":  0, "forecast_12m": 5.5, "comment": "Strukturelle Käufe der Zentralbanken und geopolitische Portfolioversicherung."},
          {"id": "COMM",  "asset_class": "Rohstoffe",    "stance":  0, "change": -1, "forecast_12m": 1.5, "comment": "Industriemetalle unterstützt, Energiesektor durch reichliches Angebot gedeckelt."}
        ]
      }
    }',
    'Dr. M. Kaufmann (CIO)',
    1
);
GO
