# tools/fuzz/holes/open — soundness holes known open in 0.72.0

Every program here is **safe code** (no `unsafe` function of its own, no
raw memory or FFI of its own) that the 0.72.0 compiler still **accepts**
and that then leaks, frees memory it does not own, frees memory twice or
reads freed memory under ASan/LSan/UBSan. They are the release's known
issues (see `CHANGELOG.md`, 0.72.0 "Known issues", and
[`docs/MEMORY.md` §6.2](../../../../docs/MEMORY.md)). Each file's header
starts with `// OPEN in 0.72.0 — …` and says what the program does, why it
is unsound and what the sanitizer reports.

They are kept **out of the CI gate**: `../check.sh` with no arguments runs
only `h*.nu` in the parent directory, where every probe must be REJECTED or
run clean. Run these by hand:

```sh
cd tools/fuzz/holes
./check.sh open/*.nu open/stdlib/*.nu   # reports each as HOLE; last line "holes: 34"
```

A probe that prints REJECTED or ACCEPTED (ran clean) here has been closed —
graduate it (below).

## Classes

| Class | What is unsound | Files |
|---|---|---|
| `string_consume_*` (10) | A raw string `s` handed to a consuming parameter — `string_adopt` or a `sink s`. `string_adopt` takes over whatever it is handed (a literal, a view of a `String`, a borrowed or closure parameter, a result that is fresh on only some paths); a `sink s` the callee only reads, or leaves in the caller's container, is never released; a generic's `sink A` at `s` gives the caller's string up to nobody. | `string_consume_borrowed_param`, `string_consume_closure_param`, `string_consume_generic_sink_at_s`, `string_consume_left_in_param_container`, `string_consume_literal`, `string_consume_maybe_fresh_result`, `string_consume_method_and_trait_object`, `string_consume_panic_recover`, `string_consume_sink_param_only_read`, `string_consume_view_of_string` |
| `view_through_return_*` (4) | A view of a local leaves through a helper's return value (`^ ( pick x )`, a returned closure or `Vec` holding it); the local is released and the caller reads freed memory. | `view_through_return_closure`, `view_through_return_helper`, `view_through_return_vec`, `view_through_return_vec_literal` |
| `view_into_*` (3) | A view of a local stored into a container reached indirectly — a `Vec` parameter, a binding that aliases one, a field of an `inout` struct — outlives the local. | `view_into_aliased_param_vec`, `view_into_inout_struct_field`, `view_into_param_container` |
| `mem_forget_*` / `mem_take_*` (7) | `mem_forget` and `mem_take` are `unsafe`-only (spec §3.3d) but callable from safe code: `mem_forget` gives an owned value up unreleased (in any context — plain, generic, spawned closure, trait method, drop hook); `mem_take` claims a value a borrowed field or a `Vec` still holds. | `mem_forget_in_drop_hook`, `mem_forget_in_generic`, `mem_forget_in_spawned_closure`, `mem_forget_in_trait_method`, `mem_forget_owned_vec`, `mem_take_field_borrow`, `mem_take_vec_element` |
| `rcbox_*` (3) | The `rcbox` primitives are callable from safe code: `rcbox_new` parks a value behind a plain `i`, `rcbox_release` frees any `i`, and a program's own rcbox handle can be built over an address of its choosing. | `rcbox_handle_literal_over_forged_block`, `rcbox_new_parks_value`, `rcbox_release_any_address` |
| `dtor_*` (5) | Destructors (`% Drop` impls and library-handle drop hooks): a receiver handed to a `sink` disposer is dropped by nobody; an impl that reassigns a receiver field leaks the old value; an impl that panics is run again by the unwind; a closure inside an impl drops the receiver from its own body. | `dtor_closure_inside_drop_impl`, `dtor_disposer_leaks_fields`, `dtor_panics_runs_twice`, `dtor_reassigns_receiver_field`, `dtor_skipped_when_handed_to_disposer` |
| closure call (1) | A fresh string passed straight to a call of a closure value is never released. | `closure_call_fresh_temp_string` |
| trusted path (1) | Any source whose path contains `/stdlib/` is compiled as the trusted standard library, with every safe-code check off. The probe sits in `open/stdlib/` for that reason. | `stdlib/trusted_by_path_substring` |

34 probes in all (33 in this directory, one in `stdlib/`). Closed since
0.72.0 and graduated to the CI gate: `consumed_twice_in_one_call` (h143),
`consumed_and_read_in_one_call` (h144), `kwargs_forward_consuming_callee`
(h142).

## Earlier fix attempts

Two parked branches hold first attempts at two of the classes:

- `fix-sink-s-param-drop` — `string_consume_*` (a `sink s` released by its
  callee, a generic's `sink A` at `s` taking nothing over);
- `fix-mem-forget-unsafe` — `mem_forget_*` and `rcbox_*` (`mem_forget` and
  the `rcbox` primitives `unsafe`-only, drop hooks that no longer forget
  their receiver).

Their reviews found neither sound yet: they turned some of the leaks into
use-after-frees (`string_consume_left_in_param_container` is one: once the
callee releases a `sink s`, the caller's `Vec` still points at it), so
neither was merged. Some probe headers name a shape a fix must also hold
for that reason.

## Graduating a probe

When a fix makes a probe REJECTED, or makes it run clean under the
sanitizers, move it to `tools/fuzz/holes/` as the next free number
(`h142_…`, `h143_…` — `ls ../h*.nu` for the highest in use), with a
one-line `// H<NNN>: …` header in the style of the others. The CI step
"Soundness hole probes" (`./tools/fuzz/holes/check.sh`) then holds it: a
later change that reopens the hole fails the build. Then update the count
and the class row above, and the open-hole lists in `docs/MEMORY.md` §6.2
and `docs/LIMITATIONS.md`.
