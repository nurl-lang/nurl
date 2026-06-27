# Result widening — next-session kickoff (note to future me)

You are resuming the deferred Result `{i1,i64}` → `{i1,T,E}` widening. Everything
you need is already on this branch. Read this top-to-bottom once, then start.

## 0. Orient (2 min)

```
cd /home/wau/dev/nurl-lang
git checkout feat/result-wide
git log --oneline -3        # expect the plan + kickoff commits on top of main
```

Read `docs/dev/result-widening-plan.md` first — it has the full recon (the exact
sites, the Ok→field1 / Err→field2-by-tag insight, the side-channels). This
kickoff is the *runbook*; the plan is the *map*. Do not re-run the recon agents;
the map is current as of 2026-06-27.

## 1. Pre-flight audits (do BEFORE editing — they can change the design)

- **void payloads.** Grep the tree for `!v ` and `! v ` and any `→ ! … v` /
  `→ ! v …` so you know if `!v E` or `!T v` exist. `{ i1, void, E }` is illegal
  LLVM. If they occur, lower a `void` payload slot to `i1` (a 1-byte placeholder
  you never read) in `parse_type_res`. If they don't occur, still add the guard —
  it is cheap insurance.
  ```
  grep -rnE '![[:space:]]*v[[:space:]]|[[:space:]]v[[:space:]]E' stdlib compiler/tests examples | grep '!'
  ```
- **16-byte assumptions.** Re-grep for anything that assumes Result is two words /
  16 bytes (memcpy of a result, fixed offset 8 into a result, an `i64` cast of a
  whole result). Recon said none exist and runtime.c uses `NurlProcResult` (not
  the value layout), but verify before you rely on it.
- **Confirm the validator is green at HEAD:** `./build.sh` must pass on the branch
  before you touch anything, so any later red is yours.

## 2. The change is ATOMIC — edit all, then build

There is no partially-building state: the first construction site that emits
`insertvalue {i1,T,E} …, i64 X, 1` is a type error. So make every edit from the
plan's "Sites to change" list in one pass, THEN build. Order to write them (all
before the first build):

1. `parse_type_res` (~567) → `{ i1, <lt>, <le> }` (+ void guard).
2. `compound_field_type` (~425) → depth-aware N-th-field extractor (steal the
   comma/`depth` loop from `agg_field_count` ~448). Must return i1 / T / E for
   idx 0 / 1 / 2 of `{ i1, T, E }`, and still handle Option `{ i1, T }` (idx 0/1)
   and slice `{ T*, i64 }`.
3. `gen_agg_lit` Result construction (~10472–11120): NEW Result branch — read the
   tag value (first literal, T/F→i1), route the payload (second literal) to field
   1 (Ok) or field 2 (Err) by value via `coerce_store_val`, leave the other slot
   zeroinit. The Result i64-squeeze branches (ptrtoint / bool-zext / double-bitcast
   / narrow-int pad / multi-field heap-box / wide-enum heap-box) become DEAD for
   Result — bypass them. Leave Option untouched.
4. `gen_match` (~6190–6410): in the shared `pt0_is_opt_bool` path, for Result
   extract Ok from field **1** and Err from field **2**, each at its real type by
   value. DELETE the Result reconstruction (f→bitcast at ~6227, b→trunc at ~6244,
   struct/enum heap-unbox ~6300–6346) — by-value slots make it unnecessary. Option
   stays field-1-by-value.
5. `gen_try_expr` (~12437–12576): `\ res` reads Ok from field 1 by value; on Err
   early-returns the field-2 Err. Mirror the removed reconstruction.

Tip: keep a scratch list of every `, 1\n` / `, 2\n` extractvalue and every
`compound_field_type … 1` you touch — those are the index-sensitive spots.

## 3. Build–iterate loop (the long part)

```
./check.sh compiler/nurlc.nu      # syntax/type first — fast, catches NURL errors
./build.sh                        # bootstrap fixed point + 467 corpus = the validator
```

`./build.sh` is ~3 min. Expect several red rounds: clang IR type-mismatches point
you straight at a site still using the old layout. Triage by the failing `.ll`
(the driver leaves it; or `build/nurlc <file> 2>&1 | clang -x ir -`). A corpus
test that returns/matches a Result is your canary — `string_to_int`
(`compiler/tests/string.nu`), `msgpack_demo` (returns `!Point ParseErr`), and any
`should_fail_*` around `?? `/`\`.

## 4. Prove the win + land

- Add `compiler/tests/result_wide.nu`: a fn returning `!Multi E` where
  `Multi { i a i b i c }`, construct Ok and Err, `??`-match both, assert values.
  Then confirm the Ok path emits **no `nurl_alloc`** (grep the `.ll`) — that is the
  boxing-elimination proof the whole change exists for.
- Run the sanitized pass: `./build.sh --san` then
  `./compiler/tests/run_san_tests.sh` (expect SAN_FAIL 0), then `./build.sh` to
  restore the normal toolchain.
- `nurlfmt`: `build/nurlfmt --write` any touched + new files;
  `./compiler/tests/nurlfmt_check.sh` must say OK.
- Update `docs/spec.md` §4.5 (the `{ i1, i64 }` description) and remove the
  `docs/LIMITATIONS.md` / TODO.md "Result boxes multi-field payloads" entry.
- Commit (one focused commit), push, PR. Keep the two planning docs or fold them
  into the PR description.

## 5. If it does not converge

It is a representation upgrade, not a correctness fix — current code is already
correct (it boxes). So if the iteration count balloons or a corpus regression is
subtle, it is safe to `git reset --hard` the implementation work; the branch keeps
the plan + this kickoff for the next attempt. No shame in landing it in two
sittings.

## Gotchas already known

- `: ~ s g_*` mutable string globals work in nurlc.nu (used elsewhere).
- Result and Option SHARE the `{ i1, … }` match path — the bug class is touching
  Option by accident. After each edit ask "does this also fire for `?T`?"; if so,
  guard on 3-field vs 2-field (use the depth-aware field count).
- A `?` statement needs BOTH branches (`? c { } {}`) — a missing `{}` silently
  eats the next statement (the prefix-arity footgun).
- Enum / option `F` variant literals need a payload slot: `@ ?i { F 0 }`, not
  `{ F }`.
