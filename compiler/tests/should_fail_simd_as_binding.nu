// `simd` is a reserved word from grammar v2.5 on, so it cannot name a
// binding. The diagnostic says which keyword it is rather than the
// generic "expected a binding name", because the reader's next question
// is always "since when".
$ `stdlib/core/io.nu`

@ main → v {
    : i simd 4
    ( nurl_print ( nurl_str_int simd ) )
}
