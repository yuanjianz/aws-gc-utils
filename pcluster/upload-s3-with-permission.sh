#!/bin/bash
#
# Upload a local folder or file to S3, preserving POSIX-style metadata.
#   - If uploading a directory: requires a prefix (to avoid scattering at bucket root)
#   - If uploading a single file: uploads directly to the specified bucket/prefix
#   - Users must specify their UID and GID before running (see below)
#
# Usage:
#   ./s3_upload_with_posix_meta_update.sh [options] <local_path> <bucket> [prefix]
#
# Options:
#   -h, --help      Show this help message and exit.
#
# Examples:
#   # Upload a directory safely (with prefix)
#   ./s3_upload_with_posix_meta_update.sh ./data my-bucket fsxdata
#
#   # Upload a single file directly to bucket root
#   ./s3_upload_with_posix_meta_update.sh ./file.txt my-bucket
#
#   # Find your UID and GID on the cluster
#   id -u   # prints your UID
#   id -g   # prints your GID
#
# Expected consequences:
#   - Files are uploaded with metadata:
#       x-amz-meta-file-owner        = USER_ID
#       x-amz-meta-file-group        = GROUP_ID
#       x-amz-meta-file-permissions  = 0100644
#   - Directories appear as zero-byte objects (keys ending with "/") with:
#       x-amz-meta-file-permissions  = 0040755
#   - If a directory marker already exists, its metadata are updated in-place
#     using aws s3api copy-object --metadata-directive REPLACE.

set -euo pipefail

# ---------- Configuration ----------
USER_ID=""
GROUP_ID=""

# ---------- Help section ----------
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    awk '
        /^#/ { sub(/^# ?/, ""); print; next }
        !/^#/ { exit }
    ' "$0"
    exit 0
fi

# ---------- Validate UID/GID ----------
if [[ -z "$USER_ID" || -z "$GROUP_ID" ]]; then
    echo "❌ ERROR: USER_ID or GROUP_ID not set."
    echo
    echo "You must edit this script before running it and fill in your own UID and GID."
    echo
    echo "👉 Run the following commands on your cluster to find them:"
    echo "   id -u   # prints your UID"
    echo "   id -g   # prints your GID"
    echo
    echo "Then open this script and set:"
    echo "   USER_ID=<your_uid>"
    echo "   GROUP_ID=<your_gid>"
    echo
    echo "Example:"
    echo "   USER_ID=1001"
    echo "   GROUP_ID=1001"
    exit 1
fi

# ---------- Argument parsing ----------
LOCAL_PATH="${1:-}"
BUCKET="${2:-}"
PREFIX="${3:-}"  # optional

if [[ -z "$LOCAL_PATH" || -z "$BUCKET" ]]; then
    echo "Usage: $0 <local_path> <bucket> [prefix]"
    echo "Try '$0 -h' for more information."
    exit 1
fi

# ---------- Metadata setup ----------
FILE_MODE="0100644"   # regular file rw-r--r--
DIR_MODE="0040755"    # directory rwxr-xr-x

# ---------- Case 1: local_path is a file ----------
if [[ -f "$LOCAL_PATH" ]]; then
    BASENAME=$(basename "$LOCAL_PATH")

    if [[ -n "$PREFIX" ]]; then
        KEY="${PREFIX}/${BASENAME}"
    else
        KEY="$BASENAME"
    fi

    echo ">>> Uploading single file $LOCAL_PATH to s3://$BUCKET/$KEY"
    aws s3api put-object \
        --bucket "$BUCKET" \
        --key "$KEY" \
        --body "$LOCAL_PATH" \
        --metadata "file-owner=${USER_ID},file-group=${GROUP_ID},file-permissions=${FILE_MODE}"
    echo ">>> Done uploading file."
    exit 0
fi

# ---------- Case 2: local_path is a directory ----------
if [[ -d "$LOCAL_PATH" ]]; then
    if [[ -z "$PREFIX" ]]; then
        echo "Error: when uploading a directory, you must specify a prefix to avoid scattering files in bucket root."
        echo "Example: $0 ./data my-bucket fsxdata"
        exit 1
    fi

    echo ">>> Uploading directory $LOCAL_PATH to s3://$BUCKET/$PREFIX/"
    echo ">>> Using USER_ID:GROUP_ID = $USER_ID:$GROUP_ID"

    DEST="s3://$BUCKET/$PREFIX/"

    # ---------- Step 1: upload files ----------
    aws s3 sync "$LOCAL_PATH" "$DEST" \
      --metadata "file-owner=${USER_ID},file-group=${GROUP_ID},file-permissions=${FILE_MODE}" \
      --exact-timestamps

    # ---------- Step 2: create/update directory markers ----------
    echo ">>> Creating or updating directory markers with metadata ..."

    find "$LOCAL_PATH" -type d | while read -r dir; do
        rel="${dir#${LOCAL_PATH}/}"
        key="${PREFIX}/${rel}/"
        key="${key#./}"
        key="${key#/}"

        echo " -> Processing $key"

        if aws s3api head-object --bucket "$BUCKET" --key "$key" >/dev/null 2>&1; then
            echo "    (exists) updating metadata"
            aws s3api copy-object \
                --bucket "$BUCKET" \
                --copy-source "$BUCKET/$key" \
                --key "$key" \
                --metadata-directive REPLACE \
                --metadata "file-owner=${USER_ID},file-group=${GROUP_ID},file-permissions=${DIR_MODE}" \
                >/dev/null
        else
            echo "    (new) creating directory marker"
            aws s3api put-object \
                --bucket "$BUCKET" \
                --key "$key" \
                --metadata "file-owner=${USER_ID},file-group=${GROUP_ID},file-permissions=${DIR_MODE}" \
                >/dev/null
        fi
    done

    echo ">>> Directory upload complete."
    exit 0
fi

# ---------- Otherwise ----------
echo "Error: $LOCAL_PATH is neither a regular file nor a directory."
exit 1
