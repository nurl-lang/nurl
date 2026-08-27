# containers/dev/Dockerfile — the full development environment, in a box.
#
# Why this exists, and how it differs from containers/ci/Dockerfile:
#
#   containers/ci  is the CI environment: the UNION of the three Linux
#                  jobs' package lists and nothing else. It is pinned by
#                  dated tag in ci.yml, it runs as root, and every byte
#                  in it is there because a workflow step needs it.
#
#   containers/dev (this file) is a WORKBENCH. It is what a human — or a
#                  coding agent — needs to sit down in a clean checkout
#                  and do a day's work without hitting a "command not
#                  found" every twenty minutes: the CI set, plus the
#                  ecosystem toolchains (Node/pnpm for the Cloudflare
#                  Workers under registry/, webdocs/, nurlweb/; Rust and
#                  Node for the bench comparison programs; Python with
#                  numpy for the metamorph / fuzz / reference gates),
#                  plus git, gh, an editor, a debugger and a shell that
#                  is pleasant to be in.
#
# The two are deliberately NOT the same image. CI wants a small, audited,
# reproducible surface; a dev box wants coverage. Keeping them separate
# means a convenience package added here can never change what CI tests.
#
# Size budget: ~5 GB. The three optional blocks below (Rust, the
# non-x86 QEMU system emulators, the global wrangler) are what you trim
# first if you need to go smaller — see the ARGs.
#
# Build (from the repo root or anywhere; the build context is tiny):
#
#   docker build -t nurllang/dev:latest containers/dev
#
# Run — see containers/dev/run.sh, which mounts the repo, forwards your
# git/gh/Claude credentials and keeps agent state in named volumes.
#
# ubuntu:24.04 to match containers/ci and the ubuntu-latest runners, so
# a failure reproduced here is a failure CI will also see. clang 18 and
# glibc 2.39 are the versions the compiler's IR output is tuned against.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH=amd64

# ── Optional blocks ────────────────────────────────────────────────────
# Flip any of these to 0 to trade a capability for image size.
#   INCLUDE_RUST       ~700 MB — bench/*.rs comparison programs (bench.sh
#                      builds them with rustc/cargo). Nothing in the
#                      compiler or stdlib needs it.
#   INCLUDE_QEMU_CROSS ~900 MB — qemu-system-arm + qemu-system-misc, for
#                      booting the aarch64 / riscv64 unikernel targets.
#                      qemu-system-x86 is NOT optional: the unikernel
#                      test path and unikernel/bench_boot.sh need it.
#   INCLUDE_WRANGLER   ~150 MB — the Cloudflare CLI, preinstalled so the
#                      Worker directories do not each npx-fetch their own
#                      copy on first use.
ARG INCLUDE_RUST=1
ARG INCLUDE_QEMU_CROSS=1
ARG INCLUDE_WRANGLER=1

# Versions that are fetched rather than apt-installed. Pinned so a
# rebuild is a reviewed diff, not a moving target.
ARG ZIG_VERSION=0.16.0
ARG NODE_MAJOR=24
ARG RUST_VERSION=1.97.1

# The container user. Match your host uid/gid (the default 1000:1000 is
# the first interactive user on Debian/Ubuntu/Fedora) so that files the
# container writes into the bind-mounted work-tree stay yours, and the
# ones your host editor writes stay writable in here. run.sh passes the
# real values through.
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── 1. The CI package set ──────────────────────────────────────────────
# Everything containers/ci installs, so anything that reproduces in CI
# reproduces here. Two notes carried over from that file because they
# cost real debugging time to learn:
#
#   libclang-rt-dev — Ubuntu 24 splits the sanitizer runtimes out of the
#   `clang` package. Without it `build.sh --san` dies with "cannot find
#   libclang_rt.asan-x86_64.a".
#
#   The grub/mtools/xorriso trio is what unikernel/build_bootable_image.sh
#   shells out to; it checks for each by name and refuses early.
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
        qemu-system-x86 \
        sudo \
        xorriso \
        xz-utils \
        zlib1g-dev \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# ── 2. What a workbench adds on top ────────────────────────────────────
