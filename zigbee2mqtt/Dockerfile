ARG BUILD_FROM
FROM $BUILD_FROM as base

ENV LANG C.UTF-8
# Version format X.Y.Z-A; stable tarball uses X.Y.Z (e.g. 2.8.0-1 -> 2.8.0)
ARG BUILD_VERSION=2.8.0-1

RUN apk add --no-cache socat tini nodejs eudev && \
    # Validation to confirm that curl is installed in the base image.
    curl --version || (echo "curl missing" && exit 1)

# Dependencies and build
FROM base as dependencies_and_build

ARG BUILD_ARCH
# More memory for Node (helps under QEMU emulation for armv7)
ENV NODE_OPTIONS=--max-old-space-size=4096
# pnpm uses frozen-lockfile by default in CI (avoids --frozen-lockfile flag parsing issues)
ENV CI=true

RUN set -e && \
    if [ "${BUILD_ARCH}" = "armv7" ]; then export NODE_OPTIONS="--max-old-space-size=6144"; fi && \
    apk add --no-cache --virtual .buildtools npm make gcc g++ linux-headers udev git python3 && \
    if [ "${BUILD_VERSION}" = "edge" ]; \
    then \
        echo "Installing Edge version" && \
        git clone -b dev --single-branch --depth 1 \
            https://github.com/Koenkk/zigbee2mqtt.git /app && \
        mkdir /app/dist && \
        jq -n --arg commit $(eval cd /app;git rev-parse --short HEAD) '$commit' > /app/dist/.hash ; \
    else \
        echo "Installing Stable version ${BUILD_VERSION%-*}" && \
        curl -sfL -o "/app.tar.gz" \
            "https://github.com/Koenkk/zigbee2mqtt/archive/${BUILD_VERSION%-*}.tar.gz" && \
        tar xzvf "/app.tar.gz" && rm "/app.tar.gz" && \
        mv -v "zigbee2mqtt-${BUILD_VERSION%-*}" app && \
        mkdir /app/dist && \
        jq -n --arg commit ${BUILD_VERSION%-*} '$commit' > /app/dist/.hash ; \
    fi && \
    echo "Installed Zigbee2MQTT @ version $(cat /app/dist/.hash)" && \
    cd /app && \
    if [ "${BUILD_ARCH}" = "armv7" ]; then \
        NODE_OPTIONS="--max-old-space-size=6144" npm install -g $(jq -r '.packageManager' package.json) --ignore-scripts ; \
    else \
        ( corepack enable 2>/dev/null && corepack prepare $(jq -r '.packageManager' package.json) --activate ) || \
        npm install -g $(jq -r '.packageManager' package.json) ; \
    fi && \
    ( [ "${BUILD_ARCH}" = "armv7" ] && echo "child-concurrency=1" >> .npmrc ; true ) && \
    pnpm install --no-optional --unsafe-perm && \
    pnpm run build && \
    rm -rf node_modules && \
    pnpm install --no-optional --unsafe-perm --prod && \
    rm -rf $(find ./node_modules/.pnpm/ -wholename "*/@serialport/bindings-cpp/prebuilds" -type d) && \
    pnpm rebuild @serialport/bindings-cpp

# Release
FROM base as release

WORKDIR /app

COPY rootfs /
RUN chmod +x /docker-entrypoint.sh
COPY --from=dependencies_and_build /app/node_modules ./node_modules
COPY --from=dependencies_and_build /app/dist ./dist
COPY --from=dependencies_and_build /app/package.json /app/LICENSE /app/index.js ./

ENV NODE_ENV production

HEALTHCHECK --interval=1m --timeout=3s --start-period=30s --start-interval=3s \
    CMD curl -f http://localhost:8099/

ENTRYPOINT [ "/sbin/tini", "--", "/docker-entrypoint.sh"]
