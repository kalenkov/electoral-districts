#!/bin/sh
for d in */
do
    echo "$d"
    cd $d
    make -f ../../Makefile clean_all 
    cd ..
done
