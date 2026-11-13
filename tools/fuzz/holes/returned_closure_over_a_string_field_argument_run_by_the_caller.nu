// returned_closure_over_a_string_field_argument_run_by_the_caller: `( mk . app name )`, the closure growing the String, a view of its bytes
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a returned closure over a String field argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

: App { String name i n }

@ mk String s → ( @ v ) { ^ \ → v { ( string_push_str s `, and a good deal more text so the buffer has to move somewhere else for sure` ) } }

@ main → i {
    : App app @ App { ( string_from `a name long enough to live on the heap for sure` ) 1 }
    : ( @ v ) c ( mk . app name )
    : s d ( string_data . app name )
    ( c )
    ( nurl_println d )
    ^ 0
}
