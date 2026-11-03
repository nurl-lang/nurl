// join_of_two_owners_handed_to_a_callee_that_keeps_it: agora #451 — `( eat ? c u t )`, eat keeping or releasing its parameter without declaring `sink`
// Closed: a `?`/`??` whose arms lend bindings on every path (no ownership of its own) is copied where a consuming parameter takes it, as a join that lends on some paths is (gen_call; agora #451).
// main: heap-use-after-free (base 2f2e1f7e too).
// map: §7.6 | A2 | runs-clean | - | agora #451: `( eat ? c u t )`, eat keeping or releasing its parameter without declaring `sink`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ eat String s → v { ( nurl_println ( string_data s ) ) ( string_free s ) }

@ main → i {
    : b c F
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : String u ( string_from `another heap string, long enough to be on the heap` )
        ( eat ? c u t )
    }
    ^ 0
}
