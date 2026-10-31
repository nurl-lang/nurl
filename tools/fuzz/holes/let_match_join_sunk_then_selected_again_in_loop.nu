// let_match_join_sunk_then_selected_again_in_loop: agora #242 (formal's review) — the `??` twin of let_join_sunk_then_selected_again_in_loop: `: String t ?? o { T _ → a F → b }` in a loop, `t` to a `sink` on the first pass only, `a` selected again on the third (let_match_join_sunk_then_selected_again_in_loop).
// Closed: the arm's read on its `endmatch-arm-edge` row (gen_match, bck_handle_match) and the walk's give-back (bck_join_giveback).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #242: a `:` match join's binding sunk on one pass, its owner selected again on a later pass
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : ~ i k 0
    : ~ i n 0
    ~ < k 3 {
        : ?i o ? == 0 % k 2 @ ?i { T k } @ ?i { F }
        : String t ?? o { T _ → a F → b }
        = n + n ( string_len t )
        ? == k 0 { = n + n ( consume t ) } {}
        = k + k 1
    }
    ^ n
}
