#!/bin/sh

lxc launch images:debian/12 -c security.privileged=true gluon
yes "
" | lxc exec gluon adduser "$USER"
SRC=$(readlink -f ..)
lxc exec gluon apt update
lxc exec gluon apt install build-essential python2 libncurses-dev unzip -y
lxc config device add gluon src "target=$SRC" "path=$SRC"
