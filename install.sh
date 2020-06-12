#!/bin/bash

# Install the program

shopt -s extglob

PREFIX="/usr/local/bin"
case "$1" in
	-@(h|-help) )
		echo "Install the program"
		echo " -p	Set prefix for the installation"
		echo " -h	Show help"
		exit 0
		;;
	-p )
		[ -n "$2" ] && PREFIX="$2"
		;;
esac

install bin/* "${PREFIX}/" && echo "Success!"
