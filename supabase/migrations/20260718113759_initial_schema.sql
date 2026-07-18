-- ============================================================================
-- SCSM v4.0 — Database Schema (Supabase / Postgres — SYSTEM OF RECORD)
-- Strategic Compliance Synthesis Model
-- Authors: Hadrian Matshobo Tamele, Keith Karabo Mahasha
--
-- This is the persisted, authoritative store. Every table here is the
-- single source of truth for its entity — DuckDB (see duckdb_schema.sql /
-- pipeline/pair_metrics_runner.py) attaches to this database live via the
-- `postgres` extension for compute, and writes results back here. DuckDB
-- itself holds no persisted state.
--
-- Naming convention: Postgres standard — snake_case, plural tables,
-- singular columns, `id` PK, `{table}_id` FK, `_at` timestamps, `_date` dates.
--
-- Changes from the DuckDB-era schema:
--   1. CREATE SEQUENCE + nextval() -> GENERATED ALWAYS AS IDENTITY (idiomatic
--      Postgres/Supabase; DuckDB's sequence syntax was a workaround, not the
--      preferred form on real Postgres).
--   2. *_weights_json VARCHAR -> JSONB (indexable, queryable with ->, and
--      validated as real JSON at the type level instead of an opaque string).
--   3. audit_logs.decided_by VARCHAR -> UUID REFERENCES auth.users(id).
--      This is the single biggest defensibility upgrade in the migration:
--      a free-text name is not an audit trail, an authenticated actor is.
--   4. Row Level Security enabled on every table, with policy stubs marked
--      TODO — governance-sensitive tables (weight_sets, blocking_statutes)
--      get a tighter default than read-only reference tables.
--
-- Design principle unchanged: auditability over cleverness. Every metric
-- column traces to a named formula term (Section 4.2 of the Mathematics
-- Toolkit). Provisional constants are marked inline via `status` columns.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- jurisdictions — the base entity. ISO 3166-1 alpha-3 as the natural key.
-- ----------------------------------------------------------------------------
CREATE TABLE jurisdictions (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jur_code            VARCHAR(3) NOT NULL,          -- ISO 3166-1 alpha-3
    name                VARCHAR NOT NULL,
    region              VARCHAR,
    global_south_flag   BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_jurisdictions_jur_code UNIQUE (jur_code)
);

-- ----------------------------------------------------------------------------
-- dimensions — regulatory dimensions coded in doctrinal mapping (Stage 1).
-- Seeded from the 9 HavenTech-style dimensions (seeds/dimensions.csv).
-- ----------------------------------------------------------------------------
CREATE TABLE dimensions (
    id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name    VARCHAR NOT NULL,
    CONSTRAINT uq_dimensions_name UNIQUE (name)
);

-- ----------------------------------------------------------------------------
-- sources — every external data source, for citation discipline in the
-- Transparency Registry (L4). Seeded from seeds/sources.csv.
-- ----------------------------------------------------------------------------
CREATE TABLE sources (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                VARCHAR NOT NULL,
    url                 VARCHAR,
    retrieval_method    VARCHAR,       -- e.g. 'bulk_download', 'api', 'scraper',
                                       -- 'manual_compiled', 'mcp_server', 'unverified'
    license             VARCHAR,
    target_metric       VARCHAR,       -- which metric/table this source feeds —
                                       -- so the registry itself explains why a
                                       -- row exists
    verified            BOOLEAN NOT NULL DEFAULT FALSE,  -- FALSE = access details
                                                          -- not yet confirmed; do
                                                          -- not build a connector
                                                          -- against an unverified
                                                          -- source
    CONSTRAINT uq_sources_name UNIQUE (name)
);

-- ----------------------------------------------------------------------------
-- doctrinal_scores — raw D_ij inputs feeding BDD (Base Doctrinal Divergence).
-- Grain: jurisdiction x dimension x source x time.
-- ----------------------------------------------------------------------------
CREATE TABLE doctrinal_scores (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jurisdiction_id     BIGINT NOT NULL REFERENCES jurisdictions(id),
    dimension_id        BIGINT NOT NULL REFERENCES dimensions(id),
    source_id           BIGINT NOT NULL REFERENCES sources(id),
    score               DECIMAL(4,2) NOT NULL CHECK (score BETWEEN 0 AND 10),
    as_of_date          DATE NOT NULL,
    CONSTRAINT uq_doctrinal_scores_natural
        UNIQUE (jurisdiction_id, dimension_id, source_id, as_of_date)
);

