// let_match_join_outer_owner_in_loop_read_after: agora #242 — `: String t ?? o { T _ → a F → b }` in a loop body over owners made before it, `t` only read; after the loop `a` is read. The binding gives back what it took where it dies (__jpb_putback), every pass (let_match_join_outer_owner_in_loop_read_after).
// Pin: the walk gives it back too (bck_join_giveback): A2's `while` asks the body to leave Γ as it found it, and with the give-back it does — `a` is its own after the loop.
// main: rejected ("use of possibly-moved value 'a'"), though it runs clean: the walk had no give-back.
// map: §2.2 | A2 | runs-clean | - | agora #242: a loop body's `:` match join over outer owners, the owner read after the loop
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : ~ i k 0
    : ~ i n 0
    ~ < k 3 {
        : ?i o ? == 0 % k 2 @ ?i { T k } @ ?i { F }
        : String t ?? o { T _ → a F → b }
        = n + n ( string_len t )
        = k + k 1
    }
    ( nurl_println_int + n ( string_len a ) )
    ^ 0
}
