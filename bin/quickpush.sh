#!/bin/bash

msg="$*"

if [ -z "$msg" ]
then
    echo "Commit message required, aborting"
    exit 9
fi

git status
git add .
git commit -am "$msg"
git push

