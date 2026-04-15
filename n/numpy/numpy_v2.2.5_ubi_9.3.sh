#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package       : numpy
# Version       : v2.2.5
# Source repo   : https://github.com/numpy/numpy
# Tested on     : UBI:9.3
# Language      : Python
# Ci-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Sai Kiran Nukala <sai.kiran.nukala@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------
set -ex

PACKAGE_NAME=numpy
PACKAGE_VERSION=${1:-v2.2.5}
PACKAGE_URL=https://github.com/numpy/numpy.git
PACKAGE_DIR=numpy
CURRENT_DIR="${PWD}"

yum install -y wget python3.12 python3.12-devel python3.12-pip git \
               gcc-toolset-13-gcc gcc-toolset-13-gcc-c++ \
               gcc-toolset-13-gcc-gfortran make

export PATH=/opt/rh/gcc-toolset-13/root/usr/bin:$PATH

ln -sf /usr/bin/python3.12 /usr/bin/python3

python3 -m pip install --upgrade pip
python3 -m pip install tox Cython pytest hypothesis wheel meson ninja

export SITE_PACKAGE_PATH=/usr/local/lib/python3.12/site-packages

# ================= OpenBLAS =================
git clone https://github.com/OpenMathLib/OpenBLAS.git
cd OpenBLAS
git checkout v0.3.32

make -j$(nproc) TARGET=POWER9 BUILD_BFLOAT16=1 BINARY=64 \
     USE_OPENMP=1 USE_THREAD=1 NUM_THREADS=120 \
     DYNAMIC_ARCH=1 INTERFACE64=0

make install

export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH

cd ..
# =====================================================

# clone numpy
git clone $PACKAGE_URL
cd $PACKAGE_NAME
git checkout $PACKAGE_VERSION
git submodule update --init

export GCC_HOME=/opt/rh/gcc-toolset-13/root/usr

export PATH=$GCC_HOME/bin:$PATH
export CC=$GCC_HOME/bin/gcc
export CXX=$GCC_HOME/bin/g++
export GCC=$CC
export GXX=$CXX
export AR=${GCC_HOME}/bin/ar
export LD=${GCC_HOME}/bin/ld
export NM=${GCC_HOME}/bin/nm
export OBJCOPY=${GCC_HOME}/bin/objcopy
export OBJDUMP=${GCC_HOME}/bin/objdump
export RANLIB=${GCC_HOME}/bin/ranlib
export STRIP=${GCC_HOME}/bin/strip
export READELF=${GCC_HOME}/bin/readelf

UNAME_M=$(uname -m)
case "$UNAME_M" in
    ppc64*)
        export CXXFLAGS="$(echo ${CXXFLAGS} | sed -e 's/ -fno-plt//')"
        export CFLAGS="$(echo ${CFLAGS} | sed -e 's/ -fno-plt//')"
        ;;
    *)
        ;;
esac

# install numpy
if ! (python3 -m pip install . ); then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    exit 1
fi

python3 -m pip install build meson-python patchelf

if ! python3 -m build --wheel --no-isolation --outdir="$CURRENT_DIR/"; then
    echo "Retrying with isolation..."
    python3 -m build --wheel --outdir="$CURRENT_DIR/"
fi

export CFLAGS="-DCYTHON_PEP489_MULTI_PHASE_INIT=0"

# run tests
if ! (tox -e py3); then
    echo "--------------------$PACKAGE_NAME:Test_fails---------------------"
    exit 2
else
    echo "------------------$PACKAGE_NAME:SUCCESS-------------------------"
    exit 0
fi
