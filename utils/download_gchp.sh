#!/bin/bash

git clone --recurse-submodules https://github.com/geoschem/GCHP.git GCHP
cd GCHP
git checkout 14.6.0
git submodule update -f --recursive
cd src/GCHP_GridComp/GEOSChem_GridComp/geos-chem
git remote add dev https://github.com/yuanjianz/geos-chem.git
git fetch dev
git checkout dev/dev/14.6.0-long-term-luo2023-load-balancing
git submodule update -f
cd -

