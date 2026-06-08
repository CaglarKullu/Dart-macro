#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_DIR="/opt/flutter"
FLUTTER_VERSION="3.27.4"

# Suppress git dubious ownership warnings in containers
git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true

# Install Flutter SDK if not already present
if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Installing Flutter ${FLUTTER_VERSION}..."

  # Prerequisites
  apt-get install -y -qq curl git unzip xz-utils zip libglu1-mesa 2>/dev/null || true

  # Download and extract Flutter
  curl -fsSL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar xJ -C /opt/

  echo "Flutter installed at ${FLUTTER_DIR}"
else
  echo "Flutter already installed at ${FLUTTER_DIR}"
fi

# Add Flutter/Dart to PATH for this session
export PATH="${FLUTTER_DIR}/bin:${PATH}"

# Persist to session environment file
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${FLUTTER_DIR}/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Disable Flutter analytics in CI/automated environments
"${FLUTTER_DIR}/bin/flutter" config --no-analytics 2>/dev/null || true

# Install project dependencies
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
"${FLUTTER_DIR}/bin/dart" pub get

echo "Environment ready. Dart $(${FLUTTER_DIR}/bin/dart --version 2>&1)"
