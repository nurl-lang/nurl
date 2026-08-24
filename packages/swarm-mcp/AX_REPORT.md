# swarm-mcp 0.22.0 — AX report (agent-experience test, installed package)

**Date:** 2026-08-13 · **Tester:** Claude (agent-driven, over the MCP surface itself)
**Setup:** `nurl upgrade` → v0.40.0 toolchain, `nurlpkg install swarm-mcp` → 0.22.0
(registry), `nurlpkg install nwasm` → 0.8.1. Host: Linux x86_64, LAN address
192.168.1.30, GPUs: RTX 4090 + GTX 970. Everything below was driven the way a
language model would drive it: `initialize` → `tools/list` → `tools/call` over
HTTPS JSON-RPC, plus the dev CLI.

**Topologies tested**
1. All-in-one node on 192.168.1.30 (`--relay --worker --mcp --mcp-listen
   0.0.0.0:8443`) + a second `--worker --gpu` node joining over the LAN
   address; all MCP calls end-to-end against `https://192.168.1.30:8443/mcp`.
2. A two-GPU cluster (RTX 4090 + GTX 970) on a build of the package carrying
   the one-line wasmbuilder fix described below — this is where the whole GPU
   tool family was exercised on real hardware.

## Verdict

The CPU story is excellent: install → serve → first correct distributed result
in under a minute, tool schemas are discoverable, `swarm_help` is genuinely
useful, kernel compile errors round-trip to the agent verbatim in ~70 ms, and
every numeric result checked out exactly.

**Every GPU tool was dead on the installed package — because of one bad
character in a dependency.** wasmbuilder built an LLVM `define` with a *named
vararg parameter* (`... %a2`), which is not legal LLVM, so every local wasm
build whose IR declares a vararg libc symbol failed to link. `compute_submit`'s
kernel path survived (its IR pulls in no vararg symbol); the whole CUDA family
did not. The failure was then masked twice over: the local error is discarded
in favour of a silent fallback to a public build service, which hung for 5
minutes and reported "could not reach the build API".

**Fix applied and verified:** `packages/wasmbuilder/src/wasi_ir.nu` now drops
the `...` marker when it mirrors a declare's parameters. wasmbuilder's own
suite passes 17/17, and with it the entire GPU family works end to end on real
hardware, including the documented mid-task worker-death re-dispatch. The
installed package will pick this up when wasmbuilder is re-published and
swarm-mcp rebuilt against it.

## CPU / control surface — all verified exact

| # | Test | Result |
|---|------|--------|
| 1 | `initialize` + `tools/list` (14 tools) | ✓ schemas short and clear |
| 2 | `compute_submit` `x*x` sum [1,10⁶) | ✓ 333332833333500000 |
| 3 | `compute_submit` float `1.0/(x*x)` (Basel) | ✓ 1.6449330668477464 |
| 4 | `compute_submit` count `x%2==0` [0,10⁷) | ✓ 5000000 |
| 5 | `compute_submit` float `min` of a parabola | ✓ 0 at x=500 |
| 6 | `compute_result` / `compute_list` | ✓ running→done, full history |
| 7 | `compute_submit_kernel`, element kind (prime count) | ✓ π(10⁵)=9592, 3.5 s incl. local wasm build |
| 8 | `compute_submit_kernel`, `kind:"chunk"` | ✓ same sum-of-squares, 3.8 s |
| 9 | `compute_run_wasm` (pre-compiled module) | ✓ π(2·10⁵)=17984, 2.5 s |
| 10 | `compute_upload_data` + `compute_list_data` | ✓ correct min/max/mean |
| 11 | `swarm_help` index + topics (incl. `troubleshooting`), bogus topic → index | ✓ good agent reference |
| 12 | Error paths: bad expr, missing args, bad task_id, unknown tool, empty range, malformed JSON (−32700) | ✓ clear, actionable |
| 13 | Dev CLI `submit` through the relay | ✓ correct result |
| 14 | Token isolation (wrong `--token`) | ✓ "no workers found" — cluster invisible |
| 15 | Second worker joins over LAN `--connect 192.168.1.30:47700` | ✓ chunks 4→8, results still exact |
| 16 | MCP served on the LAN address end to end | ✓ all of the above via https://192.168.1.30:8443 |

The kernel-compile feedback loop deserves praise: three syntax mistakes in my
NURL kernels came back as precise nurlc diagnostics (line, column, hint) inside
the tool result in ~70 ms, and the corrected kernel compiled and ran one round
later. That is exactly the loop an agent needs.

## GPU — after the wasmbuilder fix, on real hardware

