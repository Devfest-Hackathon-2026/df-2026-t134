# Firebase Emulator Suite (Auth / Firestore / Storage / UI) for local development.
FROM node:24-trixie-slim

ARG FIREBASE_TOOLS_VERSION=15.35.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "firebase-tools@${FIREBASE_TOOLS_VERSION}" \
    && firebase setup:emulators:firestore \
    && firebase setup:emulators:storage \
    && firebase setup:emulators:ui

WORKDIR /workspace
