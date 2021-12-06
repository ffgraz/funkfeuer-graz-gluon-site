#!/bin/sh

eval "export FF_$FF_CHANNEL=true"

ENV=$(env | grep "^FF_")
SELF=$(dirname $(readlink -f "$0"))

if ! lxc info gluon 2>/dev/null >/dev/null; then
  bash "$SELF/lxd.sh"
fi

(for e in $ENV; do
  echo "export $e"
done

echo "cd $SELF/../.."

cat "$SELF/ci.sh") | lxc exec gluon bash -

rm -rf /var/www/ffgraz/$FF_CHANNEL
mv output /var/www/ffgraz/$FF_CHANNEL
