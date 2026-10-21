#!/bin/sh
# Build the shannon package, the way shannon's own CI does. Runs in the
# build container (see build.sh):
#
#   scripts/build-shannon.sh SRCDIR OUTDIR
set -eu

SRC=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)

# The linker for the target comes from shannon's .cargo/config.toml
cd "$SRC"
cargo deb --target aarch64-unknown-linux-gnu --output "$OUT/"
