#!/bin/bash
#
# run_dali_native.sh - Native ARM64 DALI structural alignment wrapper
#
# This script provides a convenient interface to DaliLite.v5 compiled
# natively for Apple Silicon (M1/M2/M3) Macs.
#
# IMPORTANT: Array sizes have been reduced for macOS ARM64 compatibility:
#   - maxprot: 10000 (from 1000000) - max structures per list
#   - maxres: 2000 (from 5000) - max residues per structure
#
# Usage:
#   run_dali_native.sh import <pdb_file> <pdb_id> <dat_dir>
#   run_dali_native.sh pairwise <query_list> <db_list> <dat_dir>
#   run_dali_native.sh matrix <structure_list> <dat_dir>
#   run_dali_native.sh search <query_list> <db_list> <dat_dir>
#
# Examples:
#   # Import a PDB file
#   run_dali_native.sh import structure.pdb MYID ./DAT
#
#   # Pairwise alignment (structures must be imported first)
#   run_dali_native.sh pairwise query.txt db.txt ./DAT
#
#   # All-against-all matrix
#   run_dali_native.sh matrix structures.txt ./DAT
#

set -e

# DALI installation directory
DALI_DIR="${DALI_DIR:-/Users/mukshudahamed/claude_rotifer/rotifer/lib/DaliLite.v5}"

# Check DALI installation
if [[ ! -d "$DALI_DIR" ]]; then
    echo "Error: DALI directory not found: $DALI_DIR"
    echo "Set DALI_DIR environment variable to point to DaliLite.v5 installation"
    exit 1
fi

# Check binaries
for bin in import.pl dali.pl serialcompare dsspcmbi; do
    if [[ ! -x "$DALI_DIR/bin/$bin" ]]; then
        echo "Error: Required binary not found: $DALI_DIR/bin/$bin"
        exit 1
    fi
done

usage() {
    cat << EOF
Native ARM64 DALI Structural Alignment Wrapper

Usage:
  $(basename $0) import <pdb_file> <pdb_id> <dat_dir>
      Import a PDB file into DALI format

  $(basename $0) pairwise <query_list> <db_list> <dat_dir>
      Run pairwise structural alignment

  $(basename $0) matrix <structure_list> <dat_dir>
      Run all-against-all comparison

  $(basename $0) search <query_list> <db_list> <dat_dir>
      Run database search

Arguments:
  pdb_file       - PDB format structure file
  pdb_id         - 4-character identifier for the structure
  dat_dir        - Directory for DALI .dat files
  query_list     - File containing query structure IDs (one per line)
  db_list        - File containing database structure IDs (one per line)
  structure_list - File containing all structure IDs for matrix comparison

Environment:
  DALI_DIR       - Path to DaliLite.v5 installation
                   (default: /Users/mukshudahamed/claude_rotifer/rotifer/lib/DaliLite.v5)

Limitations (macOS ARM64 build):
  - Maximum 10,000 structures per query/database list
  - Maximum 2,000 residues per structure

Output:
  - <query_id>.txt  - Alignment results in text format
  - <query_id>.html - Alignment results in HTML format
  - <query_id>.dccp - Detailed comparison file

Examples:
  # Import structures
  $(basename $0) import protein1.pdb P001 ./DAT
  $(basename $0) import protein2.pdb P002 ./DAT

  # Run pairwise alignment
  echo "P001A" > query.txt
  echo "P002A" > db.txt
  $(basename $0) pairwise query.txt db.txt ./DAT

EOF
    exit 1
}

cmd_import() {
    local pdb_file="$1"
    local pdb_id="$2"
    local dat_dir="$3"

    if [[ -z "$pdb_file" || -z "$pdb_id" || -z "$dat_dir" ]]; then
        echo "Error: import requires pdb_file, pdb_id, and dat_dir"
        usage
    fi

    if [[ ! -f "$pdb_file" ]]; then
        echo "Error: PDB file not found: $pdb_file"
        exit 1
    fi

    mkdir -p "$dat_dir"

    echo "Importing $pdb_file as $pdb_id..."
    "$DALI_DIR/bin/import.pl" --pdbfile "$pdb_file" --pdbid "$pdb_id" --dat "$dat_dir" --clean
}

cmd_pairwise() {
    local query_list="$1"
    local db_list="$2"
    local dat_dir="$3"

    if [[ -z "$query_list" || -z "$db_list" || -z "$dat_dir" ]]; then
        echo "Error: pairwise requires query_list, db_list, and dat_dir"
        usage
    fi

    if [[ ! -f "$query_list" ]]; then
        echo "Error: Query list not found: $query_list"
        exit 1
    fi

    if [[ ! -f "$db_list" ]]; then
        echo "Error: Database list not found: $db_list"
        exit 1
    fi

    echo "Running pairwise alignment..."
    "$DALI_DIR/bin/dali.pl" --query "$query_list" --db "$db_list" --dat1 "$dat_dir" --dat2 "$dat_dir"
}

cmd_matrix() {
    local structure_list="$1"
    local dat_dir="$2"

    if [[ -z "$structure_list" || -z "$dat_dir" ]]; then
        echo "Error: matrix requires structure_list and dat_dir"
        usage
    fi

    if [[ ! -f "$structure_list" ]]; then
        echo "Error: Structure list not found: $structure_list"
        exit 1
    fi

    echo "Running all-against-all matrix comparison..."
    "$DALI_DIR/bin/dali.pl" --query "$structure_list" --matrix --dat1 "$dat_dir" --dat2 "$dat_dir"
}

cmd_search() {
    local query_list="$1"
    local db_list="$2"
    local dat_dir="$3"

    if [[ -z "$query_list" || -z "$db_list" || -z "$dat_dir" ]]; then
        echo "Error: search requires query_list, db_list, and dat_dir"
        usage
    fi

    echo "Running database search..."
    "$DALI_DIR/bin/dali.pl" --query "$query_list" --db "$db_list" --dat1 "$dat_dir" --dat2 "$dat_dir"
}

# Main
if [[ $# -lt 1 ]]; then
    usage
fi

command="$1"
shift

case "$command" in
    import)
        cmd_import "$@"
        ;;
    pairwise)
        cmd_pairwise "$@"
        ;;
    matrix)
        cmd_matrix "$@"
        ;;
    search)
        cmd_search "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Error: Unknown command: $command"
        usage
        ;;
esac
