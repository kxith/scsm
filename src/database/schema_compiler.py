
"""
Schema Compiler

This script compiles YAML schema files to JSON schema files, updating the last_updated date.

It scans a source directory of YAML schemas, updates the `last_updated` field inside the YAML
files to the current date using regular expressions, loads the YAML content, and writes the
corresponding JSON schema representations to a target directory.

Attributes:
    app (typer.Typer): The Typer CLI application instance.
    console (Console): The rich Console instance for colored output.
    BASE_DIR (str): Absolute path to the repository root directory.
    YAML_DIR (str): Path to the source directory containing YAML schema definitions.
    JSON_DIR (str): Path to the output directory for compiled JSON schemas.
"""

import os
import glob
import re
import json
import yaml
import datetime
import typer
from rich.console import Console
from rich.table import Table

app = typer.Typer(help="SCSM v4.0 Schema Compiler")
console = Console()

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
YAML_DIR = os.path.join(BASE_DIR, "data", "schemas", "yaml")
JSON_DIR = os.path.join(BASE_DIR, "data", "schemas", "json")

os.makedirs(JSON_DIR, exist_ok=True)

@app.command("compile")
def compile_schemas(files: list[str] = typer.Argument(None, help="List of YAML files to compile. If omitted, compiles all.")):
    """
    Compile YAML schemas to JSON schemas, updating the last_updated date.

    This command parses the specified YAML/YML files (or all files in the source YAML directory
    if none are specified), updates the `last_updated` date in the source files to today's date,
    and compiles them to JSON format in the output JSON directory.

    A summary table is printed to the console using the `rich` library at the end of execution.

    Args:
        files (list[str], optional): A list of YAML files to compile. Paths can be absolute
            or relative to the source YAML directory. If omitted or empty, all YAML/YML files
            in the source YAML directory will be compiled.

    Raises:
        typer.Exit: Raised when no YAML files are found to compile.
    """
    if not files:
        files = glob.glob(os.path.join(YAML_DIR, "*.yaml")) + glob.glob(os.path.join(YAML_DIR, "*.yml"))
    else:
        # If files are passed, resolve them either as absolute paths or relative to YAML_DIR
        resolved_files = []
        for f in files:
            if os.path.isabs(f):
                resolved_files.append(f)
            else:
                resolved_files.append(os.path.join(YAML_DIR, f))
        files = resolved_files

    if not files:
        console.print("[orange]No YAML files found to compile.[/orange]")
        raise typer.Exit()

    table = Table(title="Schema Compilation Report")
    table.add_column("Status", justify="center")
    table.add_column("Source File", style="cyan")
    table.add_column("Output File", style="green")
    table.add_column("Details")

    success_count = 0
    fail_count = 0
    today_str = datetime.date.today().isoformat()
    
    # Regex to match last_updated with optional quotes
    date_pattern = re.compile(r'^(last_updated\s*:\s*)(["\']?)\d{4}-\d{2}-\d{2}\2', re.MULTILINE)

    for filepath in files:
        if not os.path.exists(filepath):
            table.add_row("[red]:cross_mark: FAILURE[/red]", os.path.basename(filepath), "-", "File not found")
            fail_count += 1
            continue

        filename = os.path.basename(filepath)
        json_filename = filename.replace(".yaml", ".json").replace(".yml", ".json")
        json_filepath = os.path.join(JSON_DIR, json_filename)

        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            # 1. Surgical text replacement for last_updated
            new_content, count = date_pattern.subn(rf'\g<1>\g<2>{today_str}\g<2>', content)
            
            # 2. Write back to YAML if changed
            if count > 0 and new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                content = new_content

            # 3. Parse YAML
            schema_data = yaml.safe_load(content)

            # 4. Serialize to JSON
            with open(json_filepath, 'w', encoding='utf-8') as f:
                json.dump(schema_data, f, indent=2, ensure_ascii=False)

            table.add_row("[yellow2]SUCCESS[/yellow2]", filename, json_filename, "Compiled successfully")
            success_count += 1
        except Exception as e:
            table.add_row("[red]:cross_mark: FAILURE[/red]", filename, json_filename, str(e))
            fail_count += 1

    console.print(table)
    console.print(f"Total: {success_count + fail_count} | [yellow2]Success: {success_count}[/yellow2] | [red]Failed: {fail_count}[/red]")

if __name__ == "__main__":
    app()
