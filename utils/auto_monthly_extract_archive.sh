#!/bin/bash
# ============================================================
# Automated GEOS-Chem monthly extraction and FSx HSM handler
# Persistent background version
# Author: Yuanjian Zhang
# Version: 3.0
# ============================================================

set -euo pipefail

# ------------------ USER CONFIG -----------------------------
# ------------------ USER CONFIG -----------------------------
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <year> <start_month> <end_month>"
    echo "Example: $0 2013 1 12"
    exit 1
fi

year=$1
start_month=$2
end_month=$3

if ! [[ "$year" =~ ^[0-9]{4}$ ]]; then
    echo "Error: year must be a 4-digit number" >&2
    exit 1
fi
if (( start_month < 1 || start_month > 12 )) || (( end_month < 1 || end_month > 12 )); then
    echo "Error: months must be between 1 and 12" >&2
    exit 1
fi

# Paths (user-defined)
root_path="/fsx"
extract_script="$HOME/aws-gc-utils/gchp/extracts/extract.sh"
pypath="$HOME/aws-gc-utils/gchp/extracts/extract.py"
lfs_hsm_util="$HOME/aws-gc-utils/pcluster/lfs_hsm_util.sh"
extdata_root="$root_path/s3/ExtData/GEOS_C180/GEOS_IT"

experiment="longterm_v2"
rundir="$root_path/rundir/gchp_c180_mf_cSOA_sPOA_GFASnoscaling_${year}_amd"
checkpoint_dir="${rundir}/Restarts"

# Extract script directory
indir="${rundir}/OutputDir"
outdir="$root_path/s3/analyze/extracts/${experiment}/${year}"
archivedir="$root_path/s3/OutputDir/${experiment}/${year}"

# ------------------ LOGGING SETUP ---------------------------
LOGDIR="$HOME/logs"
STATUS_LOGDIR="$LOGDIR/lfs_hsm_status_log"
mkdir -p "$LOGDIR" "$STATUS_LOGDIR"
MASTER_LOG="$LOGDIR/monthly_extract_master_${year}.log"

# Concurrency guard (single instance)
exec 9>"$MASTER_LOG.lock"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another instance is running; exiting." | tee -a "$MASTER_LOG"; exit 1; }

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MASTER_LOG"
}

# Fail trap for visibility
trap 'rc=$?; log "ERROR: command failed (exit $rc) at ${BASH_SOURCE[0]}:${LINENO} -> ${BASH_COMMAND}"; exit $rc' ERR

# Sanity checks
for f in "$extract_script" "$pypath" "$lfs_hsm_util"; do
  [[ -f "$f" && -r "$f" ]] || { log "Required file missing or unreadable: $f"; exit 1; }
  [[ -x "$f" ]] || log "Warning: $f not executable; attempting to continue"
done
[[ -d "$indir" ]] || { log "Input directory not found: $indir"; exit 1; }
mkdir -p "$outdir"

# ------------------------------------------------------------
# Helper function to compute next months with year rollover
# ------------------------------------------------------------
get_next_month() {
    local y=$1
    local m=$2
    local offset=$3
    date -d "${y}-${m}-01 +${offset} month" +"%Y %m"
}

# ------------------------------------------------------------
# Main monthly loop
# ------------------------------------------------------------
for (( m=$start_month; m<=$end_month; m++ )); do
    month=$(printf "%02d" $m)
    mkdir -p "$archivedir/$month"

    read next_year next_month < <(get_next_month "$year" "$month" 1)
    read next2_year month2    < <(get_next_month "$year" "$month" 2)

    log "===== Starting cycle for ${year}-${month} ====="

    checkpoint_file="${checkpoint_dir}/gcchem_internal_checkpoint.${next_year}${next_month}01_0000z.nc4"

    # Ensure per-month output/archive subdirs exist
    mkdir -p "$outdir" "$archivedir/$month"

    # =========================================================
    # Step 1: Wait until next-month checkpoint file exists
    # =========================================================
    while true; do
        if [[ -f "$checkpoint_file" ]]; then
            log "Checkpoint found: $checkpoint_file"

            # =================================================
            # Step 2: Wait 15 minutes and run extraction
            # =================================================
            log "Waiting 15 minutes before running extract.sh..."
            sleep 900

            dst_restart="${checkpoint_dir}/GEOSChem.Restart.${next_year}${next_month}01_0000z.c180.nc4"
            if [[ -e "$dst_restart" ]]; then
                log "Destination restart exists; will overwrite: $dst_restart"
            fi
            log "Renaming restart files to standard names..."
            mv -f "$checkpoint_file" "$dst_restart"

            log "Running extract.sh ${year} ${month} ..."
            "$extract_script" "$year" "$month" "$indir" "$outdir" "$archivedir/$month" "$MASTER_LOG" "$pypath" >> "$MASTER_LOG" 2>&1

            # =================================================
            # Step 3: Manage FSx HSM data
            # =================================================
            log "Releasing current month and preloading month+2..."
            sudo "$lfs_hsm_util" -o release "${extdata_root}/${year}/${month}" >> "$MASTER_LOG" 2>&1
            "$lfs_hsm_util" -o preload "${extdata_root}/${next2_year}/${month2}" >> "$MASTER_LOG" 2>&1

            # =================================================
            # Step 4: Wait until archived month fully archived
            # =================================================
            sleep 2700
            log "Monitoring HSM status for $archivedir/$month"
            status_log="$STATUS_LOGDIR/lfs_hsm_${year}_${month}.log"
            : > "$status_log"   # truncate to start fresh

            while true; do
                "$lfs_hsm_util" -o status "$archivedir/$month" >> "$status_log" 2>&1

                total_lines=$(wc -l < "$status_log")
                if (( total_lines >= 7 )); then
                    sed -n "$((total_lines-6)),$((total_lines-3))p" "$status_log" | tee -a "$MASTER_LOG"
                else
                    tail -n 4 "$status_log" | tee -a "$MASTER_LOG"
                fi

                if grep -q "(100%) - (0x00000009) exists archived, archive_id:1" "$status_log"; then
                    log "Archive fully complete — releasing $archivedir/$month"
                    "$lfs_hsm_util" -o release "$archivedir/$month" >> "$MASTER_LOG" 2>&1
                    break
                else
                    log "Archive not complete, waiting 10 more minutes..."
                    sleep 600
                fi
            done

            log "Cycle complete for ${year}-${month}"
            break
        else
            log "Checkpoint not found ($checkpoint_file), sleeping 1 hour..."
            sleep 3600
        fi
    done
done

log "===== All months ($start_month → $end_month) completed ====="
