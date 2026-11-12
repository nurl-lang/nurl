// locked_value_taken_and_never_restored_is_dropped_once_runs_clean: a `Locked D` (D with a destructor that pushes onto a Vec field) checked out with locked_take and never put back, then its last share dropped.
// Agora #795: the last share's drop ran D's destructor again on the zero bytes the take left (a write through a null Vec: SEGV); Locked_drop now releases only the latch when the value is out (nurl_lk_taken).
// map: §6.5 | A3 | runs-clean | - | agora #795: a Locked value taken and never restored is dropped once, by its taker
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Logged { ( Vec i ) seen i id }

% Drop Logged { @ drop Logged r → v { : ~ ( Vec i ) s . r seen ( vec_push [i] s . r id ) ( nurl_println_int ( vec_len [i] s ) ) } }

@ main → i {
    : ( Locked Logged ) l ( locked_new [Logged] @ Logged { ( vec_new [i] ) 7 } )
    { : Logged c ( locked_take [Logged] l ) }
    ^ 0
}
