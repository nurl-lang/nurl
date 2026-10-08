// stdlib/core/mem.nu — typed memory allocation wrappers
//
// Thin generic wrappers around the `nurl_alloc` / `nurl_zalloc` runtime
// calls. They compute `sizeof(T) * n` via `Z T` and bitcast the returned
// `i8*` to `*T`.
//
//   ( alloc  [T] n )   →  *T    uninitialised buffer for n items
//   ( zalloc [T] n )   →  *T    zero-initialised buffer for n items
//
// Release with ( nurl_free #s p ). Typed `drop`/`resize` may follow.
//
// Sizes are checked (`alloc_size`, stdlib/core/vec.nu): a count whose byte
// size cannot be represented panics before anything is allocated.

$ `stdlib/core/vec.nu`

@ alloc [T] i n → *T {
    ^ # *T ( nurl_alloc ( alloc_size Z T n ) )
}

@ zalloc [T] i n → *T {
    ^ # *T ( nurl_zalloc ( alloc_size Z T n ) )
}
