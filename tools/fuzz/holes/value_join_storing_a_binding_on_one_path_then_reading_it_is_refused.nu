// value_join_storing_a_binding_on_one_path_then_reading_it_is_refused: a value `?` whose then-arm stores `k1` into a literal and whose else-arm does not; `k1` is read after the join.
// Guard for agora #757: a value `?`'s arms' stores are written per arm (a `cond` with a block per arm), so the walk joins "stored" with "owned" after the `?`, and a read of the binding is a use of a possibly-moved value, refused as before.
// main: refused ("'k1' is read here, but its value was moved into 'r'"); with #757: refused ("use of possibly-moved value 'k1'").
// map: §7.6 | A2 | rejected | - | agora #757 guard: a binding stored by one arm of a value `?` and read after it stays refused
$ `stdlib/core/vec.nu`

: K { ( Vec u ) a ( Vec u ) b }

@ f i c → i {
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : ( Vec u ) k3 ( vec_new [u] )
    : ( Vec u ) k4 ( vec_new [u] )
    : K r ? == c 1 @ K { k1 k2 } @ K { k3 k4 }
    ^ # i ( vec_len [u] k1 )
}

@ main → i { ^ ( f 0 ) }
