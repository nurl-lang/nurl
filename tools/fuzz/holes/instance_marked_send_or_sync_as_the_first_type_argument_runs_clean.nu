// instance_marked_send_or_sync_as_the_first_type_argument_runs_clean: `unsafe % Send ( W ( Rc i ) ) { }` and `unsafe % Sync ( W Cell ) { }` vouch for ONE instance each. Each is the FIRST argument of `: Two [A B] { A first B second }`: a `( Two ( W ( Rc i ) ) i )` is moved into a `thread_spawn` closure that reads the count of an `Rc` nobody else holds, and an `( Arc ( Two ( W Cell ) i ) )` is cloned to it and read.
// main: refused — an instance's marker was found only when the instance stood alone or as the LAST argument of the generic around it; the same two programs with the arguments swapped were accepted.
// map: §6.5 | A3 | runs-clean | - | guard: an instance marked `unsafe % Send` / `unsafe % Sync` as the first argument of another generic, moved into a spawned closure and shared in an Arc: the author's promise holds wherever the instance stands (agora #683, #693)
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/cell.nu`

: W [A] { A x }

: Two [A B] { A first B second }

unsafe % Send ( W ( Rc i ) ) {}

unsafe % Sync ( W Cell ) {}

@ main → i {
    : ( Two ( W ( Rc i ) ) i ) p @ ( Two ( W ( Rc i ) ) i ) { @ ( W ( Rc i ) ) { ( rc_new [i] 5 ) } 1 }
    : ( Arc ( Two ( W Cell ) i ) ) a ( arc_new [( Two ( W Cell ) i )] @ ( Two ( W Cell ) i ) { @ ( W Cell ) { ( cell_new 8 ) } 2 } )
    : ( Arc ( Two ( W Cell ) i ) ) a2 ( arc_clone [( Two ( W Cell ) i )] a )
    : ( Channel i ) out ( chan_new [i] )
    ?? ( thread_spawn \ → v { : b told ( chan_send [i] out + ( rc_strong [i] . . p first x ) . ( arc_get [( Two ( W Cell ) i )] a2 ) second ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T got → { ^ - + got . ( arc_get [( Two ( W Cell ) i )] a ) second 5 }
        F → {}
    }
    ^ 9
}
