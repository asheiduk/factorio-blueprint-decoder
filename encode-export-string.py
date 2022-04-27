#!/usr/bin/python3

import base64
import collections
import json
import zlib
import argparse

################################################################
#
# main

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='converts JSON into a packed import/export string')
    parser.add_argument("json_filename", nargs="?", default="all.txt")
    parser.add_argument("out_filename", nargs="?", default="out.txt")
    opt = parser.parse_args()

    json_str = open(opt.json_filename, mode='r', encoding='utf-8' ).read().strip()
    data = json.loads(json_str, object_pairs_hook=collections.OrderedDict)
    #print( data )

    json_str = json.dumps(data, separators=(",", ":"),
                      ensure_ascii=False ).encode("utf8")
    #print( json_str )

    compressed = zlib.compress(json_str, 9)
    encoded = base64.b64encode(compressed)
    #print( encoded.decode() )
    
    open(opt.out_filename, "w").write('0' + encoded.decode())

