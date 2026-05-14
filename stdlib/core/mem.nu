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

@ alloc [T] i n → *T {
    ^ # *T ( nurl_alloc * Z T n )
}

@ zalloc [T] i n → *T {
    ^ # *T ( nurl_zalloc * Z T n )
}
