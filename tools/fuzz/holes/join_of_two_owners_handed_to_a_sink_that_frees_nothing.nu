// join_of_two_owners_handed_to_a_sink_that_frees_nothing: agora #451 — `( eat ? c u t )`, eat only reading its `sink` parameter: the callee's drop at return and the block's drop of the owner
// Closed: a `?`/`??` whose arms lend bindings on every path (no ownership of its own) is copied where a consuming parameter takes it, as a join that lends on some paths is (gen_call; agora #451).
// main: heap-use-after-free (base 2f2e1f7e too).
// map: §7.6 | A2 | runs-clean | - | agora #451: `( eat ? c u t )`, eat only reading its `sink` parameter: the callee's drop at return and the block's drop of the owner
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : b c F
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : String u ( string_from `another heap string, long enough to be on the heap` )
        ( nurl_println_int ( eat ? c u t ) )
    }
    ^ 0
}
