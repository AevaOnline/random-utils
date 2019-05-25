#!/bin/bash

# simple tool to remap symlinks after renaming a home directory
# use this AFTER remapping ~/.ecryptfs and ~/.Private
#
# 


OLD_NAME=${1:-}
NEW_NAME=${2:-}

if [[ -z "$NEW_NAME" ]]; then
	echo "Usage: find ./ -lname '*OLD*' -printf \"%p %l\\n\" | $0 OLD NEW"
	exit
fi


remap() {
	src=$1
	dst=$(echo $2 | sed "s/$OLD_NAME/$NEW_NAME/")

	echo Repointing $src to $dst
	unlink $src
	ln -s $dst $src

	return
}

while read line; do
	remap $line
done