-- ----------------------------------------------------------------------------
-- capacity_indicators — feeds CapacityScore -> ICM (Institutional Capacity
-- Modifier). Weighted 0.25/0.25/0.20/0.20/0.10 across the five indicators
-- per Mathematics Toolkit Section 4.2.x (hard-coded weights, NOT provisional
-- — these are specified in the toolkit, unlike ISDS/EPF constants below).
-- ----------------------------------------------------------------------------
CREATE TABLE capacity_indicators (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jurisdiction_id     BIGINT NOT NULL REFERENCES jurisdictions(id),
    source_id           BIGINT NOT NULL REFERENCES sources(id),
    indicator           VARCHAR NOT NULL CHECK (indicator IN
                            ('reg_quality', 'rule_law', 'political_will',
                             'judicial_indep', 'corruption_perc')),
    score               DECIMAL(4,2) NOT NULL CHECK (score BETWEEN 0 AND 10),
    as_of_date          DATE NOT NULL,
    CONSTRAINT uq_capacity_indicators_natural
        UNIQUE (jurisdiction_id, indicator, source_id, as_of_date)
);

-- ----------------------------------------------------------------------------
-- weight_sets — versioned Delphi panel outputs. Never mutate a row in place;
-- a new panel round is a new id. `status` distinguishes illustrative
-- placeholder weights from panel-validated ones. Weight vectors stored as
-- JSONB (was VARCHAR under DuckDB) — queryable and type-validated.
-- ----------------------------------------------------------------------------
CREATE TABLE weight_sets (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    panel_round         INTEGER NOT NULL,
    iqr                 DECIMAL(4,2),                  -- consensus check, target <= 2.0
    status              VARCHAR NOT NULL DEFAULT 'illustrative'
                            CHECK (status IN ('illustrative', 'panel_validated')),
    consensus_date      DATE,
    -- BDD per-dimension weights (w_i), e.g. {"1": 0.15, "2": 0.10, ...}
    bdd_weights         JSONB,
    -- PAI weights (w1/w2/w3), e.g. {"mad": 0.4, "cfd": 0.35, "ssi": 0.25}
    pai_weights         JSONB
);

-- ----------------------------------------------------------------------------
-- jurisdiction_pairs — the atomic unit of analysis (home j x host k).
-- Every downstream metric (BDD, ECC, TCC, ISDS, PAI, RFI) is defined at
-- this grain, not at the single-jurisdiction level (ICM is the exception,
-- computed per host k and looked up, not stored per-pair).
-- ----------------------------------------------------------------------------
CREATE TABLE jurisdiction_pairs (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    home_jurisdiction_id    BIGINT NOT NULL REFERENCES jurisdictions(id),
    host_jurisdiction_id    BIGINT NOT NULL REFERENCES jurisdictions(id),
    CONSTRAINT uq_jurisdiction_pairs_pair
        UNIQUE (home_jurisdiction_id, host_jurisdiction_id),
    CONSTRAINT ck_jurisdiction_pairs_distinct
        CHECK (home_jurisdiction_id <> host_jurisdiction_id)
);

