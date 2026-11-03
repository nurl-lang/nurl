// view_pushed_through_a_copy_given_a_fresh_value_leaves_the_owner_alone: agora #414 — `: ~ ( Vec s ) w ? == c 1 { vs } { vs2 }`, then `= w ( vec_new [s] )`: a view of a block-local String pushed into `w`, `vs` read after the block (the shape the fix must keep)
// Closed: what is stored into a binding marked a copy of an owner's handle or a part of one (`hr_`) lands in that owner too — but a binding given a new value is no part of its old value's owners (`=` replaces the mark), and an owner given a new value leaves the bindings marked a part of its old one (__bck_hr_drop_owner; agora #414).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #414: a view pushed through a copy of an owner given a fresh value since, the owner read after its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    : ( Vec s ) vs2 ( vec_new [s] )
    ( vec_push [s] vs `keep` )
    : i c 1
    : ~ ( Vec s ) w ? == c 1 { vs } { vs2 }
    ( nurl_println_int ( vec_len [s] w ) )
    = w ( vec_new [s] )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ( vec_push [s] w ( string_data loc ) )
        ( nurl_println ( vec_at [s] w 0 ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