# build-essential: gcc/make. The compiler itself needs clang (nurlc emits
#   LLVM IR, which gcc cannot consume — nurl.sh says so explicitly), but
#   bench/*.c, node-gyp and any pip source build want a working cc.
# lld: the LTO link path, and the linker zig would otherwise shadow.
# clang-format/clang-tidy: stdlib/*.c and unikernel/**.c hygiene.
# valgrind/strace/ltrace: the leak + syscall gates under tools/ reach for
#   these when ASan is not the right instrument.
# shellcheck: there are ~60 .sh files in this repo driving the gates.
# python3-numpy: the reference implementations under packages/*/tests
#   (gguf, tensor, nurllama) and bench/genacc/score.py. python3-venv +
#   python3-dev so the heavier optional deps (torch, tiktoken — several
#   GB, deliberately NOT baked in) can be added on demand in a venv.
# postgresql-client / redis-tools / sqlite3: NURL speaks these protocols
#   in pure NURL, but debugging a wire-format mismatch means having the
#   reference client to compare against.
# busybox-static: the DIFFERENTIAL ORACLE for packages/nurlbox — its
#   test suite runs each applet against busybox and compares stdout and
#   exit status, and where busybox is absent it SKIPS. A suite whose
#   default state is "skipped" reads exactly like a suite that passed,
#   so this is not a convenience package.
# minisign: tools/ package-signing gates.
# dosfstools: mkfs.vfat for the unikernel FAT image path.
# qemu-utils: qemu-img, for the virtio-blk disk images.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        bsdextrautils \
        build-essential \
        busybox-static \
        clang-format \
        clang-tidy \
        cmake \
        diffutils \
        dnsutils \
        dosfstools \
        fd-find \
        file \
        git-lfs \
        gnupg \
        htop \
        iproute2 \
        iputils-ping \
        less \
        libncurses-dev \
        lld \
        locales \
        ltrace \
        make \
        man-db \
        minisign \
        nano \
        netcat-openbsd \
        ninja-build \
        openssh-client \
        patch \
        postgresql-client \
        procps \
        psmisc \
        python3-dev \
        python3-numpy \
        python3-venv \
        qemu-utils \
        redis-tools \
        ripgrep \
        rsync \
        shellcheck \
        socat \
        sqlite3 \
        strace \
        time \
        tmux \
        tree \
        tzdata \
        unzip \
        uuid-runtime \
        valgrind \
        vim \
        wget \
        xxd \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /bin/busybox /usr/local/bin/busybox

# Non-x86 system emulators for the cross-compiled unikernel targets.
# Separate layer so INCLUDE_QEMU_CROSS=0 drops ~900 MB cleanly instead of
# poisoning the big layer above.
RUN if [ "${INCLUDE_QEMU_CROSS}" = "1" ]; then \
        apt-get update -qq && apt-get install -y --no-install-recommends \
            qemu-system-arm \
            qemu-system-misc \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# UTF-8 everywhere. nurlc's diagnostics draw carets under multi-byte
# source, the test goldens contain UTF-8, and a C locale turns both into
# mojibake that reads like a real diff.
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ── 3. GitHub CLI ──────────────────────────────────────────────────────
# From GitHub's own apt repo rather than Ubuntu's, which ships a `gh` old
# enough to be missing subcommands the release/PR flows use.
RUN curl -fsSL --retry 5 https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update -qq \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ── 3b. cloud-hypervisor ───────────────────────────────────────────────
# The OTHER PVH loader. unikernel/tests/run_unit_tests.sh's
# hypervisor_gate boots the SAME ELF QEMU boots — both read the PVH note
# — which is the cheapest check that the image is not secretly a QEMU
# image. Without the binary the gate SKIPS, and a skip that is the
# default reads like a pass. ci.yml curls it per run; 4.5 MB is cheaper
# baked in. amd64 only: upstream ships no aarch64 static build.
RUN if [ "${TARGETARCH}" = "amd64" ]; then \
        curl -fsSL --retry 5 -o /usr/local/bin/cloud-hypervisor \
            https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/v46.0/cloud-hypervisor-static \
        && chmod +x /usr/local/bin/cloud-hypervisor; \
    fi

