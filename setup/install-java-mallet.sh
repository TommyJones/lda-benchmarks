#!/usr/bin/env bash
# Install a JDK and MALLET into ~/opt without needing root.
#
# This machine has no JVM and no passwordless sudo, so we unpack an Eclipse
# Temurin tarball rather than using apt. Everything lands under ~/opt and is
# picked up by setup/env.sh.
set -euo pipefail

OPT="$HOME/opt"
mkdir -p "$OPT"

JDK_VERSION="21.0.5+11"
JDK_TAG="jdk-21.0.5%2B11"
JDK_FILE="OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz"
JDK_URL="https://github.com/adoptium/temurin21-binaries/releases/download/${JDK_TAG}/${JDK_FILE}"

MALLET_VERSION="202108"
MALLET_FILE="Mallet-${MALLET_VERSION}-bin.tar.gz"
MALLET_URL="https://github.com/mimno/Mallet/releases/download/v${MALLET_VERSION}/${MALLET_FILE}"

# --- JDK ----------------------------------------------------------------------
if [ ! -x "$OPT/jdk/bin/java" ]; then
  echo "downloading Temurin JDK ${JDK_VERSION}..."
  curl -fsSL "$JDK_URL" -o "$OPT/$JDK_FILE"
  rm -rf "$OPT/jdk" "$OPT/jdk-tmp"
  mkdir -p "$OPT/jdk-tmp"
  tar -xzf "$OPT/$JDK_FILE" -C "$OPT/jdk-tmp" --strip-components=1
  mv "$OPT/jdk-tmp" "$OPT/jdk"
  rm -f "$OPT/$JDK_FILE"
fi
echo -n "java: "; "$OPT/jdk/bin/java" -version 2>&1 | head -1

# --- MALLET -------------------------------------------------------------------
if [ ! -x "$OPT/mallet/bin/mallet" ]; then
  echo "downloading MALLET ${MALLET_VERSION}..."
  curl -fsSL "$MALLET_URL" -o "$OPT/$MALLET_FILE"
  rm -rf "$OPT/mallet" "$OPT/mallet-tmp"
  mkdir -p "$OPT/mallet-tmp"
  tar -xzf "$OPT/$MALLET_FILE" -C "$OPT/mallet-tmp" --strip-components=1
  mv "$OPT/mallet-tmp" "$OPT/mallet"
  rm -f "$OPT/$MALLET_FILE"
  chmod +x "$OPT/mallet/bin/mallet"
fi

export JAVA_HOME="$OPT/jdk"
export PATH="$JAVA_HOME/bin:$PATH"
echo -n "mallet: "
"$OPT/mallet/bin/mallet" 2>&1 | head -2 | tail -1 || true
echo "java + mallet OK"
