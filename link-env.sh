#!/bin/bash

if [ -n "$1" ]
then
    TARGET_LOC="$1"
else
    TARGET_LOC="${HOME}"
fi

if [ -z "${TARGET_LOC}" ]
then
    echo ERROR: TARGET_LOC dir not set
    exit 1
fi

function linkToFile
{
    
    sourceFileName=$1
    sourceFilePath=${SOURCE_DIR}/${sourceFileName}

    destFilePath=${TARGET_LOC}/.$(echo $sourceFileName | tr -d "_")

    echo "Processing $destFilePath"

	if [ -L "$destFilePath" ]
	then
	    printf "\tRemoving stale $destFilePath\n"
	    rm -f "$destFilePath"
    fi

    if [ -f "$destFilePath" ]
    then
	    echo "ERROR: $destFilePath is a regular file, aborting"
	    exit 1
    fi
    printf "\tlinking $sourceFilePath to $destFilePath\n"
    ln -s "$sourceFilePath" "$destFilePath"
}

SOURCE_DIR=$(pwd)

echo Linking from source dir $SOURCE_DIR

for file in _*
do
    linkToFile $file
done
