// view_loop_left_right_after_what_they_view_grew_runs_clean: agora #492 — a view read, its source grown, then `break`: no later round reads an ended view
// Control for agora #492: only a read of a view that ended is refused.
// map: §2.5 | A2 | runs-clean | - | agora #492: a view read, its source grown, then `break`: no later round reads an ended view
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ growstr String l → v {
    : ~ i k 0
    ~ < k 64 { ( string_push_str l ` and a long tail, so the buffer moves` ) = k + k 1 }
}

@ main → i {
    : ~ String line ( string_from `a line long enough for a heap buffer` )
    : ~ String line2 ( string_from `another line long enough for a heap buffer` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    ( vec_push [s] ws ( string_data line ) )
    ( vec_push [s] ws ( string_data line ) )
    : ~ i done 0
    ~ v ws {
        ( nurl_println v )
        ( growstr line )
        break
    }
    ^ 0
}
