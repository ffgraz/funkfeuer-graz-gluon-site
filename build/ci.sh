#!/bin/bash

make update

cores=$(( $(cat /proc/cpuinfo | awk '/^processor/{print $3}' | tail -1) + 1 ))

PARAMS=()

if [ ! -z "$FF_experimental" ]; then
  PARAMS+=(GLUON_AUTOUPDATER_BRANCH=experimental GLUON_AUTOUPDATER_ENABLED=1)
fi

if [ ! -z "$FF_stable" ]; then
  # no autoupdates by default
  PARAMS+=(GLUON_AUTOUPDATER_BRANCH=stable)
fi

echo "Cleaning..."

rm -rf output

for target in $(make list-targets); do
  make "GLUON_TARGET=$target" clean
done

for target in $(make list-targets); do
  echo "Building $target..."
  make "GLUON_TARGET=$target" "-j$cores" "${PARAMS[@]}"
done

make manifest "${PARAMS[@]}"
