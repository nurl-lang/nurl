// struct_field_viewed_past_a_callee_reading_it_runs_clean: a callee that only reads `. a name` through a local
// Kept: a callee that reads a handle read out of its parameter moves nothing (agora #647).
// main c5115caa: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #647: a struct field's view past a callee reading it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name i n }

@ ext App a → v {
    : String nm . a name
    ( nurl_println_int # i ( string_len nm ) )
}

@ main → i {
    : App app @ App { ( string_from `a name long enough to live on the heap` ) 1 }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