| # | Test | Result |
|---|------|--------|
| 17 | `compute_submit_cuda` — π·10⁸ integral over [0,10⁸) | ✓ 314159266.3589793, **3.5 s** |
| 18 | `compute_sample_cuda` — x² for x<10 | ✓ [0,1,4,…,81] + min/max/mean |
| 19 | `compute_histogram_cuda` — 4 bins over 10⁶ | ✓ 250000 each |
| 20 | `compute_upload_data` + `compute_submit_cuda` over the dataset | ✓ sum 499500, `seeded_blocks:1` |
| 21 | `compute_iterate` — gradient descent fitting the mean | ✓ converged to 499.4999999998696 in 18 of 200 rounds, `seeded_blocks:0` (blocks cached) |
| 22 | `compute_shuffle` — group-by 4 keys over 10⁶ | ✓ 250000 per key, `distributed_reduce:true` |
| 23 | Numerical oracle: Σ_x Σ_{i<400} sin(x+i), x<10⁵ | ✓ GPU 1.8512270883986144 vs numpy 1.8512270883914512 (7·10⁻¹² abs, different summation order) |
| 24 | **Worker killed mid-task** (heavy CUDA kernel, 2 GPU workers) | ✓ `retries:4`, task finished exactly on the survivor — as documented |
| 25 | `compute_submit_kernel` CPU path on the same build | ✓ no regression, 3.4 s |

## Follow-up: every finding fixed (2026-08-13, same day)

The findings below were then fixed in the tree — swarm-mcp **0.24.0** plus the
one-line wasmbuilder fix — and re-verified on the same hardware. Details and
verification per item live in [critic.md](critic.md); the short version:

| finding | state |
|---------|-------|
| GPU family dead (wasmbuilder vararg shim) | fixed; wasmbuilder suite 17/17, `gpu_smoke.sh` 7/7 (was 0/7) |
| build error swallowed, silent public fallback | fixed: local error logged and leads the message; fallback announced |
| no timeout on the fallback (300 s block, wrong error) | fixed: 90 s cap, honest message; `httpc_request_timeout` added to the stdlib |
| dead worker never left the ring | fixed: 90 s liveness TTL evicts from roster + both rings |
| expression tasks `running` forever | fixed: retry plan on every task kind, roster-based liveness, 30 min backstop |
| — *found while fixing:* only the coordinator aged its roster, so re-dispatched chunks were forwarded back to the corpse | fixed: every node ages its own roster, never itself |
| — *found while fixing:* the FT layer misread the expression result frame, so healthy chunks looked failed | fixed: frames parsed by job kind |
| unknown `reduce` silently ran as `sum` | fixed: rejected with the valid ops |
| `failed_chunks` with no cause | fixed: the worker's reason rides home and appears as `error` |
| no `--gpu` preflight | fixed: startup probe refuses a GPU worker without a GPU-capable runtime |
| any path served the MCP body; wrong server name | fixed: `/mcp` only, 404 elsewhere; banner reports the transport |
| bind failure left the process half-alive; CLI newlines; unflushed `-v` log | fixed |
| cluster was invisible from outside | new `swarm_status` tool: workers, GPU capability, last-heard-from, TTL |

Re-verified after the fixes: `live_smoke.sh`, `tasks_smoke.sh` and
`gpu_smoke.sh` all pass; a new offline `liveness_test.nu` (ASan/LSan clean)
covers eviction and the reason suffix; and the worker-death scenarios were
replayed on real hardware — a task in flight plus two submitted *during*
recovery now settle in ~80 s with exact results, where they previously hung.

## What was still broken / rough (before the fixes)

| # | Finding | Where |
|---|---------|-------|
| a | Local build errors discarded; silent fallback ships kernel source to a public service | critic #2 |
| b | No timeout on that fallback: one tool call blocked **300 s**, then blamed reachability | critic #3 |
| c | Dead worker never leaves the roster: **every** later GPU submit pays 6 re-dispatches (~15 s extra) — observed still happening 7 min after the kill | critic #4 |
| d | A dead worker leaves **expression** tasks `running` forever — no deadline, no re-dispatch (observed >45 min) | critic #5 |
| e | Unknown `reduce` (`"avg"`) silently runs as `sum` | critic #6 |
| f | `failed_chunks` carries no cause anywhere, not even in `-v` logs | critic #7 |
| g | `--gpu` workers do no preflight (no wasm runtime / no libcuda → task-time mystery) | critic #8 |
| h | `GET /mcp` (any path, any method) → 200 + `"server":"nurl-mcp"`; non-standard `resultType`; no auth on the MCP surface | critic #9 |
| i | Port-bind failure keeps the process alive with the surviving roles | critic #10 |
| j | `-v` output from a worker-only node never reaches a redirected log (block buffering) | critic #10 |
| k | Registry (0.22.0) lags the repo (0.23.0): the MCP tasks extension is documented but absent from what installs today | critic #11 |

## Timings (this host)

| Operation | Time |
|-----------|------|
| Expression task, 10⁶ elements | ~0.3 s |
| Expression task, 10⁸ elements | ~2 s (interpreted, as documented) |
| `compute_submit_kernel`, incl. local wasm build | 3.4–3.8 s |
| `compute_run_wasm` (module cached) | 2.4–2.5 s |
| Kernel with a compile error | 0.07 s |
| CUDA build + run, 10⁸ elements, RTX 4090 | 3.5 s |
| `compute_iterate`, 18 rounds over a cached dataset | 11.7 s |
| `compute_submit_cuda` **before** the fix | 300 s, then a wrong error |
| CUDA local wasm build alone, after the fix | 1.1 s |
