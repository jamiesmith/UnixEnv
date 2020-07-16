#!/bin/bash

branch=$(git rev-parse --abbrev-ref HEAD)

repo=$(git config --get remote.origin.url | sed 's|git@github.com:||; s|https://github.com/||; s|.git$||')

root=$(git rev-parse --show-toplevel)
relativeDir=${PWD/#$root}

echo root is $root

url="https://github.com/${repo}/tree/${branch}$relativeDir"
url=${url%*/tree/master}

echo opening $url

open $url
