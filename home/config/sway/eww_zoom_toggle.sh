#!/bin/sh

myopia=$(eww get myopia)
if [ "$myopia" = "true" ]; then
  eww update myopia="false"
else
  eww update myopia="true"
fi

