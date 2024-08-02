#!/bin/bash

for i in {11..12}
do
    taskset -c $i stress-ng --cache 1 --cache-flush --cache-prefetch --aggressive &
done
