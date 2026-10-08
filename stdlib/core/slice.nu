// stdlib/core/slice.nu — bounds-safe view into a contiguous run of
// elements.
//
// A `Slice[A]` is a `{ *A data, i len }` pair: a borrowed pointer and
// an explicit length. It owns nothing — the underlying storage lives
// in a Vec (or a malloc'd buffer the caller manages). Slices are
// designed to replace the leak-prone `vec_data` + manual index
// arithmetic pattern that shows up in every hot-loop accessor today.
//
// Lifetime rule: a Slice is a view of its storage (docs/MEMORY.md
// §2.10), valid only while that storage is alive and unchanged in
// capacity. Any `vec_push` / `vec_reserve` / `vec_extend` that may grow
// the underlying buffer, or freeing the Vec, ends every outstanding slice
// of it — and the compiler checks this wherever the slice has gone: a
// struct or container holding it, a closure that captured it, a result.
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
//   // A string's bytes, measured once; 0 past the end.
//   : ( Slice u ) b ( slice_of_str text )
//   : i c ( slice_byte b 0 )
//
//   // Raw pointer (no checks), for `unsafe` code that already knows the
//   // bound — like `vec_data`, only an `unsafe` function may take it.
//   : * i p ( slice_data [i] s )
//
// Slices do not own; never free them — let them go out of scope.

$ `stdlib/core/vec.nu`

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

// The bytes of a NUL-terminated string, measured once: a scan indexes it
// in O(1) against a length that cannot lie (`nurl_str_at` took its
// caller's, so a wrong one read past the string — it is raw memory now).
// A null string is the empty slice.
@ slice_of_str s text → ( Slice u ) {
    ? == # i text 0 { ^ ( slice_empty [u] ) } {}
    ^ @ ( Slice u ) { # *u text ( strlen text ) }
}

// The empty slice: no data, length 0. What a reader that has nothing to
// read holds — the one Slice built from no Vec.
@ slice_empty [A] → ( Slice A ) {
    ^ @ ( Slice A ) { # *A 0 0 }
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

// The byte at `idx` (0..255), or 0 outside [0, len): the read a parser
// makes one or two bytes past its cursor, with no Option to unwrap.
inline @ slice_byte ( Slice u ) s i idx → i {
    ? | < idx 0 >= idx . s len { ^ 0 } {}
    : *u p . s data
    ^ & # i . p idx 255
}

// First / last element — convenience wrappers, same None-on-empty
// semantics as `slice_get`.
@ slice_first [A] ( Slice A ) s → ?A {
    ^ ( slice_get [A] s 0 )
}

@ slice_last [A] ( Slice A ) s → ?A {
    ^ ( slice_get [A] s - . s len 1 )
}
