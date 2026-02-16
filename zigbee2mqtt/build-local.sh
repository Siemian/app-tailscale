#!/usr/bin/env bash
# Build Zigbee2MQTT addon image locally (e.g. for 32-bit / armv7).
# Usage:
#   ./build-local.sh [arch]   # build for arch (default: amd64, or armv7, aarch64)
#   ./build-local.sh armv7    # build 32-bit image for Raspberry Pi 3 and similar
#
# Requires: docker. Optional: yq, jq (or we parse with grep).
# To use in Home Assistant you must push the image to a registry (e.g. ghcr.io).
# Home Assistant does not support loading addon images from a local file.
set -e

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="${1:-amd64}"

case "$ARCH" in
  amd64)   PLATFORM="linux/amd64" ;;
  aarch64) PLATFORM="linux/arm64/v8" ;;
  armv7)   PLATFORM="linux/arm/v7" ;;
  *)
    echo "Usage: $0 [amd64|aarch64|armv7]"
    exit 1
    ;;
esac

# Detect host arch so we know if we're cross-building
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
  x86_64)  HOST_ARCH="amd64" ;;
  aarch64|arm64) HOST_ARCH="aarch64" ;;
  armv7l|armhf)  HOST_ARCH="armv7" ;;
esac
CROSS_BUILD=
[[ "$HOST_ARCH" != "$ARCH" ]] && CROSS_BUILD=1

if command -v yq &>/dev/null; then
  BUILD_FROM=$(yq -r ".build_from.${ARCH}" "$ADDON_DIR/build.yaml")
else
  BUILD_FROM=$(grep -E "^\s+${ARCH}:" "$ADDON_DIR/build.yaml" | sed -E 's/^[^:]*:\s*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi
if [[ -z "$BUILD_FROM" ]]; then
  echo "Unsupported arch: $ARCH (missing in build.yaml)"
  exit 1
fi

if command -v jq &>/dev/null; then
  VERSION=$(jq -r '.version' "$ADDON_DIR/config.json")
else
  VERSION=$(grep -oE '"version"\s*:\s*"[^"]+"' "$ADDON_DIR/config.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
fi
IMAGE_NAME="zigbee2mqtt-addon-${ARCH}:${VERSION}"

echo "Building $IMAGE_NAME (from=$BUILD_FROM)"
if [[ -n "$CROSS_BUILD" ]]; then
  echo "Cross-build: host is $HOST_ARCH, target is $ARCH (emulation may be slow)."
  if ! docker buildx version &>/dev/null; then
    echo ""
    echo "Cross-building requires Docker Buildx (the legacy 'docker build' cannot emulate other arches)."
    echo ""
    echo "Options:"
    echo "  1. Easiest: push to GitHub and let CI build the image. Add this repo in HA and install."
    echo "  2. Enable Buildx: Docker Desktop has it built-in; try: docker buildx version"
    echo "     If missing: https://docs.docker.com/build/buildx/install/"
    echo "  3. Build on an $ARCH device (e.g. Raspberry Pi for armv7)."
    exit 1
  fi
  # Use a builder that supports multi-platform emulation (docker-container driver).
  # The default builder may be legacy and cannot run armv7 on aarch64.
  if ! docker buildx inspect multiarch-builder &>/dev/null; then
    echo "Creating a Buildx builder for multi-platform (one-time)..."
    docker buildx create --use --name multiarch-builder --driver docker-container
  else
    docker buildx use multiarch-builder 2>/dev/null || true
  fi
  docker buildx build \
    --platform "$PLATFORM" \
    --build-arg BUILD_FROM="$BUILD_FROM" \
    --build-arg BUILD_VERSION="$VERSION" \
    --load \
    -f "$ADDON_DIR/Dockerfile" \
    -t "$IMAGE_NAME" \
    "$ADDON_DIR"
else
  docker build \
    --build-arg BUILD_FROM="$BUILD_FROM" \
    --build-arg BUILD_VERSION="$VERSION" \
    -f "$ADDON_DIR/Dockerfile" \
    -t "$IMAGE_NAME" \
    "$ADDON_DIR"
fi

echo "Built $IMAGE_NAME"
echo ""
echo "To push to GitHub Container Registry and use in Home Assistant:"
echo "  1. docker tag $IMAGE_NAME ghcr.io/YOUR_GITHUB_USER/zigbee2mqtt/${ARCH}:edge"
echo "  2. docker push ghcr.io/YOUR_GITHUB_USER/zigbee2mqtt/${ARCH}:edge"
echo "  3. Add this repo in HA and install Zigbee2MQTT (Supervisor pulls from ghcr.io)."
echo ""
echo "Or let CI do it: push to main or create a release so the Deploy workflow builds and pushes images."
