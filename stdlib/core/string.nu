// stdlib/core/string.nu — owned growable String, backed by Vec[u].
//
// String is an opaque handle whose underlying storage is a `Vec[u]`
// growable byte buffer. The handle is value-passed; mutations flow
// through the inner Vec's ctl pointer just like Vec[A] itself, so
// aliasing semantics match Vec.
//
// Layout: `String { s ctl }` — same single-i8* shape as `Vec[u]`. The
// `ctl` field points to the same 24-byte control block (`{data, len, cap}`)
// that vec_with_cap[u] allocates. We view it as a Vec[u] inside this
// module via the private `__sbuf` helper; outside this module the type
// is opaque.
//
// Invariants the implementation maintains:
//   1. cap >= len + 1                 (always room for a trailing NUL)
//   2. data[len] == 0  between ops    (so `string_data` returns C-safe s)
//
// `_string_seal` enforces the invariant after every mutation. NUL bytes
// inside [0, len) are stored verbatim (Vec[u] doesn't truncate); only
// `string_data`'s C-string consumers see truncation at the first inner
// NUL, which is the contract of every NUL-terminated API.
//
//   ( string_new )             → String      empty
//   ( string_from raw )        → String      copy of raw i8*
//   ( string_len s )           → i           byte length
//   ( string_data s )          → s           borrowed i8* (null-terminated); do NOT free
//   ( string_get s idx )       → i           byte at index (0 out of range)
//   ( string_push_char s c )   → v           append one byte
//   ( string_push_str s raw )  → v           append raw i8*
//   ( string_push_bytes s src n ) → v        append n raw bytes (no strlen)
//   ( string_push_int s n )    → v           append decimal integer
//   ( string_clear s )         → v           reset to empty
//   ( string_free s )          → v           release buffer, invalidates handle
//   ( string_eq a b )          → b           content equality
//
//   ( string_with_cap n )      → String      empty, cap-preallocated
//   ( string_clone s )         → String      independent deep copy
//   ( string_concat a b )      → String      new owned concatenation
//   ( string_starts_with s p ) → b           prefix check
//   ( string_ends_with s p )   → b           suffix check
//   ( string_contains s n )    → b           substring check
//   ( string_substr s from len ) → String    owned copy of [from, from+len)
//   ( string_to_int s )        → ! i ParseErr  strict decimal parse with sign
//   ( string_to_float s )      → ?f            strict decimal float
//   ( string_index_of s p )    → ?i            byte index of first occurrence
//   ( string_split s sep )     → ( Vec String ) split on sep occurrences

$ `stdlib/core/errors.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/char.nu`
// Note: do NOT include stdlib/std/bytes.nu here. bytes.nu depends on
// String (e.g. `bytes_to_str → String`); a circular include would force
// the compiler to reference %String before its body is emitted. We keep
// this module self-contained on Vec[u] primitives only.

// ── nurl_str_* / nurl_memcmp_lex / nurl_memmem_range / ─────────────
//    nurl_parse_int_range — direct libc FFI. `strlen` / `strcmp` /
//    `strncmp` / `strstr` / `memcmp` / `memmem` / `atoll` / `atof` /
//    `memcpy` / `strdup` are declared globally by the nurlc preamble,
//    so call sites don't need a per-file `&`-FFI declaration.

@ nurl_memcmp_lex s a i la s b i lb → i {
    : i n ? < la lb la lb
    ? > n 0 {
        : i c # i ( memcmp a b n )
        ? != c 0 { ^ ? < c 0 -1 1 } {}
    } {}
    ? < la lb { ^ -1 } {}
    ? > la lb { ^ 1 } {}
    ^ 0
}

@ nurl_str_len s str → i {
    ^ ( strlen str )
}

@ nurl_str_eq s a s b → i {
    : i c # i ( strcmp a b )
    ^ ? == c 0 1 0
}

@ nurl_str_cmp s a s b → i {
    : i c # i ( strcmp a b )
    ? < c 0 { ^ -1 } {}
    ? > c 0 { ^ 1 } {}
    ^ 0
}

@ nurl_str_to_int s str → i {
    ^ ( atoll str )
}

@ nurl_str_to_float s str → f {
    ^ ( atof str )
}

@ nurl_str_starts s str s prefix → i {
    : i n ( strlen prefix )
    : i c # i ( strncmp str prefix n )
    ^ ? == c 0 1 0
}

