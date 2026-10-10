// OPEN in 0.72.0 — a generic's `sink A` instantiated at a raw string: the caller gives its string up and nothing releases it.
// opt_unwrap_or [s] takes its default as `sink A`; with `o` empty it hands `m` back, and the result `r`
// is a raw string — a view — so the string main gave up is released by neither the instance nor main.
// The literal default on the next line is a second shape for the fix: a literal must never be released.
// LSan: detected memory leaks — 5 bytes (the "abcd" buffer of `m`, allocated in main).
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ?s o @ ?s { F }
    : s m ( nurl_str_cat `ab` `cd` )
    : s r ( opt_unwrap_or [s] o m )
    ( nurl_println r )
    ( nurl_println ( opt_unwrap_or [s] o `literal` ) )
    ^ 0
}
