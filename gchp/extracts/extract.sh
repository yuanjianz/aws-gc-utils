#!/bin/bash

year=$1
month=$2
indir=$3
outdir=$4
archivedir=$5
logfile=$6
pypath=$7

sbatch <<EOF
#!/bin/bash
#
#SBATCH -c 16
#SBATCH -t 01-00:00:00
#SBATCH --mem=100GB
#SBATCH -p general-ram
#SBATCH --job-name=extract
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

exec >> ${logfile} 2>&1

source ~/.bashrc
micromamba activate gcpy_env

mkdir -p $archivedir

for spe in ALT1Spec Spec AOD Gas; do
    printf -v mon "%02d" "$month"  # pad month to two digits
    echo "Processing $year-\$mon for \$spe"

    if python ${pypath} "$indir" "$outdir" "$year" "$month" "\$spe"; then
        echo "Python script succeeded for \$spe $year-\$mon"
        if [ "\$spe" == "ALT1Spec" ]; then
            mv "$indir"/GEOSChem."\$spe"*."$year""\$mon"*.nc4 "$archivedir"/
        else
            mv "$indir"/GEOSChem.ACAG"\$spe"*."$year""\$mon"*.nc4 "$archivedir"/
        fi
    else
        echo "Python script failed for \$spe $year-\$mon — skipping move."
    fi
done

echo "Moving remaining files for $year-\$mon"
mv "$indir"/GEOSChem.ACAGNO2*."$year""\$mon"*.nc4 "$archivedir"/
mv "$indir"/GEOSChem.ACAGMet*."$year""\$mon"*.nc4 "$archivedir"/
EOF
