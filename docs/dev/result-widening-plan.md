# Result widening: `{ i1, i64 }` → `{ i1, T, E }`

Branch `feat/result-wide`. Goal: a `!T E` carries its Ok payload **and** its Err
payload by value, removing the forced heap-box that a multi-field-struct success
payload currently needs. This is the Option↔Result symmetry fix: `?T` is already
`{ i1, T }` (full T by value); Result should be `{ i1, T, E }`.

This is an **atomic ABI change** to the self-hosting compiler — construction,
matching, try-propagation and type-lowering must all flip together; there is no
partially-building intermediate state. The bootstrap fixed-point + 467-test
corpus is the validator: an inconsistent ABI cannot pass the fixed point.

## Why it is not a simple "3-field aggregate"

In the current `{ i1, i64 }` model BOTH the Ok and Err payloads occupy field 1
(the single i64 slot), squeezed in via ptrtoint / bitcast / zext / heap-box. In
`{ i1, T, E }` the payload index depends on the tag:

- Ok  `@ !T E { T okval }` → tag=1 in field 0, `okval` in **field 1** (type T)
- Err `@ !T E { F errval }` → tag=0 in field 0, `errval` in **field 2** (type E)

So the literal's 2nd value routes to field 1 OR field 2 by the tag. The generic
"idx-th literal → idx-th field" insertvalue loop and the shared Option/Result
match path both assume the payload is always field 1; both need Result-specific
routing.

## Sites to change (from the 2026-06-27 recon)

1. **`parse_type_res` (nurlc.nu ~567-577)** — emit `{ i1, <lt>, <le> }` instead
   of `{ i1, i64 }`. Guard: a `void` payload (`!v E` / `!T v`) cannot sit in an
   LLVM struct — substitute a zero-width placeholder (`i1`) for a `void` slot and
   never read it. Audit whether `!v E` / `!T v` occur in tree first.

2. **`compound_field_type` (nurlc.nu ~425-440)** — currently assumes the
   `{ i1, X }` 2-field shape and slices out X. Make it depth-aware and index the
   N-th comma-separated field so `{ i1, T, E }` yields i1 / T / E for idx 0/1/2.
   Reuse the depth-counting logic from `agg_field_count`.

3. **Construction — `gen_agg_lit` (nurlc.nu ~10472-11120)** — add a Result branch
   distinct from the generic field loop: read the tag literal (T/F → i1 0/1),
   then insertvalue the payload literal into field 1 (Ok) or field 2 (Err) **by
   value** using the normal per-field coercion (`coerce_store_val`). The other
   payload slot stays zeroinitialized. Delete the Result i64-squeeze branches
   (pointer ptrtoint, bool zext, double bitcast, narrow-int pad, multi-field
   heap-box, wide-enum heap-box) for the Result path — they become dead.

4. **Matching — `gen_match` (nurlc.nu ~6190-6410)** — the `pt0_is_opt_bool` path
   is shared by Option and Result. For Result, extract the Ok binding from field
   **1** and the Err binding from field **2**, each at its real type (T / E), by
   value. Remove the Result reconstruction logic (f→bitcast, b→i64-trunc,
   struct/enum heap-unbox) — with by-value slots it is unnecessary. Option keeps
   its existing field-1-by-value behaviour. Keep field 0 (tag) extraction as is.

5. **Try-propagation — `gen_try_expr` (nurlc.nu ~12437-12576)** — `\ res` extracts
   the Ok value from field 1 by value (drop the i64-unbox), and on Err early-
   returns the Err from field 2 (or repackages it for the caller's `!_ E`). Mirror
   gen_match's removed reconstruction.

6. **Side-channels — already in place.** `__last_res_t_llvm__` / `__last_res_err_llvm__`
   (parse_type_res) and per-fn `<fn>__res_t_llvm` / `<fn>__res_e_llvm` already
   carry both T and E LLVM types; the new field-1/field-2 logic reads them. No new
   metadata needed.

7. **No size assumptions.** runtime.c uses a `NurlProcResult` wrapper, not the
   `{ i1, i64 }` layout; FFI does not see Result by value. Re-grep for any `i64`
   that assumes the 16-byte Result before finalizing.

## Order of work

parse_type_res + compound_field_type first (type layer), then construction, then
match, then try — but they must all land before the first build. Strategy: make
all edits, build, and triage the (expected many) IR type-mismatch errors clang
surfaces, iterating to a green bootstrap + corpus. Add a regression test that
returns a multi-field-struct success payload and asserts no `nurl_alloc` is
emitted on that path (the boxing-elimination proof).

## Risk

High blast radius (nurlc.nu returns `!T E` widely), but the validator is strong:
any inconsistency fails the fixed point or a corpus test, so undetected silent
miscompiles are unlikely — the cost is iteration count, not hidden breakage.
Semantics are already correct today (a multi-field success payload works, it just
allocates), so this is a performance/representation upgrade, not a bug fix.
