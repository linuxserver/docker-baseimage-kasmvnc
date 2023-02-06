#!/bin/bash
while :
do
    if [[ ! $(/usr/bin/pulseaudio --check) ]]; then
        /usr/bin/pulseaudio --start
    fi
    sleep 10
done
