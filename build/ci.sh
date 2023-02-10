#!/bin/bash

shopt -s nullglob

make update

KEYS=(key-build*)
if [ "${#KEYS[*]}" -ge 1 ]; then
  mv -v key-build* openwrt
fi

cores=$(( $(cat /proc/cpuinfo | awk '/^processor/{print $3}' | tail -1) + 1 ))

PARAMS=(GLUON_AUTOUPDATER_BRANCH=$FF_CHANNEL)

if [ ! -z "$FF_experimental" ] || [ ! -z "$FF_upstream" ] || [ ! -z "$FF_dev" ]; then
  PARAMS+=(GLUON_AUTOUPDATER_ENABLED=1)
fi

if [ ! -z "$FF_RELEASE" ]; then
  PARAMS+=(GLUON_RELEASE="$FF_RELEASE")
fi

echo "Cleaning..."

rm -rf output

# for target in $(make list-targets); do
#   make "GLUON_TARGET=$target" clean
# done

for target in $(make list-targets); do
  echo "Building $target..."
  make "GLUON_TARGET=$target" "-j$cores" "${PARAMS[@]}"
done

make manifest "${PARAMS[@]}"
