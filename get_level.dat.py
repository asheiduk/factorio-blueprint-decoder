#!/usr/bin/python
import os
import sys
import shutil
import zipfile
import zlib
import argparse
import datetime

def error(*args):
    print(*args, file=sys.stderr, flush=True)
    
def delete_folder( folder_name ):
    if os.path.isdir( folder_name ):
        shutil.rmtree( folder_name )

def get_leveldat( save_file_name, temporary_directory ):
    delete_folder( temporary_directory )
    
    with zipfile.ZipFile( save_file_name, 'r') as zip_ref:
        zip_ref.extractall( temporary_directory )

    s2 = 0
    for root, dirs, files in os.walk( temporary_directory ):
        for file in files:
            if file=='level-init.dat':
                index = 0
                file_name = '{0}\level.dat{1}'.format(root,index)
                # unpacking the file    
                while os.path.isfile( file_name ):
                    #print(file_name)
                    with open( file_name, 'rb' ) as file_to_read:
                        compressed_data = file_to_read.read()
                        decompressed_data = zlib.decompress(compressed_data)
                        s2 += sys.stdout.buffer.write(decompressed_data)
                        index += 1
                        file_name = '{0}\level.dat{1}'.format(root,index)
                
                # checking the file size
                with open('{0}\level.datmetadata'.format(root), 'rb') as level_datmetadata:
                    s1 = int.from_bytes( level_datmetadata.read(), 'little', signed=False )
                    if s1 != s2:
                        error(f"ERROR - incorrect size of the unpacked file.")
                        exit(2)
                    else:
                        error(f"The file size is correct {s1} = {s2}")

                delete_folder( temporary_directory )
                
################################################################
#
# main

if __name__ == "__main__":
    temporary_directory = ""
    
    parser = argparse.ArgumentParser(description="Unpacks the level.dat file from the save. Attention!!! The temporary directory will be completely deleted with all files!")
    parser.add_argument("save_file_name", nargs="?", default="_autosave1.zip")
    parser.add_argument("temporary_directory", nargs="?", default="0_0")
    opt = parser.parse_args()

    if opt.temporary_directory=="0_0":
        dt_now = datetime.datetime.now()
        temporary_directory = "{0:04}{1:02}{2:02}_{3:02}{4:02}_temp_for_leveldat".format(dt_now.year,dt_now.month,dt_now.day,dt_now.hour,dt_now.minute)
    else:
        temporary_directory = opt.temporary_directory

    get_leveldat( opt.save_file_name, temporary_directory )
