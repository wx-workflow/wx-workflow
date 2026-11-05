#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153,SC2154
declare -rx PS4='+${SECONDS}s $(basename ${BASH_SOURCE[0]:-${FUNCNAME[0]:-"Unknown"}})[${LINENO}]: '
set -x
cpreq=${cpreq:-cpreq}

cd "${DATA}" || exit 1

HOMErdasapp=${HOMErrfs}/sorc/RDASApp
if [[ -s "${EXECrrfs}/irs_2ioda.py" ]]; then
  ${cpreq} "${EXECrrfs}"/irs_2ioda.py .
elif [[ -s "${HOMErdasapp}/build/bin/irs_2ioda.py" ]]; then
  ${cpreq} "${HOMErdasapp}"/build/bin/irs_2ioda.py .
else
  ${cpreq} "${HOMErdasapp}"/sorc/iodaconv/src/satpy/irs_2ioda.py .
fi

# Setup Python and pyioda library path
PYIODALIB=$(echo "${HOMErdasapp}"/build/lib/python3.*)
export PYTHONPATH="${PYIODALIB}:${PYTHONPATH}"

# Configuration parameters
obspath_raw="${OBSPATH_MTGIRS:-""}"
export MTG_IRS_QUADRANTS="${MTG_IRS_QUADRANTS:-"Q3 Q4"}"
window_min="${MTG_IRS_WINDOW:-15}"
res="${MTG_IRS_RESOLUTION:-16}"
base_ev="${FIXrrfs}/jedi/RSP_OPE_BASEEV_MTS1+IRS_20240924000000_V1.h5"

echo "Processing MTG-IRS with quadrants: ${MTG_IRS_QUADRANTS}, window: +/-${window_min}m, resolution: ${res}"

if [[ ! -s "${base_ev}" ]]; then
  # Fallback to test ancillary location if not yet populated in FIXrrfs
  base_ev="/gpfs/f7/wrfruc/scratch/Sijie.Pan/AR3.5KM/wx-workflow/fix/jedi/RSP_OPE_BASEEV_MTS1+IRS_20240924000000_V1.h5"
fi

if [[ -z "${obspath_raw}" || ! -d "${obspath_raw}" ]]; then
  echo "WARNING: Raw MTG-IRS observation directory '${obspath_raw}' does not exist or is not defined. Skipping MTG-IRS."
  exit 0
fi

# Dynamically filter CHK-BODY files matching quadrants and time window [T0 - window_min, T0 + window_min]
python3 - << 'EOF'
import os
import sys
import re
from datetime import datetime, timedelta

cdate_str = os.environ.get('CDATE', '')
raw_dir = os.environ.get('OBSPATH_MTGIRS', '')
window_min = int(os.environ.get('MTG_IRS_WINDOW', '15'))
quads_str = os.environ.get('MTG_IRS_QUADRANTS', 'Q3 Q4')
quadrants = set(quads_str.replace(',', ' ').split())

if not cdate_str or not raw_dir or not os.path.isdir(raw_dir):
    print(f"WARNING: Invalid CDATE ('{cdate_str}') or raw directory ('{raw_dir}')")
    sys.exit(0)

# Parse cycle analysis time T0 (YYYYMMDDHH)
t0 = datetime.strptime(cdate_str[:10], '%Y%m%d%H')
t_start = t0 - timedelta(minutes=window_min)
t_end = t0 + timedelta(minutes=window_min)
print(f"Filtering MTG-IRS files in {raw_dir}")
print(f"Analysis cycle T0: {t0}, Window: [{t_start}, {t_end}], Quadrants: {sorted(quadrants)}")

# Match CHK-BODY files from either DEV or OPE streams, with or without numeric prefix
pattern = re.compile(r'--(Q[1-4])--CHK-BODY.*_(?:DEV|OPE)_([0-9]{14})_([0-9]{14})_.*\.nc$')

search_dirs = [raw_dir]
for dt in [t0, t_start, t_end]:
    sub1 = os.path.join(raw_dir, dt.strftime('%Y%m%d'))
    sub2 = os.path.join(raw_dir, dt.strftime('%Y%m%d'), dt.strftime('%H'))
    sub3 = os.path.join(raw_dir, dt.strftime('%Y%m%d%H'))
    for s in [sub1, sub2, sub3]:
        if os.path.isdir(s) and s not in search_dirs:
            search_dirs.append(s)

matched_files = []
for sdir in search_dirs:
    try:
        entries = os.listdir(sdir)
    except OSError:
        continue
    for fname in entries:
        m = pattern.search(fname)
        if not m:
            continue
        quad, start_str, end_str = m.group(1), m.group(2), m.group(3)
        if quad in quadrants:
            t_file = datetime.strptime(start_str, '%Y%m%d%H%M%S')
            if t_start <= t_file <= t_end:
                matched_files.append((t_file, quad, os.path.join(sdir, fname)))

matched_files.sort(key=lambda x: (x[0], x[1]))

out_file = 'file_list.txt'
with open(out_file, 'w') as f:
    for item in matched_files:
        f.write(item[2] + '\n')

print(f"Found {len(matched_files)} matching files written to {out_file}")
EOF

if [[ ! -s file_list.txt ]]; then
  echo "WARNING: No MTG-IRS files found for cycle ${CDATE} in window [T0-${window_min}m, T0+${window_min}m]."
  exit 0
fi

num_files=$(wc -l < file_list.txt)
echo "Total MTG-IRS files to process: ${num_files}"

# Set thread count from SLURM environment
nthreads=${SLURM_CPUS_ON_NODE:-${SLURM_NTASKS:-40}}
echo "Running irs_2ioda.py with ${nthreads} threads..."

mapfile -t input_files < file_list.txt

./irs_2ioda.py \
  -d "${CDATE}" \
  --baseEV "${base_ev}" \
  --resolution "${res}" \
  --include_reconstructed_radiance \
  -j "${nthreads}" \
  -o "ioda_mtgirs.nc" \
  -i "${input_files[@]}"
err=$?

if (( err != 0 )); then
  echo "FATAL ERROR: irs_2ioda.py failed with return code ${err}."
  exit 1
fi

if [[ ! -s "ioda_mtgirs.nc" ]]; then
  echo "FATAL ERROR: ioda_mtgirs.nc was not generated or is empty."
  exit 1
fi

echo "Successfully generated ioda_mtgirs.nc:"
ls -lh ioda_mtgirs.nc
${cpreq} "ioda_mtgirs.nc" "${COMOUT}/ioda_mtgirs/${WGF}/ioda_mtgirs.nc"

echo "exrrfs_ioda_mtgirs completed normally."
exit 0
