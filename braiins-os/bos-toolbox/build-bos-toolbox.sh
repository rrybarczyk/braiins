#!/bin/sh
# Builds the bos-toolbox image on Linux and Windows (requires cygwin)

set -e

[ x$1 = x ] && {
    echo "Braiins OS ssh archive is missing"
    echo "Synopsis: $0 BRAIINS_OS_ARCHIVE"
    exit 1
}

EMBEDDED_BOS_RELEASE=$(basename ${1%.tar.gz})
echo $EMBEDDED_BOS_RELEASE > bos-version.txt
tar xvzf $1

# Optional suffix of the output binary contains 'plus' when bundling with
# Braiins OS+ firmware
if echo ${EMBEDDED_BOS_RELEASE} | grep --quiet plus; then
  BOS_VARIANT='-plus'
else
  BOS_VARIANT=''
fi

if [ x$MSYSTEM = xMINGW64 ]; then
    PYINST_PATH_SEP=';'
    VIRTUAL_ENV_ARGS=
    VIRTUAL_ENV_BIN=Scripts
    ICON_ARG="--icon bos${BOS_VARIANT}.ico"
    git rm-symlinks
else
    PYINST_PATH_SEP=':'
    VIRTUAL_ENV_ARGS=--python=/usr/bin/python3
    VIRTUAL_ENV_BIN=bin
    ICON_ARG=''
fi

TOOLBOX_DIRTY=`git diff --quiet || echo '-dirty'`
TOOLBOX_VERSION=`git show --no-patch --no-notes --date='format:%Y-%m-%d' \
--pretty='%cd-%h' HEAD`

# Generate version string of the binary as an optional module
echo "toolbox = '${TOOLBOX_VERSION}${TOOLBOX_DIRTY}'" > version.py

virtualenv ${VIRTUAL_ENV_ARGS} .bos-toolbox-env
source .bos-toolbox-env/${VIRTUAL_ENV_BIN}/activate

# Choose the right requirementes file based on interpret major/minor
# version. This split is required by asyncssh
PYTHON_VER=`python -c 'import sys; print(str(sys.version_info[0])+"."+str(sys.version_info[1]))'`
python -m pip install -r requirements/python${PYTHON_VER}.txt


DATA_ARGS="--add-data ./Antminer-S9-all-201812051512-autofreq-user-Update2UBI-NF.tar.gz${PYINST_PATH_SEP}. --add-data bos-version.txt${PYINST_PATH_SEP}."

for i in upgrade firmware system; do
    DATA_ARGS="${DATA_ARGS} --add-data ./${EMBEDDED_BOS_RELEASE}/$i${PYINST_PATH_SEP}$i"
done

pyinstaller $ICON_ARG -F $DATA_ARGS bos-toolbox.py --name bos${BOS_VARIANT}-toolbox

# Cleanup the converted symlinks on Windows
if [ x$MSYSTEM = xMINGW64 ]; then
    git checkout-symlinks
fi