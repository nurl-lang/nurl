# containers/ci/Dockerfile — the CI environment, pre-installed.
#
# Why this exists: on 2026-08-19 the Ubuntu package mirror reachable
# from GitHub's runner pool degraded three separate times, and every
# Linux job whose first step is `sudo apt-get update` burned its entire
# timeout budget in that one step — 15 minutes for the build job, 25
# for ASan, 30 for unikernel — across seven re-runs of two PRs, without
# executing a line of the code under test. The jobs that never touch
# apt (Windows, macOS, arm64 that day) passed every time. Baking the
# packages into an image moves the network dependency from every CI run
# to the rare occasions this file changes.
#
# One image serves the three Linux jobs (build+corpus, ASan, unikernel):
# it is the UNION of their package lists plus the zig toolchain the
# unikernel job used to download from ziglang.org per run — the other
# per-run network fetch, gone the same way.
#
# Build and push (needs push rights to the nurllang org):
#
#   docker build --build-context tools=tools \
#       -t nurllang/ci:ubuntu24-YYYYMMDD -t nurllang/ci:latest containers/ci
#   docker push nurllang/ci:ubuntu24-YYYYMMDD
#   docker push nurllang/ci:latest
#
# ci.yml pins the DATED tag, never :latest — an image change should be
# a reviewed diff, not something a rebuild slips into every job.
#
# ubuntu:24.04 to match the ubuntu-latest runners the jobs ran on
# bare, so the toolchain versions do not silently move in the switch.
# An empty stand-in for the LLVM release archive. `docker build
# --build-context llvm=DIR` replaces it with a directory that holds
# LLVM-<version>-Linux-<arch>.tar.zst, and the image installs from that
# file (still held to its sha256) instead of downloading 1.2 GB; without
# it the archive is downloaded. See tools/install-llvm.sh.
FROM scratch AS llvm

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# The union of the three jobs' apt lists, plus what the workflow steps
# themselves assume from the runner image and a container must provide:
# git + ca-certificates (actions/checkout), curl + xz-utils (tool
# fetches), python3 (metamorph gate), openssl (csr interop gate),
# sudo (workflow steps spell `sudo apt-get ...`; with the packages
# pre-installed those lines go away, but a stray sudo in a script must
# not become the new mystery failure).
#
# python3-xxhash replaces a per-run `pip install xxhash` in the zstd
# gate — the same per-run network fetch this image exists to remove.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        bash \
        binutils \
        ca-certificates \
        curl \
        gdb \
        git \
        grub-common \
        grub-efi-amd64-bin \
        grub-pc-bin \
        jq \
        libc6-dev \
        libcurl4-openssl-dev \
        libgcc-13-dev \
        libpq-dev \
        libsqlite3-dev \
        libssl-dev \
        libstdc++-13-dev \
        libzstd-dev \
        mtools \
        openssl \
        pkg-config \
        python3 \
        python3-pip \
        python3-xxhash \
        qemu-system-arm \
        qemu-system-misc \
        qemu-system-x86 \
        sudo \
        xorriso \
        xz-utils \
        zlib1g-dev \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# clang/LLVM: LLVM's own release (Ubuntu 24.04's `clang` is 18), the
# version and its digests in tools/install-llvm.sh — the one place every
# image and workflow takes them from. lld becomes clang's default linker
# there (the release ships no LLVMgold.so for GNU ld); compiler-rt, with
# the sanitizer runtimes, comes inside the archive. The C runtime it
# links against is the system's, as for any clang: libc6-dev and
# libgcc-13-dev (crtbeginS.o, libgcc_s) in the list above — what the
# distro `clang` package used to pull in as its own dependencies.
COPY --from=tools install-llvm.sh /tmp/install-llvm.sh
# It is also this image's `cc` and `c++`, as the distro clang package made
# itself through update-alternatives: the image has no gcc, and scripts
# compile helpers with plain `cc` (nurlapi/e2e_local.sh's sandbox wrapper).
RUN --mount=type=bind,from=llvm,target=/mnt/llvm \
    sh /tmp/install-llvm.sh --link /usr/local/bin --from /mnt/llvm && rm /tmp/install-llvm.sh \
    && update-alternatives --install /usr/bin/cc cc /opt/llvm/bin/clang 100 \
    && update-alternatives --install /usr/bin/c++ c++ /opt/llvm/bin/clang++ 100 \
    && cc --version | head -1

# The zig the ecosystem ships (install.sh, the playground image, the
# aarch64 cross builds) — same version, same place the unikernel job
# used to unpack it, so NURL_ZIG=/opt/zig/zig keeps working unchanged.
# Pinned by content as well as version: ziglang.org's own digest for
# the archive (https://ziglang.org/download/index.json). Bump both.
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
RUN curl -fsSL --retry 5 -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz \
    && /opt/zig/zig version

# actions/checkout inside a container refuses a workspace owned by a
# different uid unless the directory is marked safe. Runner workspaces
# arrive as root-owned bind mounts and the steps here run as root, so
# blanket-trusting is the container-CI convention.
RUN git config --system --add safe.directory '*'

# Deliberately NO global NURL_ZIG. nurl.sh prefers a bundled zig when it
# sees one, and the native jobs test the system-clang path. (A NURL_SAN=1
# build never uses zig: zig ships no ASan runtime, and nurl.sh picks
# clang for it, agora #126.) On the bare runners NURL_ZIG was only
# ever set per-step by the unikernel job, and the workflow still does
# exactly that; the image just provides /opt/zig for it to point at.