@ nurl_str_find s haystack s needle → i {
    : s p # s ( strstr haystack needle )
    ? == # i p 0 { ^ -1 } {}
    ^ - # i p # i haystack
}

@ nurl_str_ends s str s suffix → i {
    : i slen ( strlen str )
    : i plen ( strlen suffix )
    ? > plen slen { ^ 0 } {}
    : i off - slen plen
    : *u sp # *u str
    : s base # s + # i sp off
    : i c # i ( memcmp base suffix plen )
    ^ ? == c 0 1 0
}

@ nurl_memmem_range s hay i hlen s needle i nlen → i {
    ? | < hlen 0 < nlen 0 { ^ -1 } {}
    ? == nlen 0 { ^ 0 } {}
    ? > nlen hlen { ^ -1 } {}
    : s p # s ( memmem hay hlen needle nlen )
    ? == # i p 0 { ^ -1 } {}
    ^ - # i p # i hay
}

// ── allocation-style ops ───────────────────────────────────────────
// Direct malloc + memcpy through the preamble libc declarations.
// `malloc` / `memcpy` already declared globally; no `&`-FFI needed.

// Return byte at index `idx` (0 if out of range). `& 255` masks the
// sign-extension that `# i u` introduces — caller gets 0..255.
//
// COST: this re-runs strlen(str) on EVERY call for the bounds check, so
// a loop that walks a string with it is O(n²) — seconds on a 100 KB
// input. Use `nurl_str_at` below in any loop: hoist the length once and
// pass it in. Reach for `nurl_str_get` only for a one-off read where no
// length is at hand.
@ nurl_str_get s str i idx → i {
    : i n ( strlen str )
    ? | < idx 0 >= idx n { ^ 0 } {}
    : *u p # *u str
    : u b . p idx
    ^ & # i b 255
}

// O(1) sibling of `nurl_str_get`: the caller passes the length it
// already knows, so no strlen runs. Identical contract otherwise —
// returns 0 when `idx` falls outside [0, len), which is what parsers
// rely on when they read one or two bytes past the cursor.
//
// This is the accessor scan loops want. `nurl_str_get` re-runs strlen
// per call, and in any loop that also writes (i.e. every parser) LLVM
// cannot hoist that strlen out, so the loop is quadratic — measured
// 120 µs vs 11 µs over a 4 KB input, and the gap grows with the input.
// Hoist the length once, then index with this:
//
//   : i n ( nurl_str_len src )
//   ~ < k n { : i c ( nurl_str_at src n k ) … }
@ nurl_str_at s str i len i idx → i {
    ? | < idx 0 >= idx len { ^ 0 } {}
    : *u p # *u str
    : u b . p idx
    ^ & # i b 255
}

