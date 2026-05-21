# syntax=docker/dockerfile:1.7
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ---------------------------------------------------------------
# Stage 1: bootstrap the NURL compiler (python -> nurlc_py ->
# nurlc_self -> nurlc_self2) using the repo's build.sh.
# ---------------------------------------------------------------
FROM debian:bookworm-slim AS nurl-build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang \
        llvm \
        python3 \
        python3-pip \
        ca-certificates \
        bash \
        coreutils \
        curl \
        xz-utils \
        tar \
        make \
        libsdl2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        zlib1g-dev \
        libsqlite3-dev \
        libpq-dev \
        libzstd-dev \
        pkg-config \
        binaryen \
        binutils-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3 /usr/local/bin/python

# wasm32-wasi is built with `zig cc` (installed below), which bundles
# wasi-libc — no separate WASI SDK download is required.

# ---------------------------------------------------------------
# Source-independent toolchain steps. These only depend on ARGs and
# network downloads, so we run them BEFORE `COPY . /src` so a code
# edit in the repo doesn't bust their layer cache. Every step from
# here down to the final `COPY` is reused verbatim across rebuilds
# as long as the version pins below stay constant.
# ---------------------------------------------------------------

# --- Zig toolchain ---------------------------------------------------
# Zig is the single cross-compiler for the whole release matrix: macOS
# (Mach-O via bundled libSystem stubs), Windows (x86_64-windows-gnu via
# bundled mingw-w64 headers + ucrt + lld), and wasm32-wasi (bundled
# wasi-libc). It also cross-builds the static libcurl below, so every
# target shares one toolchain and one Windows CRT (ucrt). Downloaded
# before the curl build because that build now uses `zig cc`.
ARG ZIG_VERSION=0.16.0
# TARGETARCH is supplied automatically by BuildKit (amd64 / arm64). Map it
# to Zig's arch naming and fetch the matching native Zig. Zig cross-compiles
# to every release target regardless of host arch, so this only decides
# which native Zig binary runs the build — the image builds natively on
# x86_64 (production) and arm64 (Apple Silicon dev) alike.
# NB: Zig's 0.14+ archive naming is `zig-<arch>-linux-<ver>` (arch first),
# the reverse of the pre-0.14 `zig-linux-<arch>-<ver>` layout.
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in \
        amd64) ZIG_ARCH=x86_64 ;; \
        arm64) ZIG_ARCH=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

# Single-word `zig cc`/`zig ar` wrappers targeting Windows — autoconf
# wants CC/AR to be single tokens, and these are reused by the libcurl
# cross-build below.
RUN printf '#!/bin/sh\nexec /opt/zig/zig cc -target x86_64-windows-gnu "$@"\n' > /usr/local/bin/zig-windows-cc \
    && printf '#!/bin/sh\nexec /opt/zig/zig ar "$@"\n' > /usr/local/bin/zig-ar \
    && chmod +x /usr/local/bin/zig-windows-cc /usr/local/bin/zig-ar

# --- Cross-build a static libcurl for Windows with Schannel TLS ------
# Debian ships no Windows libcurl package, so we build one from upstream
# source against Windows' built-in Schannel (no OpenSSL DLL required).
# Static + Schannel means the final .exe produced by /build_windows is
# fully self-contained — no libcurl.dll to ship alongside.
#
# Compiled with `zig cc` (ucrt) so it shares the exact CRT /build_windows
# links against. A libcurl built by the older msvcrt-based mingw-gcc
# references `sys_errlist`/`sys_nerr`, which ucrtbase.dll does not provide
# — that mismatch is what breaks the link. mingw-w64's `windres` (the one
# remaining mingw tool) compiles curl's version-resource .rc; it emits a
# standard COFF object that zig's lld links cleanly.
ARG CURL_VERSION=8.10.1
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/curl.tar.xz \
        "https://curl.se/download/curl-${CURL_VERSION}.tar.xz" \
    && mkdir -p /tmp/curl-src \
    && tar -xJf /tmp/curl.tar.xz -C /tmp/curl-src --strip-components=1 \
    && cd /tmp/curl-src \
    && ./configure \
        --host=x86_64-w64-mingw32 \
        --prefix=/opt/curl-mingw \
        --with-schannel \
        --disable-shared \
        --enable-static \
        --disable-ldap \
        --disable-ldaps \
        --disable-docs \
        --disable-manual \
        --without-libpsl \
        --without-libidn2 \
        --without-zlib \
        --without-brotli \
        --without-zstd \
        --without-nghttp2 \
        --without-librtmp \
        CC=zig-windows-cc AR=zig-ar RANLIB=true STRIP=true \
        RC=x86_64-w64-mingw32-windres \
    && make -C lib -j"$(nproc)" \
    && make -C lib install \
    && make -C include install \
    && cd / \
    && rm -rf /tmp/curl.tar.xz /tmp/curl-src

