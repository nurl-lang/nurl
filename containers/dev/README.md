# The NURL dev container

A workbench in a box: everything needed to build the compiler, run the
gates, boot the unikernel, deploy the Workers and drive a coding agent —
without installing any of it on the host.

```bash
./containers/dev/run.sh            # builds on first use, then drops you in a shell
./containers/dev/run.sh claude     # straight into the agent
./containers/dev/run.sh ./build.sh # one-shot command, then exit
```

The repo is bind-mounted at `/work`, owned by your host uid, so edits go
both ways and nothing in the container can leave a root-owned file behind.

## Why this is not `containers/ci`

`containers/ci/Dockerfile` is the CI environment: the union of the three
Linux jobs' package lists and nothing more, pinned by dated tag in
`ci.yml`. Every byte in it is there because a workflow step needs it, and
it should stay that way — a convenience package added for a human must
never change what CI tests.

This image starts from that same set and adds the rest of a working day:
the ecosystem toolchains, the debuggers, an editor, `git`, `gh`, and
Claude Code.

## What is in it

| Area | Tools |
|---|---|
| Compiler | `clang` 18, `llvm`, `lld`, `libclang-rt-dev` (ASan/UBSan), `gdb`, `valgrind`, `strace`, `ltrace` |
| Cross / freestanding | `zig` 0.16 at `/opt/zig`, `qemu-system-{x86,arm,misc}`, `cloud-hypervisor`, `grub-{pc,efi-amd64}-bin`, `xorriso`, `mtools`, `dosfstools`, `qemu-utils` |
| FFI dev libs | `libssl`, `libcurl`, `libsqlite3`, `libpq`, `libzstd`, `zlib` |
| Ecosystem web | Node 24, `pnpm` (corepack), `wrangler` |
| Scripting / gates | Python 3.12 + `numpy` + `xxhash` + `venv`, `shellcheck`, `jq`, `openssl`, `minisign` |
| Benchmarks | Rust 1.97 (`rustc`/`cargo`), Node, Python — the comparison half of `bench/` |
| Protocol debugging | `psql`, `redis-cli`, `sqlite3`, `socat`, `nc`, `dig` |
| Differential oracles | `busybox` (for `packages/nurlbox`), GNU coreutils, `openssl`, `zstd` |
| Everyday | `git`, `git-lfs`, `gh`, `ripgrep`, `fd`, `tmux`, `vim`, `nano`, `htop`, `tree`, `rsync`, `less`, `xxd`, `column`, `uuidgen` |
| Agent | Claude Code (`claude`) |

Deliberately **not** in it:

* **A GPU stack.** No CUDA, no ROCm, no `nvidia-container-toolkit`. The
  GPU packages (`packages/gpukit`, `packages/onnx`, …) are developed
  against a real device on the host.
* **PyTorch / tiktoken / onnxruntime.** Several GB for reference tests
  that a handful of packages run occasionally. `python3-venv` is
  installed so they are one command away when you need them:

  ```bash
  python3 -m venv ~/.cache/venv-ml && ~/.cache/venv-ml/bin/pip install torch numpy
  ```

* **The Docker CLI.** `dockerpush.sh` and the playground image build on
  the host; mount `/var/run/docker.sock` yourself if you want that here.

## Size, and how to shrink it

The image lands around 4–5 GB. Three blocks are the bulk of the
discretionary part and each is a build ARG:

```bash
docker build \
    --build-arg INCLUDE_RUST=0 \
    --build-arg INCLUDE_QEMU_CROSS=0 \
    --build-arg INCLUDE_WRANGLER=0 \
    -t nurllang/dev:slim containers/dev
```

| ARG | Cost | What you lose |
|---|---|---|
| `INCLUDE_RUST` | ~700 MB | the `bench/*.rs` comparison programs |
| `INCLUDE_QEMU_CROSS` | ~900 MB | booting the aarch64 / riscv64 unikernel targets (x86 still works) |
| `INCLUDE_WRANGLER` | ~150 MB | a preinstalled Cloudflare CLI (`npx wrangler` still works, online) |

## State, credentials and the agent

Nothing secret is baked into the image. `run.sh` forwards what it finds
on the host and keeps mutable state in named volumes, so `docker rm` is
never destructive:

| Volume | Mounted at | Holds |
|---|---|---|
| `nurl-dev-claude` | `~/.claude` | agent auth + session state |
| `nurl-dev-state` | `~/.local/state` | shell history |
| `nurl-dev-cache` | `~/.cache` | npm / pip / cargo download caches |
| `nurl-dev-nurl` | `~/.nurl` | an installed NURL toolchain |

Forwarded from the host when present: `~/.gitconfig` (read-only),
`~/.ssh` (read-only), `$SSH_AUTH_SOCK`, `$ANTHROPIC_API_KEY`, and a
GitHub token taken from `$GH_TOKEN`, `$GITHUB_TOKEN` or `gh auth token`.

Claude Code starts logged out. Either run `claude` and `/login` once —
the volume keeps it — or copy the host's credentials in on first run:

```bash
./containers/dev/run.sh --seed-claude claude
```

`/dev/kvm` is passed through when the host exposes it, which is the
difference between a unikernel boot test taking a second and taking a
minute. Without it QEMU falls back to TCG and everything still works.

## First run inside

```bash
./build.sh                 # bootstrap the compiler + run the corpus
./check.sh stdlib/std/fs.nu # ~0.2 s per-file syntax/type check
```

`build.sh` is the gate; `check.sh` is the loop. Note that `build.sh` does
*not* run `tools/check_stdlib_symbols.sh`, `tools/check_nolibc_symbols.sh`
or `tools/check_examples.sh` — run those before pushing.

Sanitizer builds work out of the box (`./build.sh --san`), but leave
`NURL_ZIG` unset for them. The image ships zig at `/opt/zig/zig` and
deliberately does not export `NURL_ZIG`: `nurl.sh` prefers a bundled zig
when it sees one, and zig's ASan runtime is a different LLVM generation
from system clang 18's instrumentation — mixing them fails to link with
`undefined symbol: __asan_unregister_elf_globals`. Point `NURL_ZIG` at it
per-command when you want the cross-compiler:

```bash
NURL_ZIG=/opt/zig/zig ./unikernel/build_bootable_image.sh
```

## VS Code / Codespaces

`.devcontainer/devcontainer.json` builds this same Dockerfile and mounts
the same volumes, so a login done through either path is visible to the
other. "Reopen in Container" is all it takes.

## Rebuilding

```bash
./containers/dev/run.sh --build     # rebuild, reusing layers
./containers/dev/run.sh --rebuild   # --no-cache
```

Claude Code is the last layer on purpose: bumping it rebuilds one small
layer instead of the toolchain above it.
