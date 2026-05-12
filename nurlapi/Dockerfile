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
RUN curl -fsSL -o /tmp/wasi-sdk.tar.gz \
        "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_FULL}-x86_64-linux.tar.gz" \
    && mkdir -p /opt/wasi-sdk \
    && tar -xzf /tmp/wasi-sdk.tar.gz -C /opt/wasi-sdk --strip-components=1 \
    && rm /tmp/wasi-sdk.tar.gz

# --- Static libcurl for mingw-w64 -------------------
ARG CURL_VERSION=8.10.1
RUN curl -fsSL -o /tmp/curl.tar.xz \
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
RUN curl -fsSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

WORKDIR /src
COPY . /src
RUN find . -type f \( -name '*.sh' -o -name '*.nu' \) -exec sed -i 's/\r$//' {} +

# Bootstrap nurlc
RUN chmod +x verbosebuild.sh && ./verbosebuild.sh

# Compile runtime objects
# 1. Native Linux
# (Already exists as stdlib/runtime.o after verbosebuild.sh)

# 2. wasm32-wasi
RUN /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.wasm.o \
    && /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/canvas_wasm.c -o stdlib/canvas.wasm.o \
    && /opt/wasi-sdk/bin/clang --target=wasm32-wasi -O2 \
        -c stdlib/audio_wasm.c -o stdlib/audio.wasm.o

# 3. Windows (x86_64-w64-mingw32)
RUN x86_64-w64-mingw32-gcc -O2 \
        -DNURL_HAVE_LIBCURL -DCURL_STATICLIB \
        -I/opt/curl-mingw/include \
        -c stdlib/runtime.c -o stdlib/runtime.win.o \
    && echo 1 > stdlib/runtime.win.curl

# 4. macOS x86_64
RUN /opt/zig/zig cc -target x86_64-macos-none -O2 \
        -c stdlib/runtime.c -o stdlib/runtime.mac.o

# Compile the NURL API binary itself
RUN ./nurl.sh nurlapi/main.nu nurlapi/nurlapi

# Stage 2: Final runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        clang-16 \
        libcurl4-openssl-dev \
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
COPY --from=builder /src/stdlib                  /opt/nurl/stdlib
COPY --from=builder /opt/wasi-sdk                /opt/wasi-sdk
COPY --from=builder /opt/curl-mingw              /opt/curl-mingw
COPY --from=builder /opt/zig                     /opt/zig
COPY --from=builder /src/examples                /opt/nurl/examples

EXPOSE 8000
CMD ["/app/nurlapi"]
