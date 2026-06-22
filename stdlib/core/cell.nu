// stdlib/core/cell.nu — opaque platform-sized byte buffer.
//
// `Cell` is the FFI-storage primitive: a heap-allocated, zero-init
// byte buffer of caller-chosen size. Used wherever NURL needs to hold
// a C-side struct whose layout NURL doesn't know — `pthread_mutex_t`,
// `pthread_cond_t`, `sigset_t`, `struct stat`, libcurl handles, etc.
//
// Where `Box[T]` requires a NURL-side type T (so `Z T` knows the
// size), `Cell` takes a byte count given at construction time. The
// platform-varying sizes that motivate this — `sizeof(pthread_mutex_t)`
// is 40 on glibc x86_64 but 64 on macOS, and `CRITICAL_SECTION` is a
// different shape entirely on Windows — come from the tiny C-side
// `nurl_native_sizeof(name)` thunk; see `cell_for_native`.
//
// API:
//
//   ( cell_new  i n )              → Cell      n bytes uninitialised
//   ( cell_zero i n )              → Cell      n bytes zero-init
//   ( cell_for_native s name )     → Cell      sized via nurl_native_sizeof
//   ( cell_size Cell c )           → i         capacity in bytes
//   ( cell_ptr  Cell c )           → *u        raw byte pointer (FFI)
//   ( cell_ptr_as [T] Cell c )     → *T        same pointer, typed (FFI)
//   ( cell_is_null Cell c )        → b         T iff allocation failed
//   ( cell_read_u8  Cell c i off ) → i         byte read at offset
//   ( cell_write_u8 Cell c i off i v ) → v     byte write at offset
//   ( cell_zero_fill Cell c )      → v         memset to 0
//   ( cell_clone Cell c )          → Cell      memcpy bytes; CAREFUL with FFI state
//   ( cell_free Cell c )           → v         release the buffer
//
// Memory model:
//
//   * The Cell handle is a struct `{ s ptr i bytes }` — two words.
//     The byte pointer comes from `nurl_alloc` / `nurl_zalloc`; the
//     size is recorded so `cell_clone` knows how much to copy and
//     `cell_read_u8` / `cell_write_u8` can bounds-check.
//   * `cell_ptr` returns a borrowed pointer; valid until `cell_free`.
//   * `cell_clone` is BITWISE — it copies the bytes verbatim. For
//     FFI state that has been initialised via a C-side init function
//     (`pthread_mutex_init`, `pthread_cond_init`, etc.), a bitwise
//     copy is almost always wrong: those types may hold self-pointers
//     or kernel handles. Treat `cell_clone` as a tool for raw byte
//     blobs (data the program owns), NOT for live FFI state. Use the
//     C-side init/clone primitive on a fresh `cell_zero` instead.
//   * No platform-specific alignment knobs are exposed: `nurl_alloc`
//     already returns malloc-aligned (16 or 8 bytes depending on
//     libc), which suffices for every FFI struct NURL currently
//     instantiates. If a future user needs `__attribute__((aligned(64)))`
//     storage (e.g. cache-line padding), wire `nurl_aligned_alloc`
//     into a `cell_aligned` constructor.
//
// Why a Cell + a Box rather than a single primitive:
//
//   * `Box[T]` carries a NURL-side type, so `Z T` + `# *T` give
//     compile-time-known layout. Field access is checked. The compiler
//     can monomorphise it. Good for NURL structs.
//   * `Cell` is layout-opaque: callers pass `*u` to C and the C side
//     casts to its own struct. NURL never reads through the pointer
//     via a typed lens. This is the right shape for `pthread_mutex_t`
//     and friends, whose internal layout we don't want to mirror.

// FFI: the runtime-side platform-sizeof thunk. Defined in stdlib/runtime.c.
// Returns sizeof(<name>) for known C-level types, -1 for unknown.
// Known names (case-sensitive):
//   "pthread_mutex_t"  "pthread_cond_t"   "pthread_t"
//   "pthread_rwlock_t" "pthread_attr_t"   "pthread_mutexattr_t"
//   "pthread_condattr_t"
//   "sigset_t"         "struct stat"      "struct timespec"
//   "struct sockaddr_in" "struct sockaddr_in6" "struct sockaddr_storage"
//   "int" "long" "size_t" "off_t" "time_t"
& `c` @ nurl_native_sizeof s name → i

: Cell {
    s ptr
    i bytes
}

// ── Constructors ────────────────────────────────────────────────────

@ cell_new i n → Cell {
    ? <= n 0 { ^ @ Cell { # s 0 0 } } {}
    : s p ( nurl_alloc n )
    ^ @ Cell { p n }
}

@ cell_zero i n → Cell {
    ? <= n 0 { ^ @ Cell { # s 0 0 } } {}
    : s p ( nurl_zalloc n )
    ^ @ Cell { p n }
}

// Look up the platform sizeof for `name`, allocate that many zero
// bytes. Returns a Cell with bytes=0 and ptr=NULL when the name is
// unknown to the runtime — callers should treat that as a hard
// platform-portability bug, not a runtime error to recover from.
@ cell_for_native s name → Cell {
    : i sz ( nurl_native_sizeof name )
    ? <= sz 0 { ^ @ Cell { # s 0 0 } } {}
    : s p ( nurl_zalloc sz )
    ^ @ Cell { p sz }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ cell_size Cell c → i {
    ^ . c bytes
}

@ cell_ptr Cell c → *u {
    ^ # *u . c ptr
}

// Typed alias for the same byte pointer. The caller is asserting that
// the bytes at `. c ptr` are a valid `T` — purely a NURL-side type
// hint, no runtime cast happens.
@ cell_ptr_as [T] Cell c → *T {
    ^ # *T . c ptr
}

@ cell_is_null Cell c → b {
    ^ == 0 # i . c ptr
}

// ── Byte access ─────────────────────────────────────────────────────

// Read a single byte at `off`. Returns 0 when `off` is out of range —
// no panic, no out-of-bounds read, no abort: the caller almost always
// wraps a series of these in a bigger decoder and a 0 is a tractable
// sentinel. (Bounds-check failures are reported via the `__last_…`
// sideband in future revisions; not wired yet.)
@ cell_read_u8 Cell c i off → i {
    ? | < off 0 >= off . c bytes { ^ 0 } {}
    : *u p # *u . c ptr
    ^ & 255 # i . p off
}

@ cell_write_u8 Cell c i off i v → v {
    ? | < off 0 >= off . c bytes {} {
        : *u p # *u . c ptr
        = . p off # u & v 255
    }
}

// memset the buffer back to all zeros. Useful when re-using a Cell
// for a fresh FFI init call.
@ cell_zero_fill Cell c → v {
    : i n . c bytes
    ? <= n 0 {} {
        : *u p # *u . c ptr
        : ~ i i 0
        ~ < i n { = . p i # u 0 = i + i 1 }
    }
}

// ── Cloning ─────────────────────────────────────────────────────────

// Bitwise copy of the bytes. CAUTION: see file-header note — almost
// never what you want for live FFI state.
@ cell_clone Cell c → Cell {
    : i n . c bytes
    ? <= n 0 { ^ @ Cell { # s 0 0 } } {}
    : *u src # *u . c ptr
    : s p ( nurl_alloc n )
    : *u dst # *u p
    : ~ i i 0
    ~ < i n {
        = . dst i . src i
        = i + i 1
    }
    ^ @ Cell { p n }
}

// ── Lifecycle ───────────────────────────────────────────────────────

@ cell_free Cell c → v {
    : s p . c ptr
    ? != 0 # i p { ( nurl_free p ) } {}
}
