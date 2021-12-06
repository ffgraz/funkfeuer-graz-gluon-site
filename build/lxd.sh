#!/bin/sh

lxc launch images:debian/12 -c security.privileged=true gluon
yes "
" | lxc exec gluon adduser "$(id -un)" --uid "$(id -u)"
SRC=$(readlink -f ..)
lxc exec gluon apt update
yes | lxc exec gluon apt install build-essential python2 libncurses-dev unzip make git gawk wget
lxc config device add gluon src disk "source=$SRC" "path=$SRC"
