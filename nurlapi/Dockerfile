# syntax=docker/dockerfile:1.7
# Stage 1: Build the NURL compiler and cross-target runtimes
FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang-16 \
        llvm \
        python3 \
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
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/clang-16 /usr/local/bin/clang

RUN ln -sf /usr/bin/python3 /usr/local/bin/python

# --- WASI SDK (clang + libc for wasm32-wasi) -------------------
ARG WASI_SDK_VERSION=24
ARG WASI_SDK_FULL=24.0
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/wasi-sdk.tar.gz \
        "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_FULL}-x86_64-linux.tar.gz" \
    && mkdir -p /opt/wasi-sdk \
    && tar -xzf /tmp/wasi-sdk.tar.gz -C /opt/wasi-sdk --strip-components=1 \
    && rm /tmp/wasi-sdk.tar.gz

# --- Static libcurl for mingw-w64 -------------------
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

# --- Zig toolchain (for macOS cross-compile) ------------------
ARG ZIG_VERSION=0.13.0
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

WORKDIR /src
COPY . /src
RUN find . -type f \( -name '*.sh' -o -name '*.nu' \) -exec sed -i 's/\r$//' {} +

# Bootstrap nurlc (image build skips tests; they run in CI elsewhere)
RUN chmod +x build.sh && ./build.sh --no-tests

# Compile runtime objects
# 1. Native Linux
# build.sh --no-tests already produced stdlib/runtime.native.o (a plain
# ELF object — runtime.o itself is LLVM bitcode under -flto and won't
# link with a stock clang/ld). The whole stdlib/ dir is copied below.

# 2. wasm32-wasi
RUN /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.wasm.o \
    && /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/canvas_wasm.c -o stdlib/canvas.wasm.o \
    && /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/audio_wasm.c -o stdlib/audio.wasm.o

# 3. Windows (x86_64-w64-mingw32) — two runtime variants.
# mingw's PE linker does not honour --gc-sections for COFF, so unused
# runtime code (notably static libcurl + its bcrypt/crypt32/secur32
# Schannel deps) cannot be dropped at link time. Instead we ship a lean
# default object built WITHOUT libcurl, plus a curl-enabled variant the
# server selects only when the program references the nurl_curl_* bridge
# (i.e. pulls in stdlib/ext/http.nu). Non-HTTP exes thus skip libcurl
# entirely. -ffunction-sections/-fdata-sections are kept so the user IR
# can still be trimmed and in case a future ld improves PE gc.
RUN x86_64-w64-mingw32-gcc -O2 \
        -ffunction-sections -fdata-sections \
        -c stdlib/runtime.c -o stdlib/runtime.win.o
RUN x86_64-w64-mingw32-gcc -O2 \
        -ffunction-sections -fdata-sections \
        -DNURL_HAVE_LIBCURL -DCURL_STATICLIB \
        -I/opt/curl-mingw/include \
        -c stdlib/runtime.c -o stdlib/runtime.win.curl.o \
    && echo 1 > stdlib/runtime.win.curl

# 4. macOS x86_64 (kept as runtime.mac.o for /build_macos backwards
#    compat; /build_target reads the same triple via runtime.macos-x64.o).
RUN /opt/zig/zig cc -target x86_64-macos-none -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.mac.o

# 5. Every /build_target zig target gets a pre-built runtime.<id>.o.
#    The same loop pre-warms zig's per-target libc + compiler-rt cache
#    (a small `int main(){return 0;}` link) so the first cross-compile
#    request lands as a cache hit, not a multi-second cold libc build.
#    A failure in this loop turns into a `docker build` failure, which
#    doubles as a smoke test that every advertised target actually
#    links in this image.
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

# Compile the NURL API binary itself
RUN ./nurl.sh nurlapi/main.nu nurlapi/nurlapi

# Stage 2: Final runtime image
FROM debian:bookworm-slim

# FFI -dev packages must match the builder stage above: build.sh enables
# curl / openssl / sqlite3 / libpq / zlib / zstd in runtime.o from the
# `*.pc` files it sees, and the native build link here must resolve the
# matching -lcurl / -lssl / -lsqlite3 / -lpq / -lz / -lzstd. Keeping both
# stages in sync is what stops `ld: cannot find -lz` at link time.
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang-16 \
        libcurl4-openssl-dev \
        libssl-dev \
        zlib1g-dev \
        libsqlite3-dev \
        libpq-dev \
        libzstd-dev \
        ca-certificates \
        binaryen \
        gcc-mingw-w64-x86-64 \
        binutils-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/clang-16 /usr/bin/clang

