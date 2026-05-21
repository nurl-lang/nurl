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
        gcc-mingw-w64-x86-64 \
        binutils-mingw-w64-x86-64 \
        mingw-w64-tools \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3 /usr/local/bin/python

# --- WASI SDK (clang + libc for wasm32-wasi) -------------------
ARG WASI_SDK_VERSION=24
ARG WASI_SDK_FULL=24.0
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/wasi-sdk.tar.gz \
        "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_FULL}-x86_64-linux.tar.gz" \
    && mkdir -p /opt/wasi-sdk \
    && tar -xzf /tmp/wasi-sdk.tar.gz -C /opt/wasi-sdk --strip-components=1 \
    && rm /tmp/wasi-sdk.tar.gz

# ---------------------------------------------------------------
# Source-independent toolchain steps. These only depend on ARGs and
# network downloads, so we run them BEFORE `COPY . /src` so a code
# edit in the repo doesn't bust their layer cache. Every step from
# here down to the final `COPY` is reused verbatim across rebuilds
# as long as the version pins below stay constant.
# ---------------------------------------------------------------

# --- Cross-build a static libcurl for mingw-w64 with Schannel TLS ------
# Debian ships no mingw libcurl package, so we build one from upstream
# source against Windows' built-in Schannel (no OpenSSL DLL required).
# Static + Schannel means the final .exe produced by /build_windows is
# fully self-contained — no libcurl.dll to ship alongside.
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
    && make -j"$(nproc)" \
    && make install \
    && cd / \
    && rm -rf /tmp/curl.tar.xz /tmp/curl-src

# --- Zig toolchain (for macOS x86_64 cross-compile) ------------------
# Zig ships its own darwin libc stubs (`.tbd` files for libSystem) under
# `lib/libc/darwin/`, so we can produce Mach-O binaries without Apple's
# SDK and without any Apple-owned redistributables. Canvas/audio FFIs
# (Cocoa / AudioToolbox frameworks) are explicitly unsupported on this
# path — a macOS binary from the playground links *only* libSystem.
ARG ZIG_VERSION=0.13.0
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

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

# Compile the NURL runtime for wasm32-wasi so linking later is a
# single clang invocation inside the API container. The canvas object
# is compiled in a second step — it forwards to host imports under
# the "canvas" wasm module (wired up in the browser playground).
RUN /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.wasm.o \
    && /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/canvas_wasm.c -o stdlib/canvas.wasm.o \
    && /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/audio_wasm.c -o stdlib/audio.wasm.o

# Cross-compile the NURL runtime for Windows (x86_64-w64-mingw32) so /build_windows
# can link user IR against a Windows-native runtime.o without rebuilding the runtime
# per request. We use mingw-w64's own gcc as the compiler — it owns the headers
# (`<direct.h>`, `<sys/stat.h>`, …) and the matching CRT/libgcc that the linker
# pulls in later.
#
# HTTP: built with -DNURL_HAVE_LIBCURL against the static libcurl cross-build
# above. CURL_STATICLIB suppresses libcurl's default __declspec(dllimport)
# attributes so the runtime references plain symbols satisfied by libcurl.a.
# A `stdlib/runtime.win.curl` marker tells /build_windows to append the
# required Windows system libs (ws2_32, crypt32, bcrypt, ncrypt, secur32,
# advapi32) at link time.
RUN x86_64-w64-mingw32-gcc -O2 \
        -DNURL_HAVE_LIBCURL -DCURL_STATICLIB \
        -I/opt/curl-mingw/include \
        -c stdlib/runtime.c -o stdlib/runtime.win.o \
    && echo 1 > stdlib/runtime.win.curl

