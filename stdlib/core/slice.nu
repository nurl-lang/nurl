// stdlib/core/slice.nu — bounds-safe view into a contiguous run of
// elements.
//
// A `Slice[A]` is a `{ *A data, i len }` pair: a borrowed pointer and
// an explicit length. It owns nothing — the underlying storage lives
// in a Vec (or a malloc'd buffer the caller manages). Slices are
// designed to replace the leak-prone `vec_data` + manual index
// arithmetic pattern that shows up in every hot-loop accessor today.
//
// Lifetime rule: a Slice is valid only while its backing storage is
// alive AND unchanged in capacity. Any `vec_push` / `vec_reserve` /
// `vec_set_len` / `vec_extend` that may grow the underlying buffer
// invalidates every outstanding slice. The compiler does not check
// this — same discipline as a C pointer-into-buffer.
//
// Examples:
//
//   // Whole-vec view (cheap; pointer + len snapshot).
//   : ( Slice i ) s ( slice_from_vec [i] v )
//   : i n ( slice_len [i] s )
//
//   // Sub-range view, clamped to valid bounds. None if from > to.
//   : ? ( Slice i ) sub ( slice_sub [i] s 2 8 )
//
//   // Bounds-checked single-element read.
//   : ? i x ( slice_get [i] s 3 )
//
//   // Raw pointer (no checks) for tight loops that already know the
//   // bound. Equivalent to `vec_data` but documented as borrowed.
//   : * i p ( slice_data [i] s )
//
// Slices do not own; never free them — let them go out of scope.

$ `stdlib/core/option.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`

: Slice [A] { * A data i len }

// ── Constructors ─────────────────────────────────────────────────────

// Whole-vec view. Safe immediately after construction; invalidated if
// the source Vec is later grown / shrunk.
@ slice_from_vec [A] ( Vec A ) v → ( Slice A ) {
    ^ @ ( Slice A ) {
        ( vec_data [A] v )
        ( vec_len [A] v )
    }
}

// Sub-range view `[from, to)`. Bounds are clamped to `[0, len(s))` —
// `from > to` after clamping returns None; equal indices returns an
// empty slice (data still points into v but len == 0).
@ slice_sub [A] ( Slice A ) s i from i to → ?( Slice A ) {
    : i n . s len
    : ~ i lo from
    ? < lo 0 { = lo 0 } {}
    ? > lo n { = lo n } {}
    : ~ i hi to
    ? < hi 0 { = hi 0 } {}
    ? > hi n { = hi n } {}
    ? > lo hi { ^ @ ?( Slice A ) { F @ ( Slice A ) { # *A 0 0 } } } {}
    : *A base . s data
    : *A start # *A + # i base * lo * Z A 1
    ^ @ ?( Slice A ) { T @ ( Slice A ) { start - hi lo } }
}

// Raw-pointer + length constructor. Caller MUST guarantee the storage
// holds `len` elements starting at `data`. Use only when interfacing
// with FFI buffers that the stdlib hasn't wrapped yet.
@ slice_from_raw [A] * A data i len → ( Slice A ) {
    ^ @ ( Slice A ) { data len }
}

// ── Inspectors ───────────────────────────────────────────────────────

@ slice_len [A] ( Slice A ) s → i {
    ^ . s len
}

@ slice_is_empty [A] ( Slice A ) s → b {
    ^ <= . s len 0
}

@ slice_data [A] ( Slice A ) s → *A {
    ^ . s data
}

// Bounds-checked element read. Returns None on out-of-range or empty
// slice. Mirrors `vec_get`'s semantics.
@ slice_get [A] ( Slice A ) s i idx → ?A {
    ? | < idx 0 >= idx . s len { ^ @ ?A { F # A 0 } } {}
    : *A p . s data
    ^ @ ?A { T . p idx }
}

// First / last element — convenience wrappers, same None-on-empty
// semantics as `slice_get`.
@ slice_first [A] ( Slice A ) s → ?A {
    ^ ( slice_get [A] s 0 )
}

@ slice_last [A] ( Slice A ) s → ?A {
    ^ ( slice_get [A] s - . s len 1 )
}
