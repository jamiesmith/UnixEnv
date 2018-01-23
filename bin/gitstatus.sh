#!/bin/sh

git remote update > /dev/null

UPSTREAM=${1:-'@{u}'}
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse "$UPSTREAM")
BASE=$(git merge-base @ "$UPSTREAM")

exitCode=0

if [ $LOCAL = $REMOTE ]
then
    echo "Up-to-date"
elif [ $LOCAL = $BASE ]
then
    echo "Need to pull"
    exitCode=1
elif [ $REMOTE = $BASE ]
then
    echo "Need to push"
    exitCode=2
else
    echo "Diverged"
    exitCode=3
fi

exit $exitCode
