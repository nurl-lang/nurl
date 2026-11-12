// self_containing_types_moved_into_a_thread_and_shared_in_an_arc_runs_clean: `: Node { i val ( Vec Node ) kids }` holds itself through a `Vec`, and `: Ping { i n ( Vec Pong ) ps }` / `: Pong { i m ?Ping back }` hold each other; a tree of each is moved into a `thread_spawn` closure, and one of each is shared in an `Arc` both threads read.
// main: accepted — and so it stays: a type that reaches itself is read once, the question it is already being asked about is not asked again, and nothing in either graph is unsynchronised.
// map: §6.5 | A3 | runs-clean | - | the derivation over a type that contains itself, directly and through a second type, ends and answers Send and Sync (agora #711)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: Node { i val ( Vec Node ) kids }
: Ping { i n ( Vec Pong ) ps }
: Pong { i m ? Ping back }

@ leaf i v → Node { ^ @ Node { v ( vec_new [Node] ) } }

@ tree i depth → Node {
    : Node n ( leaf depth )
    ? > depth 0 {
        ( vec_push [Node] . n kids ( tree - depth 1 ) )
        ( vec_push [Node] . n kids ( tree - depth 1 ) )
    } {}
    ^ n
}

@ sum Node n → i {
    : ~ i s . n val
    : ~ i k 0
    ~ < k ( vec_len [Node] . n kids ) {
        = s + s ( sum ( vec_at [Node] . n kids k ) )
        = k + k 1
    }
    ^ s
}

@ ping i n → Ping {
    : Ping p @ Ping { n ( vec_new [Pong] ) }
    ( vec_push [Pong] . p ps @ Pong { + n 1 @ ?Ping { F } } )
    ( vec_push [Pong] . p ps @ Pong { + n 2 @ ?Ping { T @ Ping { + n 3 ( vec_new [Pong] ) } } } )
    ^ p
}

@ weigh Ping p → i {
    : ~ i s . p n
    : ~ i k 0
    ~ < k ( vec_len [Pong] . p ps ) {
        : Pong q ( vec_at [Pong] . p ps k )
        = s + s . q m
        ?? . q back {
            T b → { = s + s ( weigh b ) }
            F _ → {}
        }
        = k + k 1
    }
    ^ s
}

@ main → i {
    : Node moved ( tree 3 )
    : Ping pmoved ( ping 10 )
    : ( Arc Node ) shared ( arc_new [Node] ( tree 2 ) )
    : ( Arc Ping ) pshared ( arc_new [Ping] ( ping 20 ) )
    : ( Arc Node ) s2 ( arc_clone [Node] shared )
    : ( Arc Ping ) p2 ( arc_clone [Ping] pshared )
    : ~ i here 0
    ?? ( thread_spawn \ → v {
        : i a ( sum moved )
        : i b ( weigh pmoved )
        : i c ( sum ( arc_get [Node] s2 ) )
        : i d ( weigh ( arc_get [Ping] p2 ) )
    } ) {
        T t → {
            = here + ( sum ( arc_get [Node] shared ) ) ( weigh ( arc_get [Ping] pshared ) )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ - here + 4 86
}
