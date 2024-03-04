#!/bin/bash

#
# Copyright (c) 2022, Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither the name of Intel Corporation nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

function fail {
    printf '%s\n' "$1" >&2 ## Send message to stderr.
    exit "${2-1}" ## Return a code specified by $2, or 1 by default.
}

# Get absolute path to the script itself
SCRIPT_DIR="$(cd "$(dirname "$0")" || exit 1; pwd)"

DEBUG=false
OPTS=$(getopt -o "d" -l "debug" -n "$0" -- "$@")
if [ $? != 0 ] ; then
  fail "Failed parsing args usage: build.sh [-d|--debug] [qvlPath]"
fi
eval set -- ${OPTS}
while :
do
  case $1 in
    -d | --debug) DEBUG=true; shift ;;
    --) shift; break ;;
  esac
done

# Check if QVL path has been provided
QVL_PATH_ARG=$1
if [ -z "$QVL_PATH_ARG" ]
  then
    QVL_PATH="$(cd "$(dirname "$SCRIPT_DIR"/../QVL/Src)" || exit 2; pwd)/Src"
else
  QVL_PATH="$(cd "$(dirname "$QVL_PATH_ARG")" || exit 2; pwd)/$(basename "$QVL_PATH_ARG")"
fi

echo "QVL_PATH=$QVL_PATH"
cd "$QVL_PATH" || fail "Failed to access QVL path" 2

# Check if QVL_PATH contains absolute path
case $QVL_PATH in
     /*) ;;
     *) fail "Absolute path to QVL sources should be provided" 3 ;;
esac

# Create local copy of QVL sources for Docker context
copyQvlSources() {
  mkdir -p "$SCRIPT_DIR/build"
  cp -R "$QVL_PATH" "$SCRIPT_DIR/build/qvls"
  rm -rf "$SCRIPT_DIR/build/qvls/Build" "$SCRIPT_DIR"/build/qvls/cmake-build*
}

if ! copyQvlSources "$@"; then
    fail "Error when copying QVL" 5
fi

# Build Docker Image
function buildDocker() {
  docker build --target artifacts --output="$SCRIPT_DIR" "$SCRIPT_DIR"
  if [ "$DEBUG" = true ]; then
    docker build --target debug-artifacts --output="$SCRIPT_DIR" "$SCRIPT_DIR"
  fi
  docker build --target app "$SCRIPT_DIR" -t qvs
}

if ! buildDocker; then
    fail "Error when building Docker image" 7
fi

pushd ${SCRIPT_DIR}/samples/simple-signing-service || fail "Failed to access SSS dir" 4
./build.sh
popd || fail "Failed leave SSS dir" 5

echo "Build - Done"