# ── 4. Node + pnpm ─────────────────────────────────────────────────────
# The workflows use both actions/setup-node (node 22 and 24) and
# pnpm/action-setup. The Cloudflare Workers under registry/, webdocs/,
# nurlweb/ and cloudflare/ are the consumers, together with the .mjs
# generators in tools/ (gen-bench-table, gen-contributors).
# NodeSource because Ubuntu 24.04's own nodejs is v18.
#
# pnpm comes from npm, NOT from corepack. `corepack prepare` installs a
# shim that downloads the real pnpm into ~/.cache/node/corepack on first
# use — which run.sh then hides behind a named cache volume, so every
# fresh container re-downloads it and an offline one has no pnpm at all.
# A global npm install lands in /usr/lib/node_modules and is immune.
RUN curl -fsSL --retry 5 https://deb.nodesource.com/setup_${NODE_MAJOR}.x -o /tmp/nodesource_setup.sh \
    && bash /tmp/nodesource_setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -f /tmp/nodesource_setup.sh \
    && rm -rf /var/lib/apt/lists/* \
    && npm config set fund false --global \
    && npm config set update-notifier false --global \
    && npm install -g pnpm \
    && npm cache clean --force \
    && pnpm --version

# Preinstalled so each Worker directory does not npx-fetch its own copy
# into a throwaway cache the first time it is touched.
RUN if [ "${INCLUDE_WRANGLER}" = "1" ]; then \
        npm install -g wrangler && npm cache clean --force; \
    fi

# ── 5. Zig ─────────────────────────────────────────────────────────────
# The same version and the same path as containers/ci and the ecosystem
# installers (install.sh, the playground image), so NURL_ZIG=/opt/zig/zig
# means the same thing in all of them. Zig is the cross-compiler: the
# aarch64/riscv64 targets and the Windows MinGW runtime object are built
# with `zig cc -target ...`, which is how the whole Windows link path is
# diagnosed from Linux.
#
# Deliberately NO global ENV NURL_ZIG — the same trap containers/ci
# documents: nurl.sh prefers a bundled zig when it sees one, and zig's
# ASan runtime is a different LLVM generation from system clang 18's
# instrumentation, so a sanitizer build links against a runtime_san.o it
# cannot resolve ("undefined symbol: __asan_unregister_elf_globals").
# Set NURL_ZIG per-command when you want zig; leave it unset otherwise.
RUN case "${TARGETARCH}" in \
        amd64) ZIG_ARCH=x86_64 ;; \
        arm64) ZIG_ARCH=aarch64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz \
    && /opt/zig/zig version
ENV PATH="/opt/zig:${PATH}"

# ── 6. The user ────────────────────────────────────────────────────────
# ubuntu:24.04 already ships a uid-1000 `ubuntu` account, which collides
# with the common host uid. Rename it into ours rather than fighting it.
RUN if getent group ${USER_GID} >/dev/null; then \
        groupmod -n ${USERNAME} "$(getent group ${USER_GID} | cut -d: -f1)"; \
    else \
        groupadd -g ${USER_GID} ${USERNAME}; \
    fi \
    && if getent passwd ${USER_UID} >/dev/null; then \
        usermod -l ${USERNAME} -d /home/${USERNAME} -m -s /bin/bash \
            "$(getent passwd ${USER_UID} | cut -d: -f1)"; \
    else \
        useradd -u ${USER_UID} -g ${USER_GID} -m -s /bin/bash ${USERNAME}; \
    fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# The work-tree arrives as a bind mount owned by the host uid. Even when
# that matches, git refuses a repo whose owner it cannot vouch for after
# any uid remap, and every gate in this repo shells out to git.
RUN git config --system --add safe.directory '*'

# ── 7. Rust ────────────────────────────────────────────────────────────
# bench/*.rs — the comparison half of every benchmark in bench/RESULTS.md.
# Installed as the user (rustup is per-user by design) with the minimal
# profile: rustc, cargo, rust-std. No docs, no rust-analyzer component.
USER ${USERNAME}
ENV HOME=/home/${USERNAME}
ENV CARGO_HOME=${HOME}/.cargo \
    RUSTUP_HOME=${HOME}/.rustup
RUN if [ "${INCLUDE_RUST}" = "1" ]; then \
        curl -fsSL --retry 5 https://sh.rustup.rs -o /tmp/rustup.sh \
        && sh /tmp/rustup.sh -y --no-modify-path --profile minimal \
            --default-toolchain ${RUST_VERSION} \
        && rm -f /tmp/rustup.sh \
        && ${CARGO_HOME}/bin/rustc --version; \
    fi
ENV PATH="${CARGO_HOME}/bin:${PATH}"

# ── 8. Claude Code ─────────────────────────────────────────────────────
# The agent this box is for. Installs to ~/.local/bin/claude.
#
# Last layer on purpose: it is the fastest-moving piece, and putting it
# here means a `claude` bump rebuilds one small layer instead of the
# 4 GB of toolchain above it.
#
# No credentials are baked in — the install only places the binary.
# Authentication lives in ~/.claude, which run.sh keeps in a named volume
# so a `claude /login` survives the container.
ENV PATH="${HOME}/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && claude --version

# ── 9. Shell environment ───────────────────────────────────────────────
# NURL_HOME is where tools/install-toolchain.sh puts an installed
# toolchain; putting its bin/ on PATH up front means `nurlpkg install
# <tool>` produces something runnable without a re-login.
ENV NURL_HOME=${HOME}/.nurl
ENV PATH="${NURL_HOME}/bin:${PATH}"

# Non-login, non-interactive shells (`docker exec ... bash -c`, and every
# tool that spawns `sh -c`) do not read .bashrc, so the PATH above is set
# as ENV and this file only carries the interactive niceties.
RUN printf '%s\n' \
    '# nurl-lang dev container' \
    'export HISTSIZE=100000 HISTFILESIZE=100000 HISTCONTROL=ignoreboth' \
    'shopt -s histappend checkwinsize' \
    "PS1='\\[\\e[38;5;39m\\]nurl\\[\\e[0m\\]:\\[\\e[38;5;114m\\]\\w\\[\\e[0m\\]\\$ '" \
    'alias ll="ls -alF"' \
    '# The repo drives everything through these; keep them one keystroke away.' \
    'alias b="./build.sh"' \
    'alias c="./check.sh"' \
    >> ${HOME}/.bashrc

# Keep the shell history in the state volume run.sh mounts, so it
# survives `docker rm`.
RUN mkdir -p ${HOME}/.local/state ${HOME}/.claude ${HOME}/.config
ENV HISTFILE=${HOME}/.local/state/bash_history

WORKDIR /work
CMD ["/bin/bash", "-l"]
