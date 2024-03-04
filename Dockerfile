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

FROM node:lts-slim AS qvl-builder

ENV DEBIAN_FRONTEND=noninteractive
# install QVL dependencies
RUN apt-get update \
 && apt-get upgrade --assume-yes -o Dpkg::Options::="--force-confold" \
 && apt-get install --assume-yes --no-install-recommends ca-certificates=\* build-essential=\* cmake=\* \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# build OpenSSL FIPS provider (Latest FIPS validated version as of writing is 3.0.8)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=SC2086,DL3003
RUN apt-get update \
 && apt-get install --assume-yes --no-install-recommends wget=\* \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 && wget --progress=dot:giga https://github.com/openssl/openssl/releases/download/openssl-3.0.8/openssl-3.0.8.tar.gz -O /tmp/openssl.tar.gz \
 && echo "6c13d2bf38fdf31eac3ce2a347073673f5d63263398f1f69d0df4a41253e4b3e /tmp/openssl.tar.gz" | sha256sum --check \
 && mkdir /tmp/openssl && cd /tmp/openssl \
 && tar -xzf /tmp/openssl.tar.gz --strip-components=1 -C /tmp/openssl \
 && ./Configure enable-fips && make -j${nproc} \
 && mkdir /tmp/fips && cp /tmp/openssl/providers/fips.so /tmp/fips && cp /tmp/openssl/providers/fipsmodule.cnf /tmp/fips \
 && rm -rf /tmp/openssl.tar.gz /tmp/openssl

# copy QVL sources
COPY build/qvls /qvl
# build and test QVL
WORKDIR /qvl
RUN ./runUT -DBUILD_LOGS=ON

FROM node:lts-slim AS qvs-builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get upgrade --assume-yes -o Dpkg::Options::="--force-confold" \
 && apt-get install --assume-yes --no-install-recommends ca-certificates=\* build-essential=\* cmake=\* \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
 
COPY --from=qvl-builder --chown=node:node /qvl /qvl
# copy QVS source files
COPY src /qvs/src
COPY configuration-default /qvs/configuration-default
# build QVS
RUN echo 'cmake_QVL_PATH=/qvl/Build/Release/dist' >> /qvs/src/.npmrc # workaround for npm 9+ https://github.com/npm/cli/issues/5852
WORKDIR /qvs/src
RUN npm install npm@latest && npm install
# copy compiled bianries
RUN mkdir -p /qvs/native/lib/ \
 && cp /qvl/Build/Release/dist/lib/*.so /qvs/native/lib/ \
 && cp /qvs/src/qvl/cmake-build-release/Release/*.node /qvs/native/ \
 && rm -rf /qvs/src/qvl/cmake-build-release
# audit
RUN mkdir ../build && npm audit --omit=dev --json > ../build/NpmAuditReport.json || echo "Npm audit failed!"

# copy QVS test files
COPY test /qvs/test
COPY nyc.config.js .eslintrc reporter_config.json /qvs/
# test QVS
WORKDIR /qvs/test
RUN npm install && NODE_ENV=production npm test
# lint test
RUN NODE_ENV=production npm run lint-report

FROM qvl-builder as qvl-builder-debug
WORKDIR /qvl
RUN ./runUT debug -DBUILD_LOGS=ON

FROM qvs-builder as qvs-builder-debug

COPY --from=qvl-builder-debug --chown=node:node /qvl/Build/Debug /qvl/Build/Debug
RUN echo 'cmake_QVL_PATH=/qvl/Build/Debug/dist' >> /qvs/src/.npmrc # workaround for npm 9+ https://github.com/npm/cli/issues/5852
WORKDIR /qvs/src
RUN npm run install-debug
RUN mkdir -p /qvs/native/lib/ \
 && cp /qvl/Build/Debug/dist/lib/*.so /qvs/native/lib/ \
 && cp /qvs/src/qvl/cmake-build-release/Debug/*.node /qvs/native/

FROM scratch as artifacts
COPY --from=qvs-builder /qvs/build /build
COPY --from=qvs-builder /qvs/native /native

FROM scratch as debug-artifacts
COPY --from=qvs-builder-debug /qvs/build /build
COPY --from=qvs-builder-debug /qvs/native /native
COPY --from=qvs-builder /qvs/src/node_modules /src/node_modules
COPY --from=qvs-builder /qvs/test/node_modules /test/node_modules

FROM node:lts-slim as app

LABEL description="Quote Verification Service"

# Remove Node package managers and its dependencies and clear apt cache
RUN rm -rf /usr/local/lib/node_modules/ \
    && rm -rf /usr/local/bin/npm \
    && rm -rf /usr/local/bin/npx \
    && rm -rf /opt \
    && rm -rf /var/cache/apt/archives

# Update the OS and install required dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade --assume-yes -o Dpkg::Options::="--force-confold" && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 

# Add QVS files from builder
COPY --from=qvs-builder --chown=node:node qvs/native /QVS/native
COPY --from=qvs-builder --chown=node:node qvs/configuration-default/config.yml /QVS/configuration-default/config.yml
COPY --from=qvs-builder --chown=node:node qvs/src /QVS/src
COPY --from=qvl-builder --chown=node:node tmp/fips /QVS/src/fips

ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/QVS/native/lib \
    NODE_ENV=production \
    OPENSSL_CONF=/QVS/src/fips/openssl.cnf \
    OPENSSL_MODULES=/QVS/src/fips
USER node
ENTRYPOINT ["nodejs", "--enable-fips", "/QVS/src/bootstrap.js"]
WORKDIR "/QVS"
