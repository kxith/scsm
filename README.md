# Strategic Compliance Synthesis Model (SCSM) v4.0

This repository contains the software implementation, data models, calculators, and registries for the **Strategic Compliance Synthesis Model (SCSM) v4.0**, a sequential mixed-methods framework for transnational regulatory compliance written from a Global South / TWAIL standpoint.

Co-authored by **Hadrian Matshobo Tamele** (compliance/governance researcher) and **Keith Karabo Mahasha** (IT/systems engineer) in Johannesburg, South Africa.

## Project Overview

---

Multinational Enterprises (MNEs) face a structural trilemma: doctrinal legal mapping is jurisdictionally siloed, socio-legal empiricism lacks operational utility, and standard RegTech fails to synthesize conflicting geopolitical signals into defensible compliance architectures.

The SCSM bridges this gap by fusing epistemic pluralism with hard-law conflict resolution. It models and calculates the composite **Regulatory Fragmentation Index (RFI)** based on five key metrics:

- **Base Doctrinal Divergence (BDD)1**
- **Institutional Capacity Modifier (ICM)**
- **Extraterritorial Conflict Coefficient (ECC)**
- **Treaty Conflict Coefficient (TCC)**
- **ISDS Vulnerability Coefficient (ISDS)**
- **Power Asymmetry Index (PAI)**

## Repository Directory Structure

---

The repository is organized according to the following layout:

```text
scsm/
├── docs/                          # Project documentation, architectural specs, and guides
│   ├── architecture/              # System design models, data flow pipelines, and core methodologies
│   │   ├── overview/              # High-level system architecture and modular breakdown
│   │   └── data-flow.md           # Processing pipeline flow mapping (L1 ingestion to L4 registry)
│   ├── reference/                 # Technical references for APIs, CLI tools, and schemas
│   │   ├── api/                   # Developer API integrations and programmatic interfaces
│   │   └── cli.md                 # CLI command reference, arguments, and usage examples
│   └── guides/                    # Operational guidelines and developer procedures
│       ├── testing-strategy.md    # Unit testing protocols and HavenTech baseline replication
│       └── logging-and-monitoring.md # Observability, audit logging, and telemetry setup
├── data/                          # Structured data folders (ignored in git except schemas)
│   ├── raw/                       # L1 raw input data downloads
│   ├── snapshots/                 # L1 dated, immutable Parquet snapshots
│   ├── processed/                 # L2 Data processing outputs and ephemeral states
│   └── registry/                  # L4 Transparency Registry JSON/Parquet exports
├── output/                        # Dynamic runs, report generation, and visualizations
├── notebooks/                     # Colab and Jupyter notebooks for EDA and stress-tests
├── src/                           # Python source code
│   ├── __init__.py
│   ├── config.py                  # Auto-resolving cross-platform path manager
│   ├── ingestion/                 # L1 connectors (WGI, V-Dem, CPI, OpenSanctions)
│   │   ├── __init__.py
│   │   └── connectors.py
│   ├── database/                  # L2 Supabase (Postgres) schema, DuckDB compute references, schemas
│   │   ├── __init__.py
│   │   ├── schema.sql             # Supabase system of record schema (RLS, JSONB, identity)
│   │   └── duckdb_schema.sql      # DuckDB ephemeral schema
│   ├── engine/                    # L3 pure-function calculation modules (BDD, ICM, RFI, etc.)
│   │   ├── __init__.py
│   │   ├── metrics.py
│   │   └── validation.py          # Inter-coder kappa and criterion validity tests
│   └── registry/                  # L4 export engines and auditing logs
│       ├── __init__.py
│       └── export.py
└── tests/                         # Unit tests and regression checks (HavenTech baseline)
    ├── __init__.py
    └── test_engine.py
```

## Stack & Requirements

---

- **System of Record (OLTP):** [Supabase (PostgreSQL)](https://supabase.com/) (Handles auth, Row-Level Security, JSONB, structured data logic)
- **Compute Engine (OLAP):** [DuckDB](https://duckdb.org/) (Attached to Postgres via `postgres` extension for ephemeral, highly performant analytical runs)
- **Data Snapshot Format:** [Apache Parquet](https://parquet.apache.org/) (for immutable historical record auditing)
- **Language:** Python 3.10+
- **Primary Libraries:** `polars`, `pandas`, `numpy`, `pyarrow`, `duckdb`

## Configuration (`src/config.py`)

---

All file and database path resolutions are managed by the auto-resolving, frozen dataclasses defined in `src/config.py`.

The paths automatically resolve relative to the codebase root across operating systems (Windows, macOS/Darwin, Linux) and find OneDrive and local environments automatically:

```python
from src.config import PATHS

# Accessing resolved paths
print(PATHS.project_root)
print(PATHS.db_paths.duckdb_path)
```

---

## Action Thresholds

Calculated RFI scores determine operational strategies:

* **$\text{RFI} \le 30$:** Standardize compliance architectures.
* **$31 \le \text{RFI} \le 70$:** Localize and apply Private International Law (PIL) contractual ring-fencing.
* **$\text{RFI} > 70$ (or $\text{ECC} \ge 11$):** Escalate to the **Hierarchy of Conflict Resolution** (VCLT Article 30 treaty priority $\rightarrow$ UNGP human-rights baseline $\rightarrow$ documented board-approved Geopolitical Compliance Exception).
