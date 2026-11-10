# Flutter SDK for local development and CI (web target only).
FROM debian:trixie-slim

ARG FLUTTER_VERSION=3.47.9

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter

ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH} \
    PUB_CACHE=/opt/pub-cache

RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --enable-web \
    && dart --disable-analytics \
    && flutter precache --web \
    && flutter --version

WORKDIR /workspace/app
