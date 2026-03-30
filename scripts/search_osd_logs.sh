#!/bin/bash

set -euo pipefail

PRIMARY_ONLY=false

# Parse flags
while [[ $# -gt 0 && "$1" == --* ]]; do
    case "$1" in
        --primary)
            PRIMARY_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ $# -lt 1 ]; then
    echo "Usage: $0 [--primary] <search_term> [search_dir] [output_file]" >&2
    exit 1
fi

SEARCH_TERM="$1"
SEARCH_DIR="${2:-.}"
OUTPUT_FILE="${3:-osd_search_results.txt}"

> "$OUTPUT_FILE"

files_searched=0
files_with_matches=0

# Find the primary OSD log file (contains 'r=0') for a given numbered directory.
# Returns the path to the primary log file, or empty if none found.
find_primary_osd() {
    local dir="$1"
    for file in "$dir"/remote/*/log/ceph-osd.*.log.gz; do
        [ -f "$file" ] || continue
        if rg -z -q 'r=0' "$file" 2>/dev/null; then
            echo "$file"
            return
        fi
    done
}

search_file() {
    local file="$1"
    [ -f "$file" ] || return

    echo "Searching file: $file" >&2
    files_searched=$((files_searched + 1))

    results=$(rg -z -m 2 --no-filename --no-line-number "$SEARCH_TERM" "$file" 2>/dev/null || true)

    if [ -n "$results" ]; then
        count=$(echo "$results" | wc -l | tr -d ' ')
        echo "Found $count matches" >&2
        files_with_matches=$((files_with_matches + 1))
        echo "=== $file ===" >> "$OUTPUT_FILE"
        echo "$results" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo "Found none" >&2
    fi
}

if [ "$PRIMARY_ONLY" = true ]; then
    for dir in "$SEARCH_DIR"/*/; do
        [ -d "$dir" ] || continue
        echo "Finding primary OSD in: $dir" >&2
        primary_file=$(find_primary_osd "$dir")
        if [ -n "$primary_file" ]; then
            echo "Primary OSD log: $primary_file" >&2
            search_file "$primary_file"
        else
            echo "No primary OSD found in: $dir" >&2
        fi
    done
else
    for file in "$SEARCH_DIR"/*/remote/*/log/ceph-osd.*.log.gz; do
        search_file "$file"
    done
fi

echo "Done. Searched $files_searched files, found matches in $files_with_matches files. Results saved to $OUTPUT_FILE" >&2
