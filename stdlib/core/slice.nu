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
//   // Indexing a loop wants: panics when out of range, like vec_at /
//   // vec_put. A kernel that writes one Vec while reading others runs
//   // as fast over slices as over raw pointers.
//   : i x ( slice_at [i] s 3 )
//   ( slice_put [i] s 3 + x 1 )
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
    ? >= # u64 idx # u64 . s len { ^ @ ?A { F # A 0 } } {}
    : *A p . s data
    ^ @ ?A { T . p idx }
}

// Never returns: defined ahead of its callers so they are compiled knowing
// that, and the optimiser can treat the check as a loop exit.
@ __slice_index_panic i idx i len → v {
    ( nurl_panic_index idx len `slice length` `` )
}

// …naming the caller's location, `at` ("file:line:col").
@ __slice_index_panic_at i idx i len s at → v {
    ( nurl_panic_index idx len `slice length` at )
}

// The element at `idx`, panicking like vec_at when it is out of range;
// an owning element comes back as a borrow of the storage. A Slice holds
// its data pointer and length in registers, so a loop that reads several
// Vecs and writes another through slices keeps both out of the loop and
// vectorises as raw pointer code does — vec_at / vec_put re-read them
// from each Vec's control block past every store.
@ slice_at [A] ( Slice A ) s i idx → A {
    ^ ( slice_at_loc [A] s idx `` )
}

// What every `( slice_at [T] s i )` call compiles to: slice_at with the
// caller's location (see vec_at_loc).
@ slice_at_loc [A] ( Slice A ) s i idx s at → A {
    : i n . s len
    ? >= # u64 idx # u64 n { ( __slice_index_panic_at idx n at ) } {}
    : *A p . s data
    ^ . p idx
}

// Store `x` at `idx` of the storage the slice views (dropping the element
// it replaces), panicking when `idx` is out of range — vec_put through a
// view. The view's length is fixed, so a store never moves the storage.
@ slice_put [A] ( Slice A ) s i idx A x → v {
    ( slice_put_loc [A] s idx x `` )
}

// What every `( slice_put [T] s i x )` call compiles to (see vec_at_loc).
@ slice_put_loc [A] ( Slice A ) s i idx A x s at → v {
    : i n . s len
    ? >= # u64 idx # u64 n { ( __slice_index_panic_at idx n at ) } {}
    : *A p . s data
    : A old . p idx
    ( mem_take old )
    = . p idx x
}

// The first `n` elements, panicking when the slice holds fewer. Slices cut
// to one length `n` share it: a loop indexing all of them at one index is
// checked once, not once per slice — parallel arrays (a tree's columns)
// walked by data-dependent indices pay for one bounds check per step.
@ slice_prefix [A] ( Slice A ) s i n → ( Slice A ) {
    ? >= # u64 n # u64 + . s len 1 { ( __slice_index_panic n . s len ) } {}
    ^ @ ( Slice A ) { . s data n }
}

