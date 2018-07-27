#!/bin/bash
for i in `seq 1 $1`
do
    logger -p local6.error Hello from message number $i
done
