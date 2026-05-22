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
        binutils-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/clang-16 /usr/local/bin/clang

RUN ln -sf /usr/bin/python3 /usr/local/bin/python

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

# --- Zig toolchain (for macOS cross-compile + repo build graph) -----
ARG ZIG_VERSION=0.16.0
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

WORKDIR /src
COPY . /src
RUN find . -type f \( -name '*.sh' -o -name '*.nu' \) -exec sed -i 's/\r$//' {} +

# Bootstrap nurlc (image build skips tests; they run in CI elsewhere)
RUN /opt/zig/zig build bootstrap

# Compile the API/runtime cross-target objects through the shared Zig helper.
RUN NURL_ZIG=/opt/zig/zig \
    NURL_MINGW_CURL_PREFIX=/opt/curl-mingw \
    /opt/zig/zig build api-runtime-objs

# Compile the NURL API binary itself
RUN /opt/zig/zig build nurl -- nurlapi/main.nu nurlapi/nurlapi

# Stage 2: Final runtime image
FROM debian:bookworm-slim

# FFI -dev packages must match the builder stage above: zig build bootstrap enables
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
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/clang-16 /usr/bin/clang

ENV NURLC_PATH=/opt/nurl/build/nurlc \
    NURL_LINK_HELPER=/opt/nurl/build/nurl-build \
    NURL_NATIVE_CLANG=/usr/bin/clang-16 \
    NURL_STDLIB_DIR=/opt/nurl/stdlib \
    NURL_WORK_ROOT=/opt/nurl \
    NURL_STATIC_DIR=/app/static \
    NURL_RUNTIME_WASM_O=/opt/nurl/stdlib/runtime.wasm.o \
    NURL_CANVAS_WASM_O=/opt/nurl/stdlib/canvas.wasm.o \
    NURL_AUDIO_WASM_O=/opt/nurl/stdlib/audio.wasm.o \
    NURL_RUNTIME_WIN_O=/opt/nurl/stdlib/runtime.win.o \
    NURL_MINGW_CURL_PREFIX=/opt/curl-mingw \
    NURL_ZIG=/opt/zig/zig \
    NURL_MACOS_TARGET=x86_64-macos-none \
    NURL_RUNTIME_MAC_O=/opt/nurl/stdlib/runtime.mac.o \
    NURL_EXAMPLES_DIR=/opt/nurl/examples \
    NURL_OUTPUT_DIR=/app/output \
    PATH=/opt/nurl/build:/usr/local/bin:/usr/bin:/bin:$PATH

WORKDIR /app
COPY --from=builder /src/nurlapi/nurlapi /app/nurlapi
COPY --from=builder /src/nurlapi/static /app/static

# Bring in all cross-compilation artifacts
RUN mkdir -p /opt/nurl/build /opt/nurl/stdlib /app/output /opt/nurl/examples
COPY --from=builder /src/build/nurlc             /opt/nurl/build/nurlc
COPY --from=builder /src/build/nurl-build        /opt/nurl/build/nurl-build
COPY --from=builder /src/stdlib                  /opt/nurl/stdlib
COPY --from=builder /opt/curl-mingw              /opt/curl-mingw
COPY --from=builder /opt/zig                     /opt/zig
COPY --from=builder /src/examples                /opt/nurl/examples

EXPOSE 8000
CMD ["/app/nurlapi"]
