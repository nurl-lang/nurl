// `simd` is a prefix on function declarations only. On any other decl
// it used to be a silent no-op that then attached itself to the next
// `@` the parser reached — the same cross-file drift `pub` had before
// grammar v2.0 made it read-and-clear. It is a diagnostic instead.
$ `stdlib/core/io.nu`

simd : i WIDTH 32

@ main → v { ( nurl_print ( nurl_str_int WIDTH ) ) }
