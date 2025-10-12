#!/bin/bash

set -e 
OPERATION="status"
YEAR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -o) OPERATION="$2"; shift 2 ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *)
            YEAR="$1"
            shift ;;
    esac
done

if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]] || (( YEAR < 1998 || YEAR > 2023 )); then
    echo "Error: Year must be a 4-digit number between 1998 and 2023"
    exit 1
fi

dust=/fsx/s3/ExtData/HEMCO/OFFLINE_DUST/v2025-03/0.5x0.625/GEOSIT/$YEAR
biovoc=/fsx/s3/ExtData/HEMCO/OFFLINE_BIOVOC/v2025-04/0.5x0.625/GEOSIT/$YEAR
seasalt=/fsx/s3/ExtData/HEMCO/OFFLINE_SEASALT/v2025-04/0.5x0.625/GEOSIT/$YEAR
soilnox=/fsx/s3/ExtData/HEMCO/OFFLINE_SOILNOX/v2025-04/0.5x0.625/GEOSIT/$YEAR

/home/ec2-user/aws-gc-utils/pcluster/lfs_hsm_util.sh -o "$OPERATION"  "$biovoc" "$seasalt" "$soilnox" "$dust"