# Cross-compile the NURL runtime for every zig target the playground
# offers — Intel / Apple-Silicon macOS, x86_64 / ARM64 / RISC-V 64
# Linux musl (static), and ARM64 Linux glibc. (No riscv64 glibc: zig
# 0.13's bundled glibc for RISC-V is incomplete.) zig bundles musl,
# glibc and the darwin libSystem stubs for all of these arches, with
# the linker too, so each target costs only one small
# `runtime.<id>.o` (≈125 KB) — no extra base-image packages. None are
# built with -DNURL_HAVE_LIBCURL: HTTP takes runtime.c's no-op `#else`
# stubs, the same "no oheistiedostoja" contract macOS already had.
# These objects ride into the runtime stage via the `COPY .../stdlib`
# below; the API resolves them as `runtime.<id>.o` per ZIG_TARGETS.
#
# Each target is also PRE-WARMED: zig builds + caches that target's
# libc / compiler-rt into ZIG_GLOBAL_CACHE_DIR (baked into the image
# and copied to the runtime stage), so the first playground build per
# target is a fast cache hit, not a multi-second cold libc compile.
# The warm link doubles as a build-time smoke test — a target that
# cannot link fails `docker build` here, not later at request time.
ENV ZIG_GLOBAL_CACHE_DIR=/opt/zig-cache
RUN set -eux; \
    mkdir -p /opt/zig-cache; \
    printf 'int main(void){return 0;}\n' > /tmp/warm.c; \
    build_zig_target() { \
        /opt/zig/zig cc -target "$2" -O2 -c stdlib/runtime.c \
            -o "stdlib/runtime.$1.o"; \
        /opt/zig/zig cc -target "$2" -O2 $3 /tmp/warm.c \
            "stdlib/runtime.$1.o" $4 -o "/tmp/warm-$1"; \
    }; \
    build_zig_target macos-x64          x86_64-macos-none        ""        ""; \
    build_zig_target macos-arm64        aarch64-macos-none       ""        ""; \
    build_zig_target linux-x64-musl     x86_64-linux-musl        "-static" "-lm -lpthread"; \
    build_zig_target linux-arm64-musl   aarch64-linux-musl       "-static" "-lm -lpthread"; \
    build_zig_target linux-arm64-gnu    aarch64-linux-gnu.2.31   ""        "-lm -lpthread"; \
    build_zig_target linux-riscv64-musl riscv64-linux-musl       "-static" "-lm -lpthread"; \
    rm -f /tmp/warm.c /tmp/warm-*

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
        gcc-mingw-w64-x86-64 \
        binutils-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/clang-16 /usr/local/bin/clang

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NURLC_PATH=/opt/nurl/build/nurlc \
    WASI_CLANG=/opt/wasi-sdk/bin/clang \
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
    NURL_MINGW_GCC=/usr/bin/x86_64-w64-mingw32-gcc \
    NURL_RUNTIME_WIN_O=/opt/nurl/stdlib/runtime.win.o \
    NURL_MINGW_CURL_PREFIX=/opt/curl-mingw \
    NURL_ZIG=/opt/zig/zig \
    ZIG_GLOBAL_CACHE_DIR=/opt/zig-cache \
    PATH=/opt/nurl/build:/opt/wasi-sdk/bin:$PATH

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
COPY --from=nurl-build /opt/zig                     /opt/zig
# Pre-warmed zig cache (libc / compiler-rt per cross target). Without
# it the first /build_target per target is a cold multi-second libc
# build; with it that work is a cache hit. The per-target
# runtime.<id>.o objects themselves ride in via the stdlib COPY below.
COPY --from=nurl-build /opt/zig-cache               /opt/zig-cache
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

# WASI SDK (clang + wasm32-wasi sysroot). Needed at runtime to link
# NURL-generated LLVM IR against the wasm build of the runtime.
COPY --from=nurl-build /opt/wasi-sdk /opt/wasi-sdk

# API source (includes static playground).
COPY api/app    /app/app
COPY api/static /app/static

# Output directory for /build artifacts (.ll + native binary) served via /download.
RUN mkdir -p /app/output

EXPOSE 8000

# Non-root user.
RUN useradd --system --uid 1001 --home-dir /app nurl \
    && chown -R nurl:nurl /app /opt/nurl /opt/zig-cache
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
