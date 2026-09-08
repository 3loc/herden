#!/bin/sh
set -eu

exec "${ZIG:-zig}" cc -target aarch64-linux-musl "$@"
