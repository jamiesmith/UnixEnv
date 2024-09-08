#!/bin/bash

quiet=""

while getopts "q" option
do
    case $option in 
	q)
	    quiet="yep"
	    ;;
    esac
done
shift $((${OPTIND} - 1)) 

if [ "$(uname)" != "Darwin" ]
then
    quiet="yep"
fi

branch=$(git rev-parse --abbrev-ref HEAD)
repo=$(git config --get remote.origin.url | sed 's|git@github.com:||; s|https://github.com/||; s|.git$||')
repo=$(git config --get remote.origin.url | sed 's|git@github.com:|https://github.com/|;  s|.git$||')

root=$(git rev-parse --show-toplevel)

# Hack in case we're in a symlinked dir
#
pwd=$(/bin/pwd -P)
relativeDir=${pwd/#$root}

if [ -n "$VERBOSE" ]
then
    echo "branch:      [$branch]"     
    echo "repo:        [$repo]"   
    echo "root:        [$root]"   
    echo "relativeDir: [$relativeDir]"          
fi

branchPath=""

url="https://github.com/${repo}"
if [ -n "$relativeDir" ]
then
    branchPath="/tree/${branch}${relativeDir}"
fi

# If the branch is detached then this will just fail
#
url="${repo}${branchPath}"

printf "Repo:\n\n%s\n\n" $url
[ -z "$quiet" ] && open $url
