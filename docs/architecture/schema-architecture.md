
# Schema Architecture & Metadata Specification (SCSM v4.0)

This document outlines the design, schema fields, compilation lifecycle, and metadata standards of the SCSM v4.0 schema registry. It serves as the master documentation for the human-source (YAML) to machine-artifact (JSON) schema compilation system.

---

## 1. Architectural Overview

To ensure data structures are highly readable for humans (for governance, compliance audits, and collaborative review) while remaining easily readable for code pipelines, the database schema definition uses a dual-representation paradigm:

```
    [ human developer ]
             │
             ▼
┌─────────────────────────┐
│  data/schemas/yaml/*.   │ ◄─── YAML Source (Human written, has rich comments)
└────────────┬────────────┘
             │
             │ (schema_compiler.py compile --write-back)
             ▼
┌─────────────────────────┐
│  data/schemas/json/*.   │ ◄─── JSON Output (Machine consumed, stripped of comments)
└─────────────────────────┘
```

1. **Source of Truth (YAML):** Written by developers in `data/schemas/yaml/`. Features rich commenting, sub-section divisions (`# ! ── ...`), and detailed formatting.
2. **Compiler Lifecycle:** The CLI script `src/database/schema_compiler.py` is executed. It automatically updates the schema's `last_updated` field in both files and generates the clean JSON output in `data/schemas/json/`.
3. **Machine Consumption (JSON):** DuckDB loaders, validation models (Pydantic/Pandera), and the public Transparency Registry consume the JSON schema files.

---

## 2. Directory Structure

```text
scsm/
├── data/
│   └── schemas/
│       ├── yaml/       # Source YAML files (committed to git)
│       └── json/       # Compiled JSON targets (committed to git)
└── src/
    └── database/
        └── schema_compiler.py   # Typer CLI compiler script
```

---

## 3. Metadata Specification (The Schema of Schemas)

Every schema file must define the following metadata envelope:

### 3.1 Header Attributes


| Key                  | Type   | Allowed Values                                                                                          | Purpose                                                                      |
| :--------------------- | :------- | :-------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------- |
| `domain_key`         | String | `scsm`                                                                                                  | Identifies the architectural domain.                                         |
| `table_name`         | String | *e.g., `jurisdictions`*                                                                                 | Name of the database table (required if`storage_format` is `table`).         |
| `schema_name`        | String | *e.g., `bdd_weights`*                                                                                   | Name of the payload schema (required if`storage_format` is `json_document`). |
| `table_type`         | String | `base_entity`, `fact`, `metadata`, `log`                                                                | Categorizes the table classification.                                        |
| `type`               | String | `struct`                                                                                                | Data type structure.                                                         |
| `version`            | String | *e.g., `"1.0"`*                                                                                         | Version of the schema layout itself (distinct from SCSM model version).      |
| `schema_category`    | String | `field_metadata`                                                                                        | Categorizes schema definitions.                                              |
| `architectural_role` | String | `core_ingestion_layer`, `relational_pair_layer`, `epistemic_pluralism_layer`, `computation_audit_layer` | Defines placement in the L1-L4 pipeline (Data Architecture Spec Section 2).  |
| `storage_format`     | String | `table`, `json_document`                                                                                | Declares physical representation (DB table vs. nested JSON payload).         |
| `description`        | String | Multi-line text block                                                                                   | Broad overview of the table/schema purpose.                                  |
| `last_updated`       | String | `YYYY-MM-DD`                                                                                            | Date of last modification (updated automatically by compiler).               |
| `update_frequency`   | String | `Static`, `Batch`, `Dynamic`                                                                            | Declares data mutation frequency.                                            |

### 3.2 Field Definitions (`fields`)

The `fields` array contains a list of column or key definitions. Each field consists of:

* `name` (String, required): Physical column/key name.
* `type` (String, required): DuckDB/Postgres data type (e.g., `BIGINT`, `VARCHAR(3)`, `DECIMAL(4,2)`).
* `nullable` (Boolean, required): Declares if `NULL` values are permitted.
* `default_value` (String, optional): Default value if omitted.
* `metadata` (Object, required):
  * `description` (String, required): Human-readable explanation.
  * `constraint` (String, optional): SQL constraint (e.g., `PRIMARY_KEY`, `NATURAL_KEY`, custom CHECK clauses).
  * `name_variations` (List of Strings, optional): Synonyms for parsing and data ingestion mapping.
  * `example` (String/Any, optional): Illustrative value.
  * `note` (String, optional): Engineering warning, fallback rules, or operational notes.
  * `allowed_values` (List of Strings, optional): Enum-style constraint.

---

## 4. Compilation & Date Write-Back Mechanics

To maintain formatting, inline comments, and code aesthetics, the compiler implements **Option B: Surgical Text Replacement**.

### 4.1 The Write-Back Process

1. Read the target `.schema.yaml` file as raw text.
2. Locate the line declaring the update date at the root of the file:
   `last_updated: "YYYY-MM-DD"` (supporting optional single, double, or no quotes).
3. Replace the date with the current system date (`datetime.date.today().isoformat()`).
4. Write the modified raw text back to `.schema.yaml` (preserving all comments and line spacing).

### 4.2 The Compilation Process

1. Parse the updated text using `yaml.safe_load(updated_text)`.
2. Convert the resulting dictionary to a serialized JSON string:
   `json.dumps(schema, indent=2, ensure_ascii=False)`.
3. Save the serialized string to the matching filename in `data/schemas/json/`.

---

## 5. CLI Execution Guide

The `schema_compiler.py` script is built using `typer` and `rich` for structured logging.

### 5.1 Batch Compile (All Files)

```bash
python src/database/schema_compiler.py compile
```

*Processes all `.yaml` and `.yml` files in the source directory.*

### 5.2 Target Compile (Selected Files)

```bash
python src/database/schema_compiler.py compile jurisdictions.schema.yaml pair_metrics.schema.yaml
```

*Processes only the specified files.*

### 5.3 Rich Output Report

The compiler outputs a structured console table highlighting:

* Execution Status (Success/Failure)
* Source File name
* Output File name
* Status Details (Error lines or confirmation messages)
* Running totals of successful and failed files.
