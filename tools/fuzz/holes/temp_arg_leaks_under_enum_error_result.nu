// temp_arg_leaks_under_enum_error_result: a handle temporary (a MappedFile, any struct with share / drop hooks) handed to a call whose result is `!T E` with an enum error (`!ZipArchive ZipErr`) was never dropped: the result did not count as a value that cannot hold the argument, so the temporary was deferred for a consumer a `:` binding never is.
// Closed: an option / result part that holds no address (an error enum) counts as such a value; the temporary is dropped after the call unless the callee keeps it.
// main's compiler: LeakSanitizer, detected memory leaks.
// map: §7.1 | A2 | runs-clean | h261 | handle temporary passed to call returning !T Enum never dropped (leak)
$ `stdlib/core/io.nu`
$ `stdlib/std/mmap.nu`

: | KE { KBad KWorse }

: Keep { MappedFile m i n }

: K2 { ( Arc Keep ) a }

@ keep_e MappedFile m → !K2 KE {
    ? < ( mapped_len m ) 0 { ^ @ !K2 KE { F KBad } } {}
    ^ @ !K2 KE { T @ K2 { ( arc_new [Keep] @ Keep { m 1 } ) } }
}

@ main → i {
    : ( Vec u ) bytes ( vec_zeroed [u] 30 )
    : !K2 KE r ( keep_e ( mapped_of_bytes bytes ) )
    ?? r { T k → { ( nurl_println_int ( mapped_len . ( arc_get [Keep] . k a ) m ) ) } F _ → {} }
    ^ 0
}