// The `n` elements from `from`, panicking when the slice does not hold
// them — slice_prefix at an offset. A row of a row-major matrix taken this
// way is checked once, and a loop to `n` over it needs no check per
// element: the view's length is the loop's bound.
@ slice_window [A] ( Slice A ) s i from i n → ( Slice A ) {
    : i len . s len
    ? | >= # u64 from # u64 + len 1 >= # u64 n # u64 + - len from 1 { ( __slice_index_panic + from n len ) } {}
    : *A base . s data
    ^ @ ( Slice A ) { # *A + # i base * from * Z A 1 n }
}

// Whether two byte views hold the same bytes: one length compare, then
// memcmp over memory both views own. What a lookup probing a table against
// a window of its input asks, with no pointer of its own.
@ slice_bytes_eq ( Slice u ) a ( Slice u ) b → b {
    : i n . a len
    ? != n . b len { ^ F } {}
    ? <= n 0 { ^ T } {}
    ^ == 0 # i ( memcmp # s . a data # s . b data n )
}

// Lexicographic order of two byte views (memcmp, then the shorter first):
// -1, 0 or 1.
@ slice_bytes_cmp ( Slice u ) a ( Slice u ) b → i {
    : i la . a len
    : i lb . b len
    : i n ? < la lb la lb
    ? > n 0 {
        : i c # i ( memcmp # s . a data # s . b data n )
        ? != c 0 { ^ ? < c 0 -1 1 } {}
    } {}
    ? < la lb { ^ -1 } {}
    ? > la lb { ^ 1 } {}
    ^ 0
}

// The byte at `idx` (0..255), or 0 outside [0, len): the read a parser
// makes one or two bytes past its cursor, with no Option to unwrap.
inline @ slice_byte ( Slice u ) s i idx → i {
    ? >= # u64 idx # u64 . s len { ^ 0 } {}
    : *u p . s data
    ^ & # i . p idx 255
}

// A Vec of its own holding a copy of every element of the view: an
// element that owns something is copied deep (`mem_dup`), anything else
// as is (one memcpy). What a view that must outlive its storage — a
// result, a global, a thread's capture — is turned into.
@ slice_to_vec [A] ( Slice A ) s → ( Vec A ) {
    : i n . s len
    : ( Vec A ) out ( vec_with_cap [A] n )
    ? > n 0 {
        : *A dst ( vec_data [A] out )
        : *A src . s data
        : ~ i k 0
        ~ < k n {
            = . dst k ( mem_dup . src k )
            = k + k 1
        }
        : b _l ( vec_set_len [A] out n )
    } {}
    ^ out
}

// Copy the first min(len dst, len src) elements of `src` over `dst`; the
// count comes back. An element that owns something is copied deep
// (`mem_dup`) and the one it replaces is dropped; anything else is copied
// as is (one memmove, from LLVM). `dst` and `src` are two views: copying
// within ONE buffer — a page's records slid together — is slice_move,
// which takes the one view (two views of one buffer, one of them written,
// are not handed to a call together, docs/MEMORY.md §2.4).
@ slice_copy [A] ( Slice A ) dst ( Slice A ) src → i {
    : i n ? < . dst len . src len . dst len . src len
    : *A d . dst data
    : *A s . src data
    : ~ i k 0
    ~ < k n {
        : A old . d k
        ( mem_take old )
        = . d k ( mem_dup . s k )
        = k + k 1
    }
    ^ n
}

// Move `n` elements of `s` from index `from` to index `to`, the two runs
// may overlap (memmove), panicking when either run is out of range. What
// was at the destination is dropped; the source run keeps a copy (a deep
// one for elements that own something).
@ slice_move [A] ( Slice A ) s i from i to i n → v {
    : i len . s len
    // Each start against the room `n` leaves (`from + n` wraps, and a
    // negative start passed the old sum test): unsigned, so a negative
    // one is out of range too.
    ? | | | < n 0 > n len > # u64 from # u64 - len n > # u64 to # u64 - len n { ( __slice_index_panic + ? > from to from to n len ) } {}
    : *A p . s data
    ? > to from {
        : ~ i k - n 1
        ~ >= k 0 {
            : A old . p + to k
            ( mem_take old )
            = . p + to k ( mem_dup . p + from k )
            = k - k 1
        }
    } {
        ? < to from {
            : ~ i k 0
            ~ < k n {
                : A old . p + to k
                ( mem_take old )
                = . p + to k ( mem_dup . p + from k )
                = k + k 1
            }
        } {}
    }
}

// ── Little-endian words in a byte view ───────────────────────────────
// The u16 / u32 / u64 at byte `off`, and stores of one: a single bounds
// check for the whole word (panicking, like slice_at, when it does not
// fit), then the bytes — which LLVM fuses into one unaligned load or
// store. What a binary-format reader (a tensor container, an audio frame,
// a header) did through a raw pointer, or paid a check per byte for.
// A u64 comes back as its i64 bit pattern.

@ __slice_word_panic i off i w i len → v {
    ( __slice_index_panic + off - w 1 len )
}

inline @ slice_u16_le ( Slice u ) s i off → i {
    ? | < off 0 > off - . s len 2 { ( __slice_word_panic off 2 . s len ) } {}
    : *u p . s data
    ^ | # i . p off << # i . p + off 1 8
}

inline @ slice_u32_le ( Slice u ) s i off → i {
    ? | < off 0 > off - . s len 4 { ( __slice_word_panic off 4 . s len ) } {}
    : *u p . s data
    ^ | | # i . p off << # i . p + off 1 8 | << # i . p + off 2 16 << # i . p + off 3 24
}

inline @ slice_u64_le ( Slice u ) s i off → i {
    ? | < off 0 > off - . s len 8 { ( __slice_word_panic off 8 . s len ) } {}
    : *u p . s data
    : i lo | | # i . p off << # i . p + off 1 8 | << # i . p + off 2 16 << # i . p + off 3 24
    : i hi | | # i . p + off 4 << # i . p + off 5 8 | << # i . p + off 6 16 << # i . p + off 7 24
    ^ | lo << hi 32
}

inline @ slice_put_u16_le ( Slice u ) s i off i x → v {
    ? | < off 0 > off - . s len 2 { ( __slice_word_panic off 2 . s len ) } {}
    : *u p . s data
    = . p off # u & x 255
    = . p + off 1 # u & >> x 8 255
}

inline @ slice_put_u32_le ( Slice u ) s i off i x → v {
    ? | < off 0 > off - . s len 4 { ( __slice_word_panic off 4 . s len ) } {}
    : *u p . s data
    = . p off # u & x 255
    = . p + off 1 # u & >> x 8 255
    = . p + off 2 # u & >> x 16 255
    = . p + off 3 # u & >> x 24 255
}

inline @ slice_put_u64_le ( Slice u ) s i off i x → v {
    ? | < off 0 > off - . s len 8 { ( __slice_word_panic off 8 . s len ) } {}
    : *u p . s data
    : ~ i k 0
    ~ < k 8 {
        = . p + off k # u & >> x * k 8 255
        = k + k 1
    }
}

// First / last element — convenience wrappers, same None-on-empty
// semantics as `slice_get`.
@ slice_first [A] ( Slice A ) s → ?A {
    ^ ( slice_get [A] s 0 )
}

@ slice_last [A] ( Slice A ) s → ?A {
    ^ ( slice_get [A] s - . s len 1 )
}
