// arcweak_of_a_node_with_a_weak_parent_edge_upgraded_on_two_threads_runs_clean: a tree node keeps a weak back-edge to its parent, `: Node { i val ?( ArcWeak Node ) parent }` — the use `stdlib/std/arc.nu` gives `ArcWeak` for. An `( ArcWeak Node )` of the child is captured by a `thread_spawn` closure, which upgrades it, follows the back-edge and reads the parent while the spawner does the same; an `( Arc Node )` is captured the same way. Every count is atomic and nothing is changed after the nodes are made.
// main: refused the `( Arc Node )` capture — it took the `ArcWeak` in the node for a share handle whose copies are one unsynchronised state, which an Arc's payload may not hold.
// The control for arcweak_of_an_arcweak_of_a_share_handle_upgraded_and_changed_on_another_thread: an `ArcWeak` below an `Arc` or an `ArcWeak` is that Arc again, not an unsynchronised share handle.
// map: §6.5 | A3 | runs-clean | - | guard: `( ArcWeak Node )` and `( Arc Node )` of a node holding an `?( ArcWeak Node )` back-edge, captured by a spawned closure and walked on both threads: an ArcWeak is its Arc to the Sync question too (agora #690)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`

: Node { i val ? ( ArcWeak Node ) parent }

@ parent_val ( Arc Node ) child → i {
    ?? . ( arc_get [Node] child ) parent {
        T pw → {
            ?? ( arc_weak_upgrade [Node] pw ) {
                T par → { ^ . ( arc_get [Node] par ) val }
                F → {}
            }
        }
        F → {}
    }
    ^ 0
}

@ walk ( ArcWeak Node ) cw i n → i {
    : ~ i k 0
    : ~ i sum 0
    ~ < k n {
        ?? ( arc_weak_upgrade [Node] cw ) {
            T child → { = sum + sum ( parent_val child ) }
            F → {}
        }
        = k + k 1
    }
    ^ sum
}

@ main → i {
    : ( Arc Node ) root ( arc_new [Node] @ Node { 7 @ ?( ArcWeak Node ) { F } } )
    : ( Arc Node ) child ( arc_new [Node] @ Node { 1 @ ?( ArcWeak Node ) { T ( arc_downgrade [Node] root ) } } )
    : ( ArcWeak Node ) c1 ( arc_downgrade [Node] child )
    : ( ArcWeak Node ) c2 ( arc_downgrade [Node] child )
    : ( Arc Node ) strong ( arc_clone [Node] child )
    : ( Channel i ) out ( chan_new [i] )
    : ~ i here 0
    ?? ( thread_spawn \ → v { : b told ( chan_send [i] out + ( walk c2 20000 ) ( parent_val strong ) ) } ) {
        T t → {
            = here ( walk c1 20000 )
            ( thread_join t )
        }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T there → { ^ - + here there 280007 }
        F → {}
    }
    ^ 9
}
