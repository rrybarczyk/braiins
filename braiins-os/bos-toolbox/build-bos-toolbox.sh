#!/bin/sh
# Builds the bos-toolbox image on Linux and Windows (requires cygwin)

set -e

[ x$1 = x ] && {
    echo "Braiins OS ssh archive is missing"
    echo "Synopsis: $0 BRAIINS_OS_ARCHIVE"
    exit 1
}

EMBEDDED_BOS_RELEASE=${1%.tar.gz}
echo $EMBEDDED_BOS_RELEASE > bos-version.txt
tar xvzf $1

virtualenv --python=/usr/bin/python3 .bos-toolbox-env
source .bos-toolbox-env/bin/activate

# Choose the right requirementes file based on interpret major/minor
# version. This split is required by asyncssh
PYTHON_VER=`python -c 'import sys; print(str(sys.version_info[0])+"."+str(sys.version_info[1]))'`
python3 -m pip install -r requirements/python${PYTHON_VER}.txt

if [ x$MSYSTEM = xMINGW64 ]; then
    PYINST_PATH_SEP=';'
else
    PYINST_PATH_SEP=':'
fi

DATA_ARGS="--add-data ./Antminer-S9-all-201812051512-autofreq-user-Update2UBI-NF.tar.gz${PYINST_PATH_SEP}. --add-data bos-version.txt${PYINST_PATH_SEP}."

for i in upgrade firmware system; do
    DATA_ARGS="${DATA_ARGS} --add-data ./${EMBEDDED_BOS_RELEASE}/$i${PYINST_PATH_SEP}$i"
done

pyinstaller -F $DATA_ARGS bos-toolbox.py
