#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash multimarkdown tree

SELF=$(dirname $(readlink -f "$0"))

markdown "$SELF/../README.md"
mv "$SELF/README.html" /tmp/index.html

echo '<style>body { background: #181a1b; color: #e8e6e3; font-family: sans-serif; } a { color: #00a3e0; }</style>' > /var/www/ffgraz/index.html
cat /tmp/index.html >> /var/www/ffgraz/index.html
tree /var/www/ffgraz -H "" >> /var/www/ffgraz/index.html
