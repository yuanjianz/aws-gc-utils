#!/bin/bash
#
# Enhanced Lustre HSM Script - Supports directories, files, and glob patterns
#

# Basic settings
set -e  # Exit on error (but not -u to avoid unbound variable issues)

# Parse arguments
OPERATION="status"
TARGET=""
DRY_RUN=false
ALL_TARGETS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -o) OPERATION="$2"; shift 2 ;;
        -d) DRY_RUN=true; shift ;;
        -h) echo "Usage: $0 [-o status|action|preload|archive|release] [-d] <directory|file|pattern>"; 
            echo "Examples:"
            echo "  $0 /path/to/directory"
            echo "  $0 /path/to/file.txt"
            echo "  $0 'ExtData/GEOS_C180/GEOS_IT/2011/01/GEOSIT.20110101.*'"
            echo "  $0 -o preload '/data/*.nc'"
            echo "Note: Quote glob patterns to prevent shell expansion"
            exit 0 ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *)
            ### MODIFIED: accept multiple targets (do not only keep the first)
            ALL_TARGETS+=("$1")
            shift ;;
    esac
done

# Validate
if [[ ${#ALL_TARGETS[@]} -eq 0 ]]; then
    echo "Error: No target specified (directory, file, or pattern)"
    exit 1
fi

### MODIFIED: show all targets instead of just one
echo "Targets: ${ALL_TARGETS[*]}"
if [[ ${#ALL_TARGETS[@]} -gt 1 ]]; then
    echo "DEBUG: Multiple arguments detected (${#ALL_TARGETS[@]} total)"
fi
echo "Operation: $OPERATION"

# Create a simple temp directory
TEMP_DIR="/tmp/lustre_$$"
mkdir -p "$TEMP_DIR" || {
    echo "Warning: Cannot create folder in /tmp, using ~/tmp"
    TEMP_DIR="~/tmp/lustre_$$"
    mkdir -p "$TEMP_DIR"
}
echo "Temp directory: $TEMP_DIR"

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        echo "Cleaned up: $TEMP_DIR"
    fi
}
trap cleanup EXIT

# Build file list based on target type
echo "Building file list..."
FILE_LIST="$TEMP_DIR/files.txt"

# Function to check if target contains glob characters
has_glob_chars() {
    [[ "$1" == *"*"* || "$1" == *"?"* || "$1" == *"["* ]]
}

### MODIFIED: unified handling for multiple directories, files, or patterns
if [[ ${#ALL_TARGETS[@]} -gt 1 ]]; then
    echo "Processing multiple targets (${#ALL_TARGETS[@]} total)"
    > "$FILE_LIST"
    for t in "${ALL_TARGETS[@]}"; do
        if [[ -d "$t" ]]; then
            echo "  Scanning directory: $t"
            if command -v lfs >/dev/null 2>&1 && lfs df "$t" >/dev/null 2>&1; then
                lfs find "$t" -type f >> "$FILE_LIST"
            else
                find "$t" -type f >> "$FILE_LIST"
            fi
        elif [[ -f "$t" ]]; then
            realpath "$t" >> "$FILE_LIST"
        elif has_glob_chars "$t"; then
            echo "  Expanding glob pattern: $t"
            shopt -s nullglob dotglob
            for f in $t; do
                [[ -f "$f" ]] && realpath "$f" >> "$FILE_LIST"
            done
        else
            echo "Warning: Skipping invalid target: $t"
        fi
    done

elif [[ -d "${ALL_TARGETS[0]}" ]]; then
    TARGET=$(realpath "${ALL_TARGETS[0]}")
    echo "Processing directory: $TARGET"
    
    if command -v lfs >/dev/null 2>&1 && lfs df "$TARGET" >/dev/null 2>&1; then
        echo "Using lfs find (Lustre filesystem detected)"
        lfs find "$TARGET" -type f > "$FILE_LIST"
    else
        echo "Using regular find"
        find "$TARGET" -type f > "$FILE_LIST"
    fi
    
elif [[ -f "${ALL_TARGETS[0]}" ]]; then
    TARGET=$(realpath "${ALL_TARGETS[0]}")
    echo "Processing single file: $TARGET"
    echo "$TARGET" > "$FILE_LIST"
    
elif has_glob_chars "${ALL_TARGETS[0]}"; then
    TARGET="${ALL_TARGETS[0]}"
    echo "Processing glob pattern: $TARGET"
    
    echo "DEBUG: Received target: '$TARGET'"
    echo "DEBUG: Arguments passed to script: $*"
    
    shopt -s nullglob dotglob
    > "$FILE_LIST"
    for file_match in $TARGET; do
        [[ -f "$file_match" ]] && realpath "$file_match" >> "$FILE_LIST"
    done
    
    TOTAL_FILES=$(wc -l < "$FILE_LIST")
    if [[ $TOTAL_FILES -eq 0 ]]; then
        echo "Error: No files match the pattern: $TARGET"
        echo "Make sure to quote your pattern: './script.sh \"$TARGET\"'"
        exit 1
    fi
    
    echo "Expanded pattern to $TOTAL_FILES files"
    
else
    echo "Error: Target does not exist and is not a valid glob pattern: ${ALL_TARGETS[0]}"
    exit 1
fi

# Check results
if [[ ! -f "$FILE_LIST" ]]; then
    echo "Error: Could not create file list"
    exit 1
fi

TOTAL_FILES=$(wc -l < "$FILE_LIST")
echo "Found $TOTAL_FILES files"

if [[ $TOTAL_FILES -eq 0 ]]; then
    echo "No files found"
    exit 0
fi

# Show sample files
echo ""
echo "Sample files:"
head -5 "$FILE_LIST"
if [[ $TOTAL_FILES -gt 5 ]]; then
    echo "... and $((TOTAL_FILES - 5)) more files"
fi
echo ""

# Execute operation
case "$OPERATION" in
    status)
        if command -v lfs >/dev/null 2>&1; then
            echo "Analyzing HSM status of all $TOTAL_FILES files..."
            echo ""
            
            # Use AWS-documented xargs approach for parallel processing
            echo "Using parallel processing with xargs..."
            cat "$FILE_LIST" | xargs -P 8 -I {} sh -c 'if [[ -f "{}" ]]; then lfs hsm_state "{}" 2>/dev/null | sed "s/.*: //" || echo "unknown"; fi' | \
                sort | uniq -c | while read -r count state; do
                percentage=$((count * 100 / TOTAL_FILES))
                printf "%8d files (%3d%%) - %s\n" "$count" "$percentage" "$state"
            done
            
            echo ""
            echo "Total files analyzed: $TOTAL_FILES"
            
        else
            echo "lfs command not available - cannot check HSM status"
            echo "Total files found: $TOTAL_FILES"
        fi
        ;;
    action)
        if command -v lfs >/dev/null 2>&1; then
            echo "Analyzing HSM action of all $TOTAL_FILES files..."
            echo ""
            # Use AWS-documented xargs approach for parallel processing
            echo "Using parallel processing with xargs..."
            cat "$FILE_LIST" | xargs -P 8 -I {} sh -c 'if [[ -f "{}" ]]; then lfs hsm_action "{}" 2>/dev/null | sed "s/.*: //" || echo  "unknown"; fi' | \
            sed 's/ (.*//' | \
            sort | uniq -c | while read -r count state; do
                percentage=$((count * 100 / TOTAL_FILES))
                printf "%8d files (%3d%%) - %s\n" "$count" "$percentage" "$state"
            done
            echo ""
            echo "Total files analyzed: $TOTAL_FILES"
        else
            echo "lfs command not available - cannot check HSM status"
            echo "Total files found: $TOTAL_FILES"
        fi
        ;;
    preload)
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY RUN: Would restore $TOTAL_FILES files from S3"
        else
            echo "Restoring $TOTAL_FILES files from S3..."
            echo "Using parallel processing with xargs..."
            
            # Use AWS-documented approach: xargs with parallel processing
            cat "$FILE_LIST" | xargs -P 8 -I {} sh -c '
                if lfs hsm_restore "{}" 2>/dev/null; then
                    echo "SUCCESS"
                else
                    echo "FAILED"
                fi
            ' | sort | uniq -c | while read -r count state; do
                percentage=$((count * 100 / TOTAL_FILES))
                printf "%8d files (%3d%%) - %s\n" "$count" "$percentage" "$state"
            done

            echo ""
            echo "Total files processed: $TOTAL_FILES"
        fi
        ;;
    archive)
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY RUN: Would archive $TOTAL_FILES files to S3"
        else
            echo "Archiving $TOTAL_FILES files to S3..."
            echo "Using parallel processing with xargs..."
            
            cat "$FILE_LIST" | xargs -P 8 -I {} sh -c '
                if lfs hsm_archive "{}" 2>/dev/null; then
                    echo "SUCCESS"
                else
                    echo "FAILED"
                fi
            ' | sort | uniq -c | while read -r count state; do
                percentage=$((count * 100 / TOTAL_FILES))
                printf "%8d files (%3d%%) - %s\n" "$count" "$percentage" "$state"
            done

            echo ""
            echo "Total files processed: $TOTAL_FILES"
        fi
        ;;
    release)
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY RUN: Would release $TOTAL_FILES files"
        else
            echo "Releasing $TOTAL_FILES files..."
            echo "Using parallel processing with xargs..."
            
            cat "$FILE_LIST" | xargs -P 8 -I {} sh -c '
                if lfs hsm_release "{}" 2>/dev/null; then
                    echo "SUCCESS"
                else
                    echo "FAILED"
                fi
            ' | sort | uniq -c | while read -r count state; do
                percentage=$((count * 100 / TOTAL_FILES))
                printf "%8d files (%3d%%) - %s\n" "$count" "$percentage" "$state"
            done

            echo ""
            echo "Total files processed: $TOTAL_FILES"
        fi
        ;;
    *)
        echo "Unknown operation: $OPERATION"
        exit 1
        ;;
esac

echo "Operation completed successfully"
