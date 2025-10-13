import xarray as xr
import os
import warnings
import argparse
import glob
#from dask.distributed import Client, LocalCluster


def main(indir, outdir, yyyy, mm, spe):
   #os.environ['HDF5_USE_FILE_LOCKING'] = 'FALSE'
   #client = Client(LocalCluster())

    warnings.filterwarnings(
        "ignore",
        message="Duplicate dimension names present.*",
        category=UserWarning,
        module="xarray.namedarray.core",
    )
    os.makedirs(outdir, exist_ok=True)
    match spe:
        case 'Spec':
            file_list = glob.glob(f"{indir}/GEOSChem.ACAGSpecDaily.{yyyy}{mm:02}*.nc4")
            out_path = f'{outdir}/GEOSChem.ACAGSpecMonthly.{yyyy}{mm:02}.nc4'
        case 'AOD':
            file_list = glob.glob(f"{indir}/GEOSChem.ACAGAODHourly.{yyyy}{mm:02}*.nc4")
            out_path = f'{outdir}/GEOSChem.ACAGAODMonthly.{yyyy}{mm:02}.nc4'
        case 'ALT1Spec':
            file_list = glob.glob(f"{indir}/GEOSChem.ALT1SpecHourly.{yyyy}{mm:02}*.nc4")
            out_path = f'{outdir}/GEOSChem.ALT1SpecMonthly.{yyyy}{mm:02}.nc4'
        case 'Gas':
            file_list = glob.glob(f"{indir}/GEOSChem.ACAGGasDaily.{yyyy}{mm:02}*.nc4")
            out_path = f'{outdir}/GEOSChem.ACAGGasMonthly.{yyyy}{mm:02}.nc4'
        case _:
            print(f'Spec {spe} does not exist.')
            return None

    ds = xr.open_mfdataset(
        file_list,
        drop_variables=['anchor'],
        chunks={'time': 1, 'nf': 6, 'lev': 72},
    )
    time_stamp = ds.time[0].values
    ds_out = ds.mean(dim='time', keep_attrs=True, keepdims=True).compute()
    ds_out = ds_out.assign_coords(time=[time_stamp])
    #os.environ['HDF5_USE_FILE_LOCKING'] = 'TRUE'
    ds_out.to_netcdf(out_path)
    ds.close()
    #client.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Extract monthly mean from daily GEOS-Chem data.'
    )
    parser.add_argument('indir', type=str, help='Input directory containing daily data')
    parser.add_argument('outdir', type=str, help='Output directory for monthly data')
    parser.add_argument('year', type=int, help='Year to process')
    parser.add_argument(
        'month', type=int, choices=range(1, 13), help='Month to process (1-12)'
    )
    parser.add_argument(
        'spe',
        type=str,
        choices=['AOD', 'Spec', 'ALT1Spec', 'Gas'],
        help='Type of file to process',
    )

    args = parser.parse_args()

    indir = args.indir
    outdir = args.outdir
    year = args.year
    month = args.month
    spe = args.spe
    main(indir, outdir, year, month, spe)