ENV NURLC_PATH=/opt/nurl/build/nurlc \
    NURL_STDLIB_DIR=/opt/nurl/stdlib \
    NURL_WORK_ROOT=/opt/nurl \
    NURL_STATIC_DIR=/app/static \
    WASI_CLANG=/opt/wasi-sdk/bin/clang \
    NURL_RUNTIME_WASM_O=/opt/nurl/stdlib/runtime.wasm.o \
    NURL_CANVAS_WASM_O=/opt/nurl/stdlib/canvas.wasm.o \
    NURL_AUDIO_WASM_O=/opt/nurl/stdlib/audio.wasm.o \
    NURL_RUNTIME_WIN_O=/opt/nurl/stdlib/runtime.win.o \
    NURL_RUNTIME_WIN_CURL_O=/opt/nurl/stdlib/runtime.win.curl.o \
    NURL_MINGW_CURL_PREFIX=/opt/curl-mingw \
    NURL_MINGW_GCC=/usr/bin/x86_64-w64-mingw32-gcc \
    NURL_ZIG=/opt/zig/zig \
    ZIG_GLOBAL_CACHE_DIR=/opt/zig-cache \
    NURL_MACOS_TARGET=x86_64-macos-none \
    NURL_RUNTIME_MAC_O=/opt/nurl/stdlib/runtime.mac.o \
    NURL_EXAMPLES_DIR=/opt/nurl/examples \
    NURL_TESTS_DIR=/opt/nurl/compiler/tests \
    NURL_README_PATH=/opt/nurl/README.md \
    NURL_GRAMMAR_PATH=/opt/nurl/spec/grammar.ebnf \
    NURL_OUTPUT_DIR=/app/output \
    PATH=/opt/nurl/build:/usr/local/bin:/usr/bin:/bin:$PATH

WORKDIR /app
COPY --from=builder /src/nurlapi/nurlapi /app/nurlapi
COPY --from=builder /src/nurlapi/static /app/static

# Stamp the deployed version into the playground UI. api-deploy.yml passes the
# released semver via --build-arg NURL_VERSION=vX.Y.Z; local builds get "dev".
ARG NURL_VERSION=dev
RUN sed -i "s/__NURL_VERSION__/${NURL_VERSION}/g" /app/static/index.html

# Exact build identity (the git SHA), reported by /health as build_id.
# The Worker compares it against its NURL_DEPLOY_ID var and recycles a
# container instance still running an older image — deploys reach the
# LIVE instance deterministically instead of waiting for an idle window
# that steady public traffic may never allow.
ARG NURL_BUILD_ID=dev
ENV NURL_BUILD_ID=${NURL_BUILD_ID}

# Bring in all cross-compilation artifacts
RUN mkdir -p /opt/nurl/build /opt/nurl/stdlib /app/output /opt/nurl/examples /opt/nurl/compiler /opt/nurl/spec /opt/nurl/docs
COPY --from=builder /src/build/nurlc             /opt/nurl/build/nurlc
COPY --from=builder /src/stdlib                  /opt/nurl/stdlib
COPY --from=builder /opt/wasi-sdk                /opt/wasi-sdk
COPY --from=builder /opt/curl-mingw              /opt/curl-mingw
COPY --from=builder /opt/zig                     /opt/zig
# Per-target runtime objects are inside /src/stdlib (covered above) but
# the pre-warmed cache rides separately so the first /build_target per
# target is a fast cache hit instead of a multi-second cold libc build.
COPY --from=builder /opt/zig-cache               /opt/zig-cache
COPY --from=builder /src/examples                /opt/nurl/examples
COPY --from=builder /src/compiler/tests          /opt/nurl/compiler/tests
COPY --from=builder /src/README.md               /opt/nurl/README.md
COPY --from=builder /src/ROADMAP.md              /opt/nurl/ROADMAP.md
COPY --from=builder /src/CHANGELOG.md            /opt/nurl/CHANGELOG.md
COPY --from=builder /src/CONTRIBUTING.md         /opt/nurl/CONTRIBUTING.md
# Whole docs/ tree (was just GOTCHAS.md) so every topic doc the README
# links to renders instead of 404ing; bench/ for the benchmark pages.
COPY --from=builder /src/docs                    /opt/nurl/docs
COPY --from=builder /src/bench                   /opt/nurl/bench
COPY --from=builder /src/LICENSE-MIT             /opt/nurl/LICENSE-MIT
COPY --from=builder /src/LICENSE-APACHE          /opt/nurl/LICENSE-APACHE
COPY --from=builder /src/NOTICE                  /opt/nurl/NOTICE
COPY --from=builder /src/spec                    /opt/nurl/spec

# ── Run unprivileged (M11) ────────────────────────────────────────────
# The server compiles untrusted source with nurlc/clang/zig; none of that
# needs root. Writable surface is exactly what the tools touch at request
# time: /app/output (build artifacts), /opt/zig-cache (zig target cache),
# /tmp (compiler temps), plus a HOME for zig/clang dotfiles.
RUN groupadd -g 10001 nurl \
    && useradd -m -u 10001 -g nurl -d /home/nurl -s /usr/sbin/nologin nurl \
    && chown -R nurl:nurl /app/output /opt/zig-cache
USER nurl
ENV HOME=/home/nurl

EXPOSE 8000
CMD ["/app/nurlapi"]
