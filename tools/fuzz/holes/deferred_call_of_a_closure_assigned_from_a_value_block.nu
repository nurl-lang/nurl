// deferred_call_of_a_closure_assigned_from_a_value_block: `; { ( a 1 ) }`, then `= a { : String s … : h \ … s … h }` — the unblocked `: h …  = a h` is refused.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846).
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §5.3 | A2 | rejected | - | agora #846, #638: a defer running a closure over a value block's binding, released before the defers run
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : ~ ( @ i i ) a \ i j → i { ^ j }
    ; { ( nurl_println_int ( a 1 ) ) }
    = a { : String s ( string_from `abcdefghijklmnopqrstuvwxyz` ) : ( @ i i ) h \ i j → i { ^ + j ( string_len s ) } h }
    ^ 0
}
