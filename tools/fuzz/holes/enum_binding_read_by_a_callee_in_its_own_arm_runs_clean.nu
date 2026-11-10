// enum_binding_read_by_a_callee_in_its_own_arm_runs_clean: the control: a callee that only reads o leaves the payload alone.
// Closed: a call that may replace an inout argument, or drop what it holds, ends the ?? arm payloads read in place out of that program-enum binding's old value, as `= o …` does since #1678 (__bck_epy_release in bck_cursor_follow; agora #565).
// main f4d6b13e: runs clean.
// map: §2.4 | A2 | runs-clean | - | agora #565: a ?? arm replacing its own enum binding through an inout callee
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ peek Msg m → i { ^ ?? m { MSome x → ( string_len x ) MNone → 0 } }

@ run i k → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ? == k 1 { : i z ( peek o ) } {}
            ( nurl_println ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
