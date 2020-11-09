#!/bin/bash

# usage: decode-export-string < foo.export > foo.json

read -N 1 version
[ "$version" = "0" ] || {
 	echo 1>&2 "Unsupported version $version"
 	exit 1;
}
base64 -d| zlib-flate -uncompress