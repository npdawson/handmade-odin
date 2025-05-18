#!/usr/bin/env bash

platform="SDL"

flags="-out:build/handmade -define:PLATFORM=${platform}"

if [[ $1 == "run" ]] then
	shift
	odin run src/ $flags $@
	exit 0
fi

odin build src/ $flags $@
