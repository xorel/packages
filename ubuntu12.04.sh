#!/bin/bash -e

SOURCES_DIR=$(dirname $0)/sources

DISTRO=`basename ${0%.sh}`
BUILD_DIR=$HOME/build
PACKAGES_DIR=$HOME/one-tester/packages

URL=$1
PKG_VERSION=${2:-1}

URL_APPS=http://testing-packages/source/oneapps.tar.gz

SOURCE=`basename $URL` # opennebula-1.9.90.tar.gz
PACKAGE=${SOURCE%.tar.gz} # opennebula-1.9.90


NAME=`echo $PACKAGE|cut -d'-' -f1` # opennebula
VERSION=`echo $PACKAGE|cut -d'-' -f2` # 1.9.90
CONTACT='OpenNebula Team <contact@opennebula.org>'

DATE_R=`date -R`

# clean $BUILD_DIR
rm -rf $BUILD_DIR/*

# download source
cd $BUILD_DIR
case $URL in
    http*)
        wget -q $URL || exit 1
        ;;
    *)
        cp $URL . || exit 1
esac

# rename source
rename 's/(opennebula)-/$1_/' *tar.gz
rename 's/\.tar\.gz/.orig.tar.gz/' *tar.gz

# untar
tar xzf *tar.gz

# copy debian folder to source code
cd $PACKAGE
cp -Lr $PACKAGES_DIR/templates/$DISTRO-debian .
mv $DISTRO-debian debian

# Prepare files in debian/
(
cd debian

# Process changelog
cat <<EOF > newchangelog
$NAME ($VERSION-$PKG_VERSION) unstable; urgency=low

  * Imported from http://packages.qa.debian.org/o/opennebula.html

 -- $CONTACT $DATE_R

EOF
mv newchangelog changelog


# parse and substitute values in templates
for f in `ls`; do
    for i in URL SOURCE PACKAGE NAME VERSION DATE_R CONTACT PKG_VERSION; do
        VAL=$(eval "echo \${$i}")
        if [ -f "$f" ]; then
            sed -i -e "s|%$i%|$VAL|g" $f
        fi
    done
done
)

debuild -us -uc

# build a tar.gz with the files
cd $BUILD_DIR
mkdir source
mv *debian* *orig* *dsc source
tar cvzf $NAME-$VERSION-$PKG_VERSION.tar.gz \
    --owner=root --group=root  \
    --transform "s,^,$NAME-$VERSION-$PKG_VERSION/," \
    *deb source
