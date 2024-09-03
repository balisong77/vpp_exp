#!/bin/bash

for i in {12..19}
do
    taskset -c $i stress-ng --cache 1 --cache-level 3 --cache-flush --cache-prefetch --aggressive &
done
