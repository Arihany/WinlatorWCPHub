#!/usr/bin/env bash
set -Eeuo pipefail

LLVM_MINGW_TAG="${LLVM_MINGW_TAG:-20251118}"
LLVM_MINGW_REPO="${LLVM_MINGW_REPO:-mstorsjo/llvm-mingw}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/opt/llvm-mingw}"

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE not set}"

cd "$GITHUB_WORKSPACE"

rm -rf src pkg_temp *_WCP out .venv

gh release download "$LLVM_MINGW_TAG" -R "$LLVM_MINGW_REPO" \
  -p '*ucrt-ubuntu-22.04-x86_64.tar.xz' -O llvm.tar.xz --clobber

sudo mkdir -p "$TOOLCHAIN_DIR"
sudo tar -C "$TOOLCHAIN_DIR" --strip-components=1 -xJf llvm.tar.xz
echo "$TOOLCHAIN_DIR/bin" >> "$GITHUB_PATH"
