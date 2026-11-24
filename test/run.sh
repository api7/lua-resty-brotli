#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Force both directions through several native output buffers with binary data.
head -c 262144 /dev/urandom > "$tmp/input"
brotli -q 3 -o "$tmp/native.br" "$tmp/input"
luajit test/streams.lua "$tmp/input" "$tmp/native.br" "$tmp/lua.br"
brotli -d -o "$tmp/output" "$tmp/lua.br"
cmp "$tmp/input" "$tmp/output"
