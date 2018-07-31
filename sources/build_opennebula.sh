#!/bin/bash -ex

BUILD_DIR=$PWD

if [ -f "${XMLRPC_DIR}xmlrpc-c.tar.gz" ]; then
(
    tar xzvf ${XMLRPC_DIR}xmlrpc-c.tar.gz
    mv xmlrpc-c ..
    mv ${XMLRPC_DIR}xml_parse_huge.patch $BUILD_DIR/..
)
fi

# Compile xmlrpc-c
cd ../xmlrpc-c
export CXXFLAGS="-fPIC"
export CFLAGS="-Wno-error=format-security"
patch -p1 < $BUILD_DIR/../xml_parse_huge.patch
./configure --prefix=$PWD/install --enable-libxml2-backend
make
make install

# Delete dynamic libraries
rm -f install/{lib,lib64}/*.so install/{lib,lib64}/*.so.*

# Add xmlrpc-c libraries bin dir to the path
export PATH=$PWD/install/bin:$PATH

# Compile OpenNebula
cd $BUILD_DIR

scons -j8 mysql=yes xmlrpc=$BUILD_DIR/../xmlrpc-c/install new_xmlrpc=yes $@ # syslog=yes
