#!/bin/bash
# --------------------------------------------------------------------
# Install Jasper 1.900.29 under /opt/geos-chem/jasper
# (includes patch for const-mismatch build error and cleanup)
# --------------------------------------------------------------------

set -euo pipefail

JASPER_VER="1.900.29"
JASPER_URL="https://www.ece.uvic.ca/~frodo/jasper/software/jasper-${JASPER_VER}.tar.gz"
SRC_DIR="/home/ec2-user/jasper-${JASPER_VER}"
TAR_FILE="/home/ec2-user/jasper-${JASPER_VER}.tar.gz"
INSTALL_DIR="/opt/geos-chem/jasper"
MODULE_DIR="/etc/modulefiles/jasper"
MODULE_FILE="${MODULE_DIR}/${JASPER_VER}"

# --------------------------------------------------------------------
# Download & extract
# --------------------------------------------------------------------
cd /home/ec2-user
if [[ ! -f "${TAR_FILE}" ]]; then
    echo "Downloading Jasper ${JASPER_VER}..."
    curl -LO "${JASPER_URL}"
fi

echo "Extracting source..."
tar -xzf "${TAR_FILE}"

# --------------------------------------------------------------------
# Apply patch for jpg_dummy.c const mismatch
# --------------------------------------------------------------------
echo "Patching jpg_dummy.c to fix const mismatch..."
sed -i 's/jpg_decode(jas_stream_t \*in, char \*optstr)/jpg_decode(jas_stream_t *in, const char *optstr)/' \
    "${SRC_DIR}/src/libjasper/jpg/jpg_dummy.c"
sed -i 's/jpg_encode(jas_image_t \*image, jas_stream_t \*out, char \*optstr)/jpg_encode(jas_image_t *image, jas_stream_t *out, const char *optstr)/' \
    "${SRC_DIR}/src/libjasper/jpg/jpg_dummy.c"

# --------------------------------------------------------------------
# Configure, build, install
# --------------------------------------------------------------------
cd "${SRC_DIR}"
echo "Configuring Jasper..."
./configure --prefix="${INSTALL_DIR}"

echo "Building Jasper..."
make -j"$(nproc)"

echo "Installing to ${INSTALL_DIR}..."
sudo make install

# --------------------------------------------------------------------
# Create modulefile
# --------------------------------------------------------------------
echo "Creating modulefile at ${MODULE_FILE}..."
sudo mkdir -p "${MODULE_DIR}"

sudo tee "${MODULE_FILE}" > /dev/null <<EOF
#%Module

proc ModulesHelp { } {
   puts stderr "This module adds JASPER v${JASPER_VER} to various paths"
}

module-whatis   "Sets up JASPER v${JASPER_VER} in your environment"

setenv JASPER_HOME ${INSTALL_DIR}
prepend-path PATH "${INSTALL_DIR}/bin"
prepend-path LD_LIBRARY_PATH "${INSTALL_DIR}/lib"
EOF

# --------------------------------------------------------------------
# Cleanup
# --------------------------------------------------------------------
echo "Cleaning up source files..."
rm -rf "${SRC_DIR}" "${TAR_FILE}"

# --------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------
echo
echo "✅ Jasper ${JASPER_VER} successfully built and installed."
echo "  Installed to: ${INSTALL_DIR}"
echo "  Module file:  ${MODULE_FILE}"
echo
echo "To load Jasper, run:"
echo "  module load jasper/${JASPER_VER}"