-- ----------------------------------------------------------------------------
-- blocking_statutes — curated, versioned lookup feeding ECC (Extraterritorial
-- Conflict Coefficient). Scored ONLY per the Triad-Conflict Disambiguation
-- Rule: contradictory primary mandates (must-do vs. must-not-do) at the
-- firm level. A maintained artifact, not a data feed — needs an owner and
-- update cadence, versioned in lockstep with `matrix_version`.
-- ----------------------------------------------------------------------------
CREATE TABLE blocking_statutes (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matrix_version          VARCHAR NOT NULL,          -- e.g. 'v2026.1'
    home_jurisdiction_id    BIGINT NOT NULL REFERENCES jurisdictions(id),
    host_jurisdiction_id    BIGINT NOT NULL REFERENCES jurisdictions(id),
    statute_citation        VARCHAR NOT NULL,          -- e.g. 'MOFCOM Order No. 1'
    severity_score          DECIMAL(4,2) NOT NULL CHECK (severity_score BETWEEN 0 AND 15),
    status                  VARCHAR NOT NULL DEFAULT 'provisional'
                                CHECK (status IN ('provisional', 'panel_validated')),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- subnational_overlays — sub-national customary/tenure overlap risk data
-- from LegalGapDB / Legal Atlas. Grain is deliberately NOT jurisdiction-pair:
-- region-level within host k, MAX-aggregated up into epf_assessments,
-- scoped to the MNE's declared operational footprint where available.
-- ----------------------------------------------------------------------------
CREATE TABLE subnational_overlays (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jurisdiction_id     BIGINT NOT NULL REFERENCES jurisdictions(id),
    source_id           BIGINT NOT NULL REFERENCES sources(id),
    region              VARCHAR NOT NULL,              -- sub-national identifier
    overlap_risk        DECIMAL(4,2) NOT NULL CHECK (overlap_risk BETWEEN 0 AND 10),
    as_of_date          DATE NOT NULL
);

-- ----------------------------------------------------------------------------
-- pair_metrics — the output table. One row per computation run; never
-- overwritten. isds_raw and isds_adjusted are BOTH stored so the
-- DefenseMultiplier discount (Triad-Conflict Disambiguation Rule, guard
-- clause) is visible and reversible, not silently baked into a single
-- number. Written by DuckDB's compute engine via the postgres ATTACH.
-- ----------------------------------------------------------------------------
CREATE TABLE pair_metrics (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jurisdiction_pair_id    BIGINT NOT NULL REFERENCES jurisdiction_pairs(id),
    weight_set_id           BIGINT NOT NULL REFERENCES weight_sets(id),

    bdd                     DECIMAL(5,2) NOT NULL CHECK (bdd BETWEEN 0 AND 10),
    icm                     DECIMAL(5,2) NOT NULL CHECK (icm BETWEEN 1.0 AND 3.0),
    ecc                     DECIMAL(5,2) NOT NULL CHECK (ecc BETWEEN 0 AND 15),
    tcc                     DECIMAL(5,2) NOT NULL CHECK (tcc BETWEEN 0 AND 10),

    -- ISDS: raw = min(10, formula); adjusted = raw * DefenseMultiplier
    -- (0.5, PROVISIONAL) applied only when an ECC conflict has triggered
    -- the Hierarchy of Conflict Resolution for this pair.
    isds_raw                    DECIMAL(5,2) NOT NULL CHECK (isds_raw BETWEEN 0 AND 10),
    isds_adjusted                DECIMAL(5,2) NOT NULL CHECK (isds_adjusted BETWEEN 0 AND 10),
    defense_multiplier_applied  BOOLEAN NOT NULL DEFAULT FALSE,

    pai                     DECIMAL(5,2) NOT NULL CHECK (pai BETWEEN 0 AND 10),

    raw_rfi                 DECIMAL(6,2) NOT NULL,      -- (BDD*ICM)+ECC+TCC+ISDS+PAI
    rfi                     DECIMAL(5,2) NOT NULL CHECK (rfi BETWEEN 0 AND 100),

    computed_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- epf_assessments — Epistemic Pluralism Flag. Deliberately separate from
-- pair_metrics (Separation of Concerns): EPF is a proposed Section 2
-- extension, updates on a different cadence than RFI (customary/tenure
-- data moves slower than treaty/case data), and must not be silently
-- overwritten every time RFI recomputes for unrelated reasons.
-- Grain: jurisdiction (host k), not jurisdiction-pair — EPF gates the
-- action threshold for any MNE operating in k, regardless of home j.
-- ----------------------------------------------------------------------------
CREATE TABLE epf_assessments (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jurisdiction_id         BIGINT NOT NULL REFERENCES jurisdictions(id),
    epf_level               DECIMAL(4,2) NOT NULL CHECK (epf_level BETWEEN 0 AND 10),
    epf_tier                VARCHAR NOT NULL CHECK (epf_tier IN ('green', 'amber', 'red')),
    footprint_scoped        BOOLEAN NOT NULL DEFAULT FALSE,  -- TRUE if MNE operational
                                                              -- regions were declared;
                                                              -- FALSE = national MAX
                                                              -- fallback
    rationale               VARCHAR,
    computed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_epf_tier_matches_level CHECK (
        (epf_tier = 'green' AND epf_level BETWEEN 0 AND 3.0) OR
        (epf_tier = 'amber' AND epf_level BETWEEN 3.1 AND 7.0) OR
        (epf_tier = 'red'   AND epf_level BETWEEN 7.1 AND 10)
    )
);

-- ----------------------------------------------------------------------------
-- audit_logs — the Ethical Compliance Threshold / Transparency Registry
-- artifact (Stage 3). Tied to a SPECIFIC pair_metrics row (not just a
-- jurisdiction pair) so a decision cites the exact RFI value, weight set,
-- and EPF context in force at decision time.
--
-- `decided_by` is a real foreign key to auth.users — the single biggest
-- defensibility upgrade in this migration. Under DuckDB this was a
-- free-text VARCHAR; a name typed into a field is not an audit trail,
-- an authenticated Supabase user is.
-- ----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pair_metric_id      BIGINT NOT NULL REFERENCES pair_metrics(id),
    epf_assessment_id   BIGINT REFERENCES epf_assessments(id),   -- nullable: not
                                                                  -- every decision
                                                                  -- involves an EPF
                                                                  -- gate
    action              VARCHAR NOT NULL CHECK (action IN
                            ('standardise', 'localise_ringfence', 'escalate_hierarchy')),
    rfi_at_decision     DECIMAL(5,2) NOT NULL,
    decided_by          UUID NOT NULL REFERENCES auth.users(id),
    rationale           VARCHAR,
    decided_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- Indexes — the joins this schema will actually run most often.
-- ----------------------------------------------------------------------------
CREATE INDEX idx_doctrinal_scores_jurisdiction_id ON doctrinal_scores(jurisdiction_id);
CREATE INDEX idx_capacity_indicators_jurisdiction_id ON capacity_indicators(jurisdiction_id);
CREATE INDEX idx_jurisdiction_pairs_home ON jurisdiction_pairs(home_jurisdiction_id);
CREATE INDEX idx_jurisdiction_pairs_host ON jurisdiction_pairs(host_jurisdiction_id);
CREATE INDEX idx_blocking_statutes_pair
    ON blocking_statutes(home_jurisdiction_id, host_jurisdiction_id);
CREATE INDEX idx_subnational_overlays_jurisdiction_id ON subnational_overlays(jurisdiction_id);
CREATE INDEX idx_pair_metrics_pair_id ON pair_metrics(jurisdiction_pair_id);
CREATE INDEX idx_pair_metrics_weight_set_id ON pair_metrics(weight_set_id);
CREATE INDEX idx_epf_assessments_jurisdiction_id ON epf_assessments(jurisdiction_id);
CREATE INDEX idx_audit_logs_pair_metric_id ON audit_logs(pair_metric_id);
CREATE INDEX idx_audit_logs_decided_by ON audit_logs(decided_by);

-- ============================================================================
-- Row Level Security — enabled on every table. Policies below are STUBS:
-- they establish the shape of the access model (reference data readable by
-- any authenticated user; governance-sensitive writes restricted to an
-- admin role) but the actual role/claim check needs Hadrian/Keith sign-off
-- before this goes anywhere near production data. Treat every `TODO` as a
-- blocking item, not a default to ship silently.
--
-- Assumes a custom claim `user_role` set in the Supabase JWT (via a
-- `raw_app_meta_data` field or a `profiles` table + trigger — not yet
-- decided). Replace `auth.jwt() ->> 'user_role'` with whatever the actual
-- role-resolution mechanism ends up being.
-- ============================================================================

ALTER TABLE jurisdictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE dimensions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctrinal_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE capacity_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE weight_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE jurisdiction_pairs ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocking_statutes ENABLE ROW LEVEL SECURITY;
ALTER TABLE subnational_overlays ENABLE ROW LEVEL SECURITY;
ALTER TABLE pair_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE epf_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- -- Reference / staging data: any authenticated user may read.
-- -- TODO: confirm read access should be this broad before enabling.
-- CREATE POLICY read_authenticated ON jurisdictions
--     FOR SELECT USING (auth.role() = 'authenticated');
-- (repeat pattern for dimensions, sources, doctrinal_scores,
--  capacity_indicators, jurisdiction_pairs, subnational_overlays,
--  pair_metrics)

-- -- Governance-sensitive tables: writes restricted to an admin role.
-- -- TODO: define the actual admin claim/mechanism with Hadrian/Keith.
-- CREATE POLICY admin_write ON weight_sets
--     FOR INSERT WITH CHECK (auth.jwt() ->> 'user_role' = 'admin');
-- CREATE POLICY admin_write ON blocking_statutes
--     FOR INSERT WITH CHECK (auth.jwt() ->> 'user_role' = 'admin');

-- -- audit_logs: any authenticated user may insert THEIR OWN decision;
-- -- no one may update or delete a past entry (immutability = the point
-- -- of an audit trail). TODO: confirm no UPDATE/DELETE policy is ever
-- -- added for this table, by anyone, including admins.
-- CREATE POLICY insert_own_decision ON audit_logs
--     FOR INSERT WITH CHECK (decided_by = auth.uid());
-- CREATE POLICY read_authenticated ON audit_logs
--     FOR SELECT USING (auth.role() = 'authenticated');