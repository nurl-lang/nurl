// OPEN in 0.72.0 — a keyword-argument call to a function defined later misses that the callee consumes it.
// `retain` (defined after main) hands its `String value` on to `consume`, a `sink String`, so it takes
// the caller's String over. The positional call ( retain raw ) is handled and runs clean; the keyword
// form ( retain value : raw ) is not, so main still drops `raw` at scope exit — a second release.
// ASan: heap-use-after-free in nurl_vec_drop (main's drop of `raw`, which consume already released).
$ `stdlib/core/string.nu`

@ main → i {
    : String raw ( string_from `abc` )
    ( nurl_println_int ( retain value : raw ) )
    ( nurl_println `KWARGS-MARK` )
    ^ 0
}

@ retain String value → i { ^ ( consume value ) }

@ consume sink String v → i { ^ ( string_len v ) }
