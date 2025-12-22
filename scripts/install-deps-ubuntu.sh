set -Eeuo pipefail

SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive

$SUDO apt-get -yqq update
$SUDO apt-get -yqq install --no-install-recommends \
  ca-certificates \
  curl \
  xz-utils \
  jq \
  git \
  glslang-tools \
  build-essential \
  python3 \
  python3-venv \
  python3-pip \
  pkg-config \
  cmake \
  ninja-build \
  zstd \
  dos2unix \
  perl \
  tar \
  unzip \
  llvm \
  crossbuild-essential-arm64
