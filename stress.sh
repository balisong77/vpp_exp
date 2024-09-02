#!/bin/bash

for i in {10..19}
do
    taskset -c $i stress-ng --cache 1 --cache-level 1 --cache-flush --cache-prefetch --aggressive &
done
