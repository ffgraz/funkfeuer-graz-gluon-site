#!/bin/sh

eval "export FF_${FF_CHANNEL}=true"

ENV=$(env | grep "^FF_")
SELF=$(dirname $(readlink -f "$0"))

if ! lxc info gluon 2>/dev/null >/dev/null; then
  bash "$SELF/lxd.sh"
fi

(for e in $ENV; do
  echo "export $e"
done

echo "cd $SELF/../.."

cat "$SELF/ci.sh") | lxc exec gluon -- su "$(id -un)" -s /bin/bash -c "bash -"

if [ ! -e openwrt/key* ]; then
  cp -v /storage/ffgraz/key* .
fi

if [ -v FF_experimental ] || [ -v FF_upstream ] || [ -v FF_dev ]; then
  contrib/sign.sh /storage/ffgraz/nightly-key output/images/sysupgrade/${FF_CHANNEL}.manifest
fi

rm -rf /storage/ffgraz/www/$FF_CHANNEL
mv output /storage/ffgraz/www/$FF_CHANNEL
