#!/bin/bash/env sh

nu -c "$@" 2> /dev/null

if [ $? -ne 0 ]; then
  bash -lc "$@"
fi