# ---------------------------------------------------------------
# From here on every step depends on the repo source. Keep this
# block at the very end of stage 1 so editing .nu / .py / .sh
# files doesn't rebuild any of the toolchain layers above.
# ---------------------------------------------------------------
WORKDIR /src
# Copy the whole repo so build.sh can run its full bootstrap + tests.
COPY . /src

# Strip any CRLF line endings that may have crept in via Windows git
# checkouts (core.autocrlf=true). Without this the shebang `#!/usr/bin/env bash`
# is read as `bash\r` and the build fails with "No such file or directory".
RUN find . -type f \( -name '*.sh' -o -name '*.nu' \) -exec sed -i 's/\r$//' {} +

# Run the bootstrap. Skip the test suite — the image build is for the
# API container, not a CI test stage; tests run elsewhere and would
# slow down image construction significantly.
RUN chmod +x build.sh \
    && ./build.sh --no-tests

# Compile the NURL runtime for wasm32-wasi so linking later is a single
# `zig cc` invocation inside the API container. `zig cc -target wasm32-wasi`
# bundles wasi-libc, so no WASI SDK is needed. The canvas/audio objects are
# compiled in further steps — they forward to host imports under the
# "canvas"/"audio" wasm modules (wired up in the browser playground).
RUN /opt/zig/zig cc -target wasm32-wasi -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.wasm.o \
    && /opt/zig/zig cc -target wasm32-wasi -O2 \
        -c stdlib/canvas_wasm.c -o stdlib/canvas.wasm.o \
    && /opt/zig/zig cc -target wasm32-wasi -O2 \
        -c stdlib/audio_wasm.c -o stdlib/audio.wasm.o

# Cross-compile the NURL runtime for Windows (x86_64-windows-gnu) so
# /build_windows can link user IR against a Windows-native runtime.o without
# rebuilding the runtime per request. `zig cc -target x86_64-windows-gnu`
# bundles the mingw-w64 headers (`<direct.h>`, `<sys/stat.h>`, …) and the CRT
# + libgcc equivalents, so no external mingw-w64 toolchain is involved — this
# matches the driver /build_windows uses at request time.
#
# HTTP: built with -DNURL_HAVE_LIBCURL against the static libcurl cross-build
# above. CURL_STATICLIB suppresses libcurl's default __declspec(dllimport)
# attributes so the runtime references plain symbols satisfied by libcurl.a.
# A `stdlib/runtime.win.curl` marker tells /build_windows to append the
# required Windows system libs (ws2_32, crypt32, bcrypt, ncrypt, secur32,
# advapi32) at link time.
RUN /opt/zig/zig cc -target x86_64-windows-gnu -O2 \
        -DNURL_HAVE_LIBCURL -DCURL_STATICLIB \
        -I/opt/curl-mingw/include \
        -c stdlib/runtime.c -o stdlib/runtime.win.o \
    && echo 1 > stdlib/runtime.win.curl

# Cross-compile the NURL runtime for macOS x86_64 (Mach-O). Zig's clang
# targets `x86_64-macos-none` with its bundled libSystem stubs; the
# resulting runtime.mac.o will be linked at request time against user
# IR to produce a standalone Mach-O executable.
#
# HTTP: built WITHOUT -DNURL_HAVE_LIBCURL. runtime.c's #else path
# provides no-op stubs that make the symbols link and report
# HttpErr::Other at runtime — same "no oheistiedostoja" rule the
# playground advertises for macOS.
RUN /opt/zig/zig cc -target x86_64-macos-none -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.mac.o

# ---------------------------------------------------------------
# Stage 2: slim runtime image with Python + FastAPI + the
# bootstrapped nurlc binary.
# ---------------------------------------------------------------
FROM python:3.12-slim-bookworm AS runtime

