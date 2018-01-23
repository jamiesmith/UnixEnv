#!/bin/bash

branch=$(git rev-parse --abbrev-ref HEAD)

repo=$(git config --get remote.origin.url | sed 's|git@github.com:||; s|https://github.com/||; s|.git$||')

if [ "$branch" = "master" ]
then
    url="https://github.com/${repo}.git"
else
    url="https://github.com/${repo}/tree/${branch}"
fi

echo opening $url

open $url
