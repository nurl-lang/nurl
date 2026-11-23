# The ownership engine as the authority: why it is blocked, and the options

Status of AGORA-869 (the core-IR plan's stage S2, [PROPOSAL_CORE_IR.md](PROPOSAL_CORE_IR.md) §9), measured on 2026-11-16 against main 3358873a.

## What is closed, and what one change would close

Closed in the default compile, with graduated probes: AGORA-689, AGORA-696, AGORA-762, AGORA-841, AGORA-848 and AGORA-868, plus the walk's `@bn` hand-over (github#1908).

Every other known open hole has the same remedy. For each shape that faults under ASan/LSan with the default compile, the ownership engine (`nurlc --engine-decides`) refuses it: AGORA-242, 280, 382, 384, 395, 428, 479, 481, 489, 495, 557, 563, 569, 580, 606, 766, 774, 789, 793, 811, 812, 813, 832, 838, 840, 842, 844, 851, 870 and 874. (The two-closure Rc shapes once listed here are closed in the walk too: AGORA-945, proposal D3.) **One change closes all of them: the engine's findings refuse the program in an ordinary compile.** That is the unified fix this plan wants. It is blocked, as explained below. The holes stay open until it lands, each still listed in `tools/fuzz/holes/open/t<N>.md`, with probes in `tools/ncore/openprobes/`.

The engine does not refuse three shapes yet, so those need a rule of their own whichever option is taken:

- AGORA-872: a closure local or parameter, picked into a captured String owner. The engine refuses the option and parameter spellings.
- AGORA-873: `= o ( id o )` drops what `o` borrowed. Codegen keeps the borrowed value by key, but the summary says "own value".
- AGORA-875: a part of `o` behind a `Box` field, handed back by a pick of `o` and that part.

## Why it is blocked

Hard rules 2 and 3: compile time and memory may not regress. Measured on the self-compile, the compiler compiling `compiler/nurlc.nu`, all builds -O2 with one-module links:

| mode | instructions | peak RSS | sound | diagnostics |
|---|---|---|---|---|
| main (walk decides) | 25.41 G | 277 MB | holes above | the walk's |
| A. walk and engine (`--engine-decides` as default) | 29.02 G (+14 %) | 296 MB (+7 %) | yes | the walk's, the engine's where the walk misses |
| B. engine decides; the walk runs only in `unsafe` and trusted-library bodies | 23.31 G (−8 %) | 257 MB (−7 %) | **no** (below) | the engine's |

Where the cost of A goes: building the IR is +0.36 G and the engine's walks +3.28 G, spread over many functions with no single hot spot. On ordinary programs A costs +1.7 % (examples/async_http_server) to +4.7 % (compiler/tests/dst_flagship). The walk itself is 7.1 G of the self-compile: 5.6 G of it is recording rows during codegen and 1.5 G is the analysis. Deferring the analysis in the same process therefore saves only the 1.5 G.

B is unsound as it stands. A function whose body crosses the raw boundary (raw memory, a raw callee, FFI: IR flags 2|4) is not walked by the engine. Its summary comes from the walk's tables (`eng_derive`). The walk builds that summary from the body *and from the walk summaries of the functions it calls*. In mode B the safe callees are not walked, so a raw function's summary loses their effects. In-tree example: `diag_stale_borrow_forward`, where an `unsafe` function calls a safe `grow` defined below, is accepted in B. Walking only the safe functions that raw ones reach is no way out: 2,621 of `compiler/nurlc.nu`'s 2,637 safe functions are reachable from its `unsafe` ones, so B's saving would be gone. Across the tree, B loses no refusal beyond the shapes still being moved into the engine, but the gap above is real.

## Options

1. **A as is.** Closes every hole above today. Costs +14 % instructions and +7 % RSS on the self-compile, +2–5 % on large programs. Refused by rules 2 and 3.
2. **A plus speed-ups elsewhere.** It needs 3.6 G. Tried: a length-aware symbol table, where the key length is folded for literals and buckets are compared by stored length, made it slower (+1.5 %). The walk's recording (`bck_put`, `bck_record`) is the largest single cost at about 1.5 G of reachable work. Not enough alone.
3. **B plus raw summaries the engine infers itself (recommended).** The engine walks a raw function's IR: a raw pointer derived from a parameter is a view of it, a store through it changes it, and a returned pointer lends it. Calls are judged by the callees' engine summaries. That needs no annotations (rule 4), removes the walk's tables from the engine's input, and gives B's numbers. Remaining work:
   - the raw-op rules in the engine and in `tools/ncore`, plus formal rows;
   - moving the walk's last refusals into the engine: raw pointers going stale, `nurl_free` of an auto-dropped binding, the unikernel handler race (`unikernel/k8s/server.nu`);
   - the shapes above;
   - the engine's diagnostics as the compiler's: end line and cause in "borrows from … which ended", with goldens updated and checked to error at the same place;
   - deleting the walk's refusal code.
4. **B plus summaries declared in source for `unsafe` functions** (the proposal's D2). It is simpler to implement, but every `unsafe` author has to write summaries: ceremony that rule 4 forbids, and an owner's decision. Not taken.

## What was tried and left out

- The #412 lift, which compared an option or result owner by its payload's key so that `= o ( pick o other k )` compiles. Made sound by itself, it opened new routes into AGORA-872, AGORA-873 and AGORA-874, which main blocked only by refusing #412's form. It returns after those three are fixed.
- An in-process rerun with the full walk on the error path, to keep the walk's diagnostics. `nurlc.wasm` (WASI) cannot re-execute itself, and an in-process rerun would cost the 5.6 G of recording anyway.
