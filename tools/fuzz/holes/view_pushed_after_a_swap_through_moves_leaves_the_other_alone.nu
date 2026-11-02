// view_pushed_after_a_swap_through_moves_leaves_the_other_alone: agora #414 — `= tmp a  = a b  = b tmp  = tmp ( vec_new [s] )`, then a view of a block-local String pushed into `b`, `a` read after the block (the shape the fix must keep)
// Closed: what is stored into a binding marked a copy of an owner's handle or a part of one (`hr_`) lands in that owner too — but a binding given a new value is no part of its old value's owners (`=` replaces the mark), and an owner given a new value leaves the bindings marked a part of its old one (__bck_hr_drop_owner; agora #414).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #414: a view pushed into a binding a swap through moves gave the other one's old value, the other read after its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) a ( vec_new [s] )
    : ~ ( Vec s ) b ( vec_new [s] )
    : ~ ( Vec s ) tmp ( vec_new [s] )
    ( vec_push [s] a `a` )
    ( vec_push [s] b `b` )
    = tmp a
    = a b
    = b tmp
    = tmp ( vec_new [s] )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ( vec_push [s] b ( string_data loc ) )
        ( nurl_println ( vec_at [s] b 1 ) )
    }
    ( nurl_println ( vec_at [s] a 0 ) )
    ^ 0
}
