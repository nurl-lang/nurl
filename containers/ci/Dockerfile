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
#   docker build -t nurllang/ci:ubuntu24-YYYYMMDD -t nurllang/ci:latest containers/ci
#   docker push nurllang/ci:ubuntu24-YYYYMMDD
#   docker push nurllang/ci:latest
#
# ci.yml pins the DATED tag, never :latest — an image change should be
# a reviewed diff, not something a rebuild slips into every job.
#
# ubuntu:24.04 to match the ubuntu-latest runners the jobs ran on
# bare, so the toolchain versions do not silently move in the switch.
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
# libclang-rt-dev is the one GitHub's bare runner image hid: Ubuntu 24
# splits the sanitizer runtimes out of `clang`, the runner image ships
# them pre-installed, and the first containerized ASan job died with
# "cannot find libclang_rt.asan-x86_64.a" 35 seconds in.
# python3-xxhash replaces a per-run `pip install xxhash` in the zstd
# gate — the same per-run network fetch this image exists to remove.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        bash \
        binutils \
        ca-certificates \
        clang \
        curl \
        gdb \
        git \
        grub-common \
        grub-efi-amd64-bin \
        grub-pc-bin \
        jq \
        libclang-rt-dev \
        libcurl4-openssl-dev \
        libpq-dev \
        libsqlite3-dev \
        libssl-dev \
        libzstd-dev \
        llvm \
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

# The zig the ecosystem ships (install.sh, the playground image, the
# aarch64 cross builds) — same version, same place the unikernel job
# used to unpack it, so NURL_ZIG=/opt/zig/zig keeps working unchanged.
ARG ZIG_VERSION=0.13.0
RUN curl -fsSL --retry 5 -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
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
# sees one, and zig 0.13's own ASan runtime is a different LLVM
# generation from system clang 18's instrumentation — a runtime_san.o
# compiled by one and linked by the other dies with "undefined symbol:
# __asan_unregister_elf_globals". On the bare runners NURL_ZIG was only
# ever set per-step by the unikernel job, and the workflow still does
# exactly that; the image just provides /opt/zig for it to point at.