// Concatenate two strings; result is heap-allocated, NUL-terminated.
@ nurl_str_cat s a s b → s {
    : i la ( strlen a )
    : i lb ( strlen b )
    : s r # s ( nurl_alloc + + la lb 1 )
    ( memcpy r a la )
    : *u rp # *u r
    : *u dst # *u + # i rp la
    ( memcpy # s dst b + lb 1 )
    ^ r
}

// Concatenate three; result is heap-allocated, NUL-terminated.
@ nurl_str_cat3 s a s b s c → s {
    : i la ( strlen a )
    : i lb ( strlen b )
    : i lc ( strlen c )
    : s r # s ( nurl_alloc + + + la lb lc 1 )
    ( memcpy r a la )
    : *u rp # *u r
    : *u d2 # *u + # i rp la
    ( memcpy # s d2 b lb )
    : *u d3 # *u + # i rp + la lb
    ( memcpy # s d3 c + lc 1 )
    ^ r
}

// Concatenate four; result is heap-allocated, NUL-terminated. Allocates
// exactly once (the historic C version nested two `cat` calls and
// leaked the intermediates).
@ nurl_str_cat4 s a s b s c s d → s {
    : i la ( strlen a )
    : i lb ( strlen b )
    : i lc ( strlen c )
    : i ld ( strlen d )
    : s r # s ( nurl_alloc + + + + la lb lc ld 1 )
    ( memcpy r a la )
    : *u rp # *u r
    : *u d2 # *u + # i rp la
    ( memcpy # s d2 b lb )
    : *u d3 # *u + # i rp + la lb
    ( memcpy # s d3 c lc )
    : *u d4 # *u + # i rp + + la lb lc
    ( memcpy # s d4 d + ld 1 )
    ^ r
}

// Return bytes [start, start+len); result is heap-allocated, NUL-terminated.
// Clamps `start` and `len` into the actual string length.
@ nurl_str_slice s str i start i n → s {
    : i slen ( strlen str )
    : ~ i st start
    : ~ i k n
    ? < st 0 { = st 0 } {}
    ? > st slen { = st slen } {}
    ? < k 0 { = k 0 } {}
    ? > + st k slen { = k - slen st } {}
    : s r # s ( nurl_alloc + k 1 )
    : *u sp # *u str
    : *u sat # *u + # i sp st
    ( memcpy r # s sat k )
    : *u rp # *u r
    : u zero # u 0
    = . rp k zero
    ^ r
}

// Parse i64 from byte range [p, p+len). Optional leading '-' / '+',
// then decimal digits; stops on first non-digit. Returns 0 on empty
// or all-non-digit input (callers that need to distinguish "parse
// failure" from "real zero" use int_parse on a NUL-terminated input).
@ nurl_parse_int_range s p i len → i {
    ? == # i p 0 { ^ 0 } {}
    ? <= len 0 { ^ 0 } {}
    : *u q # *u p
    : ~ i i 0
    : ~ i sign 1
    : u first . q 0
    ? == & # i first 255 45 { = sign -1 = i 1 } {}
    ? == & # i first 255 43 { = i 1 } {}
    : ~ i acc 0
    ~ < i len {
        : u c . q i
        : i ci & # i c 255
        ? | < ci 48 > ci 57 { ^ * acc sign } {}
        = acc + * acc 10 - ci 48
        = i + i 1
    }
    ^ * acc sign
}

// strtod via FFI for byte-range float parsing. nurl_str_int and
// nurl_str_float keep their C bodies — str_int because moving it
// would force `$ stdlib/core/string.nu` into 72 corpus tests that
// use it transitively; str_float because printf-family %g/%e needs
// Grisu/Ryu or variadic FFI.

// Parse f64 from byte range [p, p+len) via libc `strtod`. Copies
// into a NUL-terminated scratch buffer, passes NULL as endptr.
// Returns 0.0 on empty / null input.
@ nurl_parse_float_range s p i len → f {
    ? == # i p 0 { ^ 0.0 } {}
    ? <= len 0 { ^ 0.0 } {}
    : s buf # s ( nurl_alloc + len 1 )
    ( memcpy buf p len )
    : *u bp # *u buf
    : u zero # u 0
    = . bp len zero
    : **u endptr # **u 0
    : f v ( strtod buf endptr )
    ( nurl_free buf )
    ^ v
}

: String {
    s ctl
}

// ── Internal: view the underlying ctl block as a Vec[u] handle ─────
// All Vec[u] operations on the returned handle mutate the same heap
// control block that `str` references, so they're observable through
// `str` after the call returns. The struct layout `{ s ctl }` matches
// `Vec[A] { s ctl }` so this is a zero-cost view (one i8* copy).
@ __sbuf String str → ( Vec u ) {
    ^ @ ( Vec u ) { . str ctl }
}

// Append the raw NUL-terminated bytes of `raw` onto str's buffer. Caller
// is responsible for the post-mutation `_string_seal`.
@ __string_append_raw String str s raw → v {
    : ( Vec u ) b ( __sbuf str )
    : i n ( nurl_str_len raw )
    ? > n 0 {
        ( vec_reserve [u] b n )
        : *u src # *u raw
        : *u dst ( vec_data [u] b )
        : i len ( vec_len [u] b )
        : *u dst_at # *u + # i dst len
        ( nurl_memcpy dst_at src n )
        ( vec_set_len [u] b + len n )
    } {}
}

// ── Internal: NUL-terminator discipline ─────────────────────────────
// Ensure cap >= len + 1 and write 0 at data[len]. Call after every
// mutation (push, extend, clear, …) so `string_data` returns a C-safe
// pointer.
@ _string_seal String str → v {
    : ( Vec u ) b ( __sbuf str )
    ( vec_reserve [u] b 1 )
    : *u p ( vec_data [u] b )
    : i n ( vec_len [u] b )
    : u zero # u 0
    = . p n zero
}

// ── Constructors ────────────────────────────────────────────────────

@ string_new → String {
    : ( Vec u ) tmp ( vec_with_cap [u] 1 )
    : *u p ( vec_data [u] tmp )
    : u zero # u 0
    = . p 0 zero
    ^ @ String { . tmp ctl }
}

@ string_with_cap i n → String {
    : i want ? > n 0 + n 1 1
    : ( Vec u ) tmp ( vec_with_cap [u] want )
    : *u p ( vec_data [u] tmp )
    : u zero # u 0
    = . p 0 zero
    ^ @ String { . tmp ctl }
}

@ string_from s raw → String {
    : i n ( nurl_str_len raw )
    : ( Vec u ) tmp ( vec_with_cap [u] + n 1 )
    : *u src # *u raw
    : *u dst ( vec_data [u] tmp )
    ( nurl_memcpy dst src n )
    ( vec_set_len [u] tmp n )
    : u zero # u 0
    = . dst n zero
    ^ @ String { . tmp ctl }
}

// Take ownership of an already-malloc'd, NUL-terminated buffer and
// wrap it as a String WITHOUT copying. The caller must NOT touch
// `raw` after the call — the returned String now owns the buffer
// and will `nurl_free` it on `string_free`.
//
// `raw_cap` is the actual malloc'd size (bytes), typically
// `nurl_str_len raw + 1` for a freshly-read file buffer. Must be
// >= len + 1 so the trailing NUL fits.
//
// Used by fast file I/O paths (CSV / arena loaders) to avoid the
// `nurl_memcpy` over the full content — for a 100 MB CSV that's
// ~33 ms saved per load.
@ string_from_take s raw i raw_cap → String {
    : i n ( nurl_str_len raw )
    : s ctl ( nurl_zalloc 24 )
    ( nurl_poke ctl 0 # i raw )
    ( nurl_poke ctl 1 n )
    ( nurl_poke ctl 2 raw_cap )
    ^ @ String { ctl }
}

// Build an owned String from a raw byte range. `src` is a borrowed
// pointer into another buffer; `n` bytes are copied verbatim and a NUL
// terminator is written at offset n. Faster than building a temporary
// raw `s` and calling `string_from`, because it avoids a strlen scan
// and an extra malloc/free pair.
@ string_from_bytes * u src i n → String {
    : i len ? > n 0 n 0
    : ( Vec u ) tmp ( vec_with_cap [u] + len 1 )
    : *u dst ( vec_data [u] tmp )
    ? > len 0 {
        ( nurl_memcpy dst src len )
        ( vec_set_len [u] tmp len )
    } {}
    : u zero # u 0
    = . dst len zero
    ^ @ String { . tmp ctl }
}

// Packed-layout fast constructor: one malloc for `ctl + buf` together
// instead of the two `string_from_bytes` makes. For read-only Strings
// (parsed JSON values, immutable lookup keys, …) this halves the
// per-string alloc count. `vec_free` / `vec_free_with` / `__vec_grow`
// in `core/vec.nu` detect the packed layout by `data == ctl + 24` so
// the lifecycle is byte-identical to a normal String: it can still be
// mutated and grown (growth allocates out into a separate buffer the
// first time), and freed with the standard `string_free`.
//
// Use for known-immutable strings only — the first push or extend
// pays for an unpacking copy. Mutate-heavy paths should keep using
// `string_from_bytes`.
@ string_from_bytes_packed * u src i n → String {
    : i len ? > n 0 n 0
    : i cap + len 1
    : i total + 24 cap
    : s pack ( nurl_alloc total )
    : i data_off + # i pack 24
    : s data # s data_off
    // ctl slot 0 = data ptr, slot 1 = len, slot 2 = cap
    ( nurl_poke pack 0 data_off )
    ( nurl_poke pack 1 len )
    ( nurl_poke pack 2 cap )
    ? > len 0 { ( nurl_memcpy data # s src len ) } {}
    : *u bp # *u data
    : u zero # u 0
    = . bp len zero
    ^ @ String { pack }
}

// Deep copy of `str` into a fresh owned String. The two Strings share
// no storage — mutating or freeing one never affects the other. Embedded
// NUL bytes in [0, len) are preserved verbatim.
//
// This is the stock element-clone for owned-String containers: pass it
// to `vec_clone_with` / `map_clone_with` wrapped in a `\`-closure (NURL
// hands closure values, not @-function names, to higher-order params):
//
//   ( vec_clone_with [String] src \ String s → String { ^ ( string_clone s ) } )
@ string_clone String str → String {
    : ( Vec u ) b ( __sbuf str )
    : i n ( vec_len [u] b )
    : *u src ( vec_data [u] b )
    ^ ( string_from_bytes src n )
}

// ── Inspectors ──────────────────────────────────────────────────────

@ string_len String str → i {
    ^ ( vec_len [u] ( __sbuf str ) )
}

@ string_data String str → s {
    ^ # s ( vec_data [u] ( __sbuf str ) )
}

@ string_get String str i idx → i {
    : ?u got ( vec_get [u] ( __sbuf str ) idx )
    ?? got {
        T x → { ^ # i x }
        F _ → { ^ 0 }
    }
}

// Content equality over the FULL byte range [0, len). The lengths are
// compared first, then the bytes with `memcmp` — not `strcmp`, which
// stops at the first embedded NUL and would report two strings equal
// when they differ only after it. `String` stores inner NULs verbatim
// (see the module header), so the comparison has to honour them.
@ string_eq String a String b → b {
    : ( Vec u ) ba ( __sbuf a )
    : ( Vec u ) bb ( __sbuf b )
    : i la ( vec_len [u] ba )
    : i lb ( vec_len [u] bb )
    ? != la lb { ^ F } {}
    ? == la 0 { ^ T } {}
    : *u pa ( vec_data [u] ba )
    : *u pb ( vec_data [u] bb )
    ^ == 0 # i ( memcmp # s pa # s pb la )
}

// ── Bulk emission cursor ────────────────────────────────────────────
//
// `string_push_char` is a call, three `nurl_peek`s and a `nurl_poke`
// per byte — ~1.7 ns even on its fast path, because the compiler has to
// re-read the control block every time (the store could alias it). An
// encoder that knows how many bytes it is about to produce can instead
// reserve the room once, write straight through a `*u`, and commit the
// length at the end: measured 4096 bytes in 565 ns versus 7061 ns
// through `string_push_char` — 12.5×.
//
//   : *u w ( string_reserve_at out n )     // room for n bytes + NUL
//   … = . w k # u byte …                   // k in [0, n)
//   ( string_commit out n )                // len += n, NUL re-sealed
//
// CONTRACT — the returned pointer is valid only until the next
// operation that can grow the buffer. Between `string_reserve_at` and
// `string_commit`, do NOT call any other mutator on `str` (push_char,
// push_str, push_bytes, clear, …) and do NOT write past index n-1: a
// realloc would move the buffer and leave the cursor dangling. Write
// the bytes, commit, then go back to the normal API.
//
// Committing fewer bytes than reserved is fine (encoders whose output
// size is only an upper bound reserve the bound and commit the truth).

@ string_reserve_at String str i n → *u {
    : ( Vec u ) b ( __sbuf str )
    ( vec_reserve [u] b + n 1 )
    // Re-read the control block rather than deriving the result from
    // `b`: `b` is a VIEW of str's ctl (see __sbuf), but strict borrowck
    // cannot know that and would flag a raw pointer escaping an owned
    // local. Going through nurl_peek keeps the provenance on `str`.
    : s ctl . str ctl
    : i len ( nurl_peek ctl 1 )
    : *u p # *u ( nurl_peek ctl 0 )
    ^ # *u + # i p len
}

@ string_commit String str i n → v {
    ? <= n 0 { ^ } {}
    : s ctl . str ctl
    : i len ( nurl_peek ctl 1 )
    ( nurl_poke ctl 1 + len n )
    : *u p # *u ( nurl_peek ctl 0 )
    : u zero # u 0
    = . p + len n zero
}

// ── Mutators ────────────────────────────────────────────────────────

@ string_push_char String str i c → v {
    : s ctl . str ctl
    : i len ( nurl_peek ctl 1 )
    : i cap ( nurl_peek ctl 2 )
    // Fast path: room for the byte AND the trailing NUL already exists,
    // so no grow-check and no _string_seal re-reserve is needed.
    ? >= cap + len 2 {
        : *u p # *u ( nurl_peek ctl 0 )
        : u zero # u 0
        = . p len # u c
        = . p + len 1 zero
        ( nurl_poke ctl 1 + len 1 )
    } {
        : ( Vec u ) b ( __sbuf str )
        ( vec_push [u] b # u c )
        ( _string_seal str )
    }
}

@ string_push_str String str s raw → v {
    ( __string_append_raw str raw )
    ( _string_seal str )
}

// Append exactly `n` raw bytes from `src` onto str's buffer. Unlike
// string_push_str this needs no strlen scan and preserves embedded NUL
// bytes verbatim — the range-append a streaming reader wants when it
// already knows the line length. `src` is borrowed; the bytes are
// copied, str keeps no reference.
@ string_push_bytes String str * u src i n → v {
    ? > n 0 {
        : ( Vec u ) b ( __sbuf str )
        : i len ( vec_len [u] b )
        ( vec_reserve [u] b + n 1 )
        : *u dst ( vec_data [u] b )
        : *u dst_at # *u + # i dst len
        ( nurl_memcpy dst_at src n )
        : b _ok ( vec_set_len [u] b + len n )
    } {}
    ( _string_seal str )
}

@ string_push_int String str i n → v {
    : s raw ( nurl_str_int n )
    ( __string_append_raw str raw )
    ( _string_seal str )
}

@ string_push_float String str f x → v {
    : s raw ( nurl_str_float x )
    ( __string_append_raw str raw )
    ( _string_seal str )
}

@ string_clear String str → v {
    : ( Vec u ) b ( __sbuf str )
    ( vec_clear [u] b )
    ( _string_seal str )
}

@ string_free String str → v {
    ( vec_free [u] ( __sbuf str ) )
}

// ── Concat ──────────────────────────────────────────────────────────

@ string_concat String a String b → String {
    : i la ( string_len a )
    : i lb ( string_len b )
    : String out ( string_with_cap + la lb )
    ( string_push_str out ( string_data a ) )
    ( string_push_str out ( string_data b ) )
    ^ out
}

// ── Predicates / search (delegate to nurl_str_* on string_data) ────

@ string_starts_with String str s prefix → b {
    ^ != 0 ( nurl_str_starts ( string_data str ) prefix )
}

@ string_ends_with String str s suffix → b {
    ^ != 0 ( nurl_str_ends ( string_data str ) suffix )
}

@ string_contains String str s needle → b {
    ^ >= ( nurl_str_find ( string_data str ) needle ) 0
}

// Strict decimal parse. Accepts optional leading '-' or '+', then one
// or more decimal digits, and nothing else. Empty input (or just a sign
// with no digits) → Empty. Any non-digit byte after the optional sign →
// BadFormat. Overflow is not currently detected (atoll wraps silently);
// a future revision may return Overflow for > i64 magnitude.
@ string_to_int String str → !i ParseErr {
    : i len ( string_len str )
    ? == len 0 { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    : ~ i idx 0
    : i first ( string_get str 0 )
    // '-' = 45, '+' = 43
    ? | == first 45 == first 43 { = idx 1 } {}

    // bare sign with no digits
    ? == idx len { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    ~ < idx len {
        : i c ( string_get str idx )
        ? == ( is_digit c ) 0 {
            ^ @ !i ParseErr { F @ ParseErr { BadFormat } }
        } {}
        = idx + idx 1
    }

    : s buf ( string_data str )
    ^ @ !i ParseErr { T ( nurl_str_to_int buf ) }
}

// First byte index at which `needle` occurs in `str`. Empty needle
// matches at 0 (same as nurl_str_find / strstr). Result is None if
// the needle is not present.
@ string_index_of String str s needle → ?i {
    : i n ( nurl_str_find ( string_data str ) needle )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T n }
}

// Strict decimal float. Either int or fractional part may be empty
// (`.5` and `1.` both accepted) but at least one mantissa digit is
// required overall. Optional exponent must have at least one digit.
@ string_to_float String str → ?f {
    : i len ( string_len str )
    ? == len 0 { ^ @ ?f { F 0.0 } } {}

    : ~ i idx 0
    : i first ( string_get str 0 )
    ? | == first 45 == first 43 { = idx 1 } {}
    ? == idx len { ^ @ ?f { F 0.0 } } {}

    : ~ i int_digits 0
    : ~ b going T
    ~ going {
        ? == idx len { = going F } {
            : i c ( string_get str idx )
            ? == ( is_digit c ) 0 { = going F } {
                = idx + idx 1
                = int_digits + int_digits 1
            }
        }
    }

    : ~ i frac_digits 0
    ? & < idx len == ( string_get str idx ) 46 {
        = idx + idx 1
        = going T
        ~ going {
            ? == idx len { = going F } {
                : i c ( string_get str idx )
                ? == ( is_digit c ) 0 { = going F } {
                    = idx + idx 1
                    = frac_digits + frac_digits 1
                }
            }
        }
    } {}

    ? & == int_digits 0 == frac_digits 0 {
        ^ @ ?f { F 0.0 }
    } {}

    ? < idx len {
        : i c ( string_get str idx )
        ? | == c 101 == c 69 {
            = idx + idx 1
            ? < idx len {
                : i esgn ( string_get str idx )
                ? | == esgn 45 == esgn 43 { = idx + idx 1 } {}
            } {}
            : ~ i exp_digits 0
            = going T
            ~ going {
                ? == idx len { = going F } {
                    : i ec ( string_get str idx )
                    ? == ( is_digit ec ) 0 { = going F } {
                        = idx + idx 1
                        = exp_digits + exp_digits 1
                    }
                }
            }
            ? == exp_digits 0 {
                ^ @ ?f { F 0.0 }
            } {}
        } {}
    } {}

    ? != idx len { ^ @ ?f { F 0.0 } } {}

    : s buf ( string_data str )
    ^ @ ?f { T ( nurl_str_to_float buf ) }
}

// ── Owned-returning transforms ──────────────────────────────────────

@ string_substr String str i from i len → String {
    : i slen ( string_len str )
    : ~ i start from
    ? < start 0 { = start 0 } {}
    ? > start slen { = start slen } {}
    : ~ i n len
    ? < n 0 { = n 0 } {}
    ? > + start n slen { = n - slen start } {}

    : ( Vec u ) tmp ( vec_with_cap [u] + n 1 )
    : *u dst ( vec_data [u] tmp )
    ? > n 0 {
        : *u src # *u ( string_data str )
        : *u src_at # *u + # i src start
        ( nurl_memcpy dst src_at n )
        ( vec_set_len [u] tmp n )
    } {}
    : u zero # u 0
    = . dst n zero
    ^ @ String { . tmp ctl }
}

// Copy all bytes with ASCII 'A'..'Z' mapped to 'a'..'z'. The output is
// exactly as long as the input, so it is emitted straight through a
// reserved cursor instead of n separate `string_push_char` calls.
@ string_to_lower String str → String {
    : i n ( string_len str )
    : String out ( string_with_cap n )
    ? > n 0 {
        : *u src ( vec_data [u] ( __sbuf str ) )
        : *u w ( string_reserve_at out n )
        : ~ i i 0
        ~ < i n {
            : ~ i c & # i . src i 255
            ? & >= c 65 <= c 90 { = c + c 32 } {}
            = . w i # u c
            = i + i 1
        }
        ( string_commit out n )
    } {}
    ^ out
}

// Copy all bytes with ASCII 'a'..'z' mapped to 'A'..'Z'. Cursor-emitted
// like `string_to_lower`.
@ string_to_upper String str → String {
    : i n ( string_len str )
    : String out ( string_with_cap n )
    ? > n 0 {
        : *u src ( vec_data [u] ( __sbuf str ) )
        : *u w ( string_reserve_at out n )
        : ~ i i 0
        ~ < i n {
            : ~ i c & # i . src i 255
            ? & >= c 97 <= c 122 { = c - c 32 } {}
            = . w i # u c
            = i + i 1
        }
        ( string_commit out n )
    } {}
    ^ out
}

// Bytewise reverse. Safe for ASCII; reverses code units, not UTF-8 scalars.
@ string_reverse String str → String {
    : i n ( string_len str )
    : String out ( string_with_cap n )
    ? > n 0 {
        : *u src ( vec_data [u] ( __sbuf str ) )
        : *u w ( string_reserve_at out n )
        : ~ i i 0
        ~ < i n {
            = . w i . src - - n 1 i
            = i + i 1
        }
        ( string_commit out n )
    } {}
    ^ out
}

// Concatenate `str` with itself `times` times. times ≤ 0 yields empty.
@ string_repeat String str i times → String {
    : i n ( string_len str )
    : i want ? > times 0 * n times 0
    : String out ( string_with_cap want )
    : ~ i k 0
    ~ < k times {
        ( string_push_str out ( string_data str ) )
        = k + k 1
    }
    ^ out
}

// Strip leading whitespace bytes (is_space).
@ string_trim_start String str → String {
    : i n ( string_len str )
    : ~ i start 0
    : ~ b more T
    ~ more {
        ? >= start n { = more F } {
            ? == ( is_space ( string_get str start ) ) 0 { = more F } {
                = start + start 1
            }
        }
    }
    ^ ( string_substr str start - n start )
}

// Strip trailing whitespace bytes.
@ string_trim_end String str → String {
    : i n ( string_len str )
    : ~ i end n
    : ~ b more T
    ~ more {
        ? <= end 0 { = more F } {
            ? == ( is_space ( string_get str - end 1 ) ) 0 { = more F } {
                = end - end 1
            }
        }
    }
    ^ ( string_substr str 0 end )
}

// Strip both leading and trailing whitespace.
@ string_trim String str → String {
    : i n ( string_len str )
    : ~ i start 0
    : ~ b more T
    ~ more {
        ? >= start n { = more F } {
            ? == ( is_space ( string_get str start ) ) 0 { = more F } {
                = start + start 1
            }
        }
    }
    : ~ i end n
    = more T
    ~ more {
        ? <= end start { = more F } {
            ? == ( is_space ( string_get str - end 1 ) ) 0 { = more F } {
                = end - end 1
            }
        }
    }
    ^ ( string_substr str start - end start )
}

// Split `str` on every non-overlapping occurrence of `sep` (raw `s`).
// Always returns at least one element. Empty separator → single-element
// Vec containing a copy of the whole string. Adjacent separators and
// separators at the boundaries produce empty String elements, mirroring
// Rust's `str::split` semantics.
@ string_split String str s sep → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( string_len str )
    : i slen ( nurl_str_len sep )
    ? == slen 0 {
        ( vec_push [String] out ( string_from ( string_data str ) ) )
        ^ out
    } {}

    : ~ i start 0
    : ~ b going T
    ~ going {
        : s cur # s + # i ( string_data str ) start
        : i found ( nurl_str_find cur sep )
        ? < found 0 {
            ( vec_push [String] out ( string_substr str start - n start ) )
            = going F
        } {
            ( vec_push [String] out ( string_substr str start found ) )
            = start + start + found slen
        }
    }
    ^ out
}

// Replace every non-overlapping occurrence of `from` in `str` with `to`.
// Empty `from` is a no-op (returns a copy of `str`); matching stops at
// byte boundaries, no regex.
@ string_replace String str s from s to → String {
    : i flen ( nurl_str_len from )
    ? == flen 0 { ^ ( string_from ( string_data str ) ) } {}

    : i n ( string_len str )
    : String out ( string_with_cap n )
    : ~ i start 0
    : ~ b going T
    ~ going {
        : s cur # s + # i ( string_data str ) start
        : i found ( nurl_str_find cur from )
        ? < found 0 {
            ( string_push_str out cur )
            = going F
        } {
            ? > found 0 {
                : s chunk ( nurl_str_slice cur 0 found )
                ( string_push_str out chunk )
            } {}
            ( string_push_str out to )
            = start + start + found flen
        }
    }
    ^ out
}

// Concatenate every element of `parts` into a fresh owned String,
// inserting `sep` between adjacent elements (not before the first or
// after the last). The complement of `string_split`:
// `string_join ( string_split s "," ) ","` reproduces `s`. `parts` is
// borrowed — its Strings are not consumed.
@ string_join ( Vec String ) parts s sep → String {
    : i n ( vec_len [String] parts )
    : i slen ( nurl_str_len sep )
    : String out ( string_new )
    : ~ i k 0
    ~ < k n {
        ? > k 0 {
            ? > slen 0 { ( string_push_str out sep ) } {}
        } {}
        : ?String elem ( vec_get [String] parts k )
        ?? elem {
            T part → { ( string_push_str out ( string_data part ) ) }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

// Count non-overlapping occurrences of `needle` in `str`. Empty needle
// returns 0. After a match the scan resumes past the whole match, so
// `string_count "aaaa" "aa"` is 2, not 3.
@ string_count String str s needle → i {
    : i nlen ( nurl_str_len needle )
    ? == nlen 0 { ^ 0 } {}
    : ~ i start 0
    : ~ i count 0
    : ~ b going T
    ~ going {
        : s cur # s + # i ( string_data str ) start
        : i found ( nurl_str_find cur needle )
        ? < found 0 {
            = going F
        } {
            = count + count 1
            = start + start + found nlen
        }
    }
    ^ count
}
