#!/bin/dash
discord_pids=$(ps aux | ~/.cargo/bin/rg 'discord' | awk '{print $2}')

[ -z "$discord_pids" ] && exit 0

paused=0

for pid in $discord_pids; do
  state=$(ps -ho state -p $pid)
  [ "$state" = "T" ] && paused=1 && break
done

for pid in $discord_pids; do
  [ $paused -eq 1 ] && kill -CONT $pid || kill -STOP $pid
done