# binaryen supplies wasm-opt, which we use to Asyncify-wrap modules
# that call into the canvas API (so canvas_sleep can actually yield
# back to the browser event loop).
# clang-16 gives us opaque-pointers-by-default, which matches what modern
# nurlc emits (`%T = type { i64, ptr, ptr }` and loosely-typed libc calls
# like `call i64 @puts(i8* %r)`). The default `clang` package on Debian
# bookworm is clang-14 and still enforces typed pointers, which rejects
# that IR with `error: expected type` / `defined with type … but expected`.
# The FFI -dev packages must match stage 1: build.sh enables curl / openssl /
# sqlite3 / libpq / zlib / zstd in runtime.o based on which `*.pc` files it
# sees, and the native /build link here must then resolve the matching
# -lcurl / -lssl / -lsqlite3 / -lpq / -lz / -lzstd. Keeping both stages in
# sync is what stops `ld: cannot find -lz` at link time.
RUN apt-get update && apt-get install -y --no-install-recommends \
        binaryen \
        clang-16 \
        libc6-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        zlib1g-dev \
        libsqlite3-dev \
        libpq-dev \
        libzstd-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/clang-16 /usr/local/bin/clang

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NURLC_PATH=/opt/nurl/build/nurlc \
    NURL_RUNTIME_WASM_O=/opt/nurl/stdlib/runtime.wasm.o \
    NURL_CANVAS_WASM_O=/opt/nurl/stdlib/canvas.wasm.o \
    NURL_AUDIO_WASM_O=/opt/nurl/stdlib/audio.wasm.o \
    NURL_WORK_ROOT=/opt/nurl \
    NURL_STDLIB_DIR=/opt/nurl/stdlib \
    NURL_EXAMPLES_DIR=/opt/nurl/examples \
    NURL_TESTS_DIR=/opt/nurl/compiler/tests \
    NURL_GRAMMAR_PATH=/opt/nurl/spec/grammar.ebnf \
    NURL_README_PATH=/opt/nurl/README.md \
    NURL_ROADMAP_PATH=/opt/nurl/ROADMAP.md \
    NURL_GOTCHAS_PATH=/opt/nurl/docs/GOTCHAS.md \
    NURL_NATIVE_CLANG=/usr/bin/clang-16 \
    NURL_RUNTIME_WIN_O=/opt/nurl/stdlib/runtime.win.o \
    NURL_MINGW_CURL_PREFIX=/opt/curl-mingw \
    NURL_ZIG=/opt/zig/zig \
    NURL_WINDOWS_TARGET=x86_64-windows-gnu \
    NURL_MACOS_TARGET=x86_64-macos-none \
    NURL_RUNTIME_MAC_O=/opt/nurl/stdlib/runtime.mac.o \
    PATH=/opt/nurl/build:$PATH

WORKDIR /app

COPY api/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Bring in the compiler artifacts and runtime objects.
RUN mkdir -p /opt/nurl/build /opt/nurl/stdlib /opt/nurl/compiler
COPY --from=nurl-build /src/build/nurlc             /opt/nurl/build/nurlc
COPY --from=nurl-build /src/stdlib/runtime.o        /opt/nurl/stdlib/runtime.o
COPY --from=nurl-build /src/stdlib/canvas.o         /opt/nurl/stdlib/canvas.o
COPY --from=nurl-build /src/stdlib/runtime.wasm.o   /opt/nurl/stdlib/runtime.wasm.o
COPY --from=nurl-build /src/stdlib/runtime.win.o    /opt/nurl/stdlib/runtime.win.o
COPY --from=nurl-build /src/stdlib/runtime.win.curl /opt/nurl/stdlib/runtime.win.curl
COPY --from=nurl-build /opt/curl-mingw              /opt/curl-mingw
COPY --from=nurl-build /src/stdlib/runtime.mac.o    /opt/nurl/stdlib/runtime.mac.o
COPY --from=nurl-build /opt/zig                     /opt/zig
COPY --from=nurl-build /src/stdlib/canvas.wasm.o    /opt/nurl/stdlib/canvas.wasm.o
COPY --from=nurl-build /src/stdlib/audio.wasm.o     /opt/nurl/stdlib/audio.wasm.o
COPY --from=nurl-build /src/stdlib                  /opt/nurl/stdlib
COPY --from=nurl-build /src/compiler/nurlc.nu       /opt/nurl/compiler/nurlc.nu
COPY --from=nurl-build /src/examples                /opt/nurl/examples
COPY --from=nurl-build /src/compiler/tests          /opt/nurl/compiler/tests
COPY --from=nurl-build /src/spec                    /opt/nurl/spec
COPY --from=nurl-build /src/README.md               /opt/nurl/README.md
COPY --from=nurl-build /src/ROADMAP.md              /opt/nurl/ROADMAP.md
COPY --from=nurl-build /src/docs/GOTCHAS.md         /opt/nurl/docs/GOTCHAS.md
COPY --from=nurl-build /src/LICENSE-MIT             /opt/nurl/LICENSE-MIT
COPY --from=nurl-build /src/LICENSE-APACHE          /opt/nurl/LICENSE-APACHE
COPY --from=nurl-build /src/NOTICE                  /opt/nurl/NOTICE

# API source (includes static playground).
COPY api/app    /app/app
COPY api/static /app/static

# Output directory for /build artifacts (.ll + native binary) served via /download.
RUN mkdir -p /app/output

EXPOSE 8000

# Non-root user.
RUN useradd --system --uid 1001 --home-dir /app nurl \
    && chown -R nurl:nurl /app /opt/nurl
USER nurl

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys;\
u=urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3);\
sys.exit(0 if u.status==200 else 1)" || exit 1

# --proxy-headers + --forwarded-allow-ips=* makes Starlette trust
# X-Forwarded-Proto / -Host from the reverse proxy so that
# request.base_url reflects the public https://... URL. Without these,
# the OAuth metadata advertised at /.well-known/... would point at the
# container's internal http://<pod>:8000, breaking token exchange.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips=*"]
