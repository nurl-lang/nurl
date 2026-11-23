// immutable_global_of_a_vec_zero_pushed: an immutable global of an owning type given `0` (`: ( Vec i ) g_v 0`) starts as zero bytes, a null control block. Neither rule for globals asked about it: a mutable one is reached only from `unsafe`, and one set at start must synchronise itself. Safe code pushed onto it through its handle.
// Closed: a global that never changes may not start as zero bytes that are not a value of its type (a String, a Vec, a library handle, a closure, or what holds one: `__zero_invalid`, as the zero-fill constructors ask). A mutable global behind an `unsafe` accessor, or one set at start, is the way.
// main's compiler: compiled with no `unsafe`; vec_push wrote through the null handle (SIGSEGV on Linux; near address 0 in a wasm linear memory).
// map: §6.5 | A3 | rejected | h975 | immutable zero-initialised Vec global pushed from safe code through its null handle
$ `stdlib/core/vec.nu`

: ( Vec i ) g_v 0

@ add i x → v { ( vec_push [i] g_v x ) }

@ main → i {
    ( add 7 )
    ( nurl_println_int ( vec_len [i] g_v ) )
    ^ 0
}
