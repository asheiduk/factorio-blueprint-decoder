#!/bin/bash

# compact json
jq -c . |
(
	# version
	echo "0" 
	# data
	zlib-flate -compress | base64 
)
