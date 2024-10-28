#!/bin/bash

echo "power on" | bluetoothctl

while true; do
  echo "pair E8:EE:CC:36:53:49" | bluetoothctl
  sleep 0.3
  echo "connect E8:EE:CC:36:53:49" | bluetoothctl
  sleep 2

  output=$(echo "info E8:EE:CC:36:53:49" | bluetoothctl)

  if [[ $output == *"Connected: yes"* ]]; then
    noisetorch -i
    break
  fi
done

