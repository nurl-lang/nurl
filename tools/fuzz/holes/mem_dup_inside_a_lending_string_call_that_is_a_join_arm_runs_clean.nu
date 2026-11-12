// mem_dup_inside_a_lending_string_call_that_is_a_join_arm_runs_clean: `? c ( pick o ( mem_dup x ) ) ( string_from … )` — a String arm that is a call lending `o`; the `mem_dup` copy inside it is only its argument.
// Control for agora #688: the String twin of mem_dup_inside_a_lending_call_that_is_a_join_arm_runs_clean.
// map: §7.6 | A2 | runs-clean | - | agora #688: a mem_dup copy inside a lending call that is a ? arm (String)
$ `stdlib/core/string.nu`

@ pick String a String b → String { ^ a }

@ f String o String x b c → String { ^ ? c ( pick o ( mem_dup x ) ) ( string_from `a fresh one long enough for the heap buffer` ) }

@ main → i {
    : String o ( string_from `the owner's string, long enough for the heap` )
    : String x ( string_from `another string, long enough for the heap ok` )
    : String r ( f o x T )
    ^ - ( string_len r ) ( string_len o )
}
