#!/usr/bin/env bash

flags="-out:build/handmade"

if [[ $1 == "run" ]] then
	shift
	odin run src/ $flags $@
	exit 0
fi

odin build src/ $flags $@
