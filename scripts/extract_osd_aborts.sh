#!/bin/bash

set -euo pipefail

if [ $# -gt 2 ]; then
    echo "Usage: $0 [search_dir] [output_file]" >&2
    exit 1
fi

SEARCH_DIR="${1:-.}"
OUTPUT_FILE="${2:-osd_abort_results.txt}"

> "$OUTPUT_FILE"

aborts_found=()

extract_abort() {
    local file="$1"

    # Buffer the tail of the decompressed log, then locate the LAST
    # "Got SIGABRT on shard" whose next line begins with "Backtrace:".
    # Earlier mid-log "Aborting Got SIGABRT..." lines exist; only the
    # terminal one has a real Backtrace block. Print that line + 10
    # following lines. Exit 1 if no terminal abort in the tail.
    zcat "$file" 2>/dev/null | tail -n 200 | awk '
        { buf[NR] = $0; n = NR }
        END {
            best = 0
            for (i = 1; i < n; i++) {
                if (buf[i] ~ /Got SIGABRT on shard/ && buf[i+1] ~ /^Backtrace:/) {
                    best = i
                }
            }
            if (best == 0) exit 1
            end = best + 10
            if (end > n) end = n
            for (i = best; i <= end; i++) print buf[i]
        }
    '
}

for file in "$SEARCH_DIR"/*/remote/*/log/ceph-osd.*.log.gz; do
    [ -f "$file" ] || continue

    if result=$(extract_abort "$file"); then
        echo "=== $file ===" >> "$OUTPUT_FILE"
        echo "$result" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        aborts_found+=("$file")
    fi
done

echo "Aborts found in ${#aborts_found[@]} file(s):" >&2
for f in "${aborts_found[@]}"; do
    echo "  $f" >&2
done
echo "Results saved to $OUTPUT_FILE" >&2
