// struct_owners_rotated_by_assignment_in_a_loop_runs_clean: three owners of a struct that holds a String, rotated by assignment in a loop, `a` and `b` read after it.
// Closed (agora #634): a struct that owns a String was handed over like one — a cursor until a later `=` of its source — and `b` was read freed in the loop's second round (heap-use-after-free). The assignment out of an owner is a move in the generated code now.
// map: §2.2 | A2 | runs-clean | - | agora #634: three struct owners rotated by assignment in a loop
$ `stdlib/core/string.nu`

: P { String name i n }

@ mk s x → P { ^ @ P { ( string_from x ) 1 } }

@ main → i {
    : ~ P a ( mk `the first string, long enough for the heap, yes` )
    : ~ P b ( mk `the second string, long enough for the heap, yes` )
    : ~ P t ( mk `the third string, long enough for the heap, yes` )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    ( nurl_println ( string_data . a name ) )
    ( nurl_println ( string_data . b name ) )
    ^ 0
}
