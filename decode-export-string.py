#!/usr/bin/python3

import base64
import collections
import json
import zlib
import argparse
import os

################################################################
#
# main

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='converts JSON into a packed import/export string')
    parser.add_argument("exchange_filename", nargs="?", default="bp.txt")
    parser.add_argument("out_filename", nargs="?", default="bp_out.txt")
    opt = parser.parse_args()

    exchange_str = open(opt.exchange_filename, mode='r', encoding='utf-8' ).read().strip()
    version_byte = exchange_str[0]
    #print(version_byte)

    if version_byte=='0':
        decoded = base64.b64decode(exchange_str[1:])
        json_str = zlib.decompress(decoded)
        data = json.loads(json_str, object_pairs_hook=collections.OrderedDict)
        #print( data )
    
        with open(opt.out_filename, 'w', encoding='utf-8') as f:
            json.dump(data, f, separators=(",", ":"), indent=1,
                      ensure_ascii=False )
    else:
        print( "Unsupported version: {0}".format( version_byte ) )
        if os.path.isfile( opt.out_filename ):
            os.remove( opt.out_filename )
