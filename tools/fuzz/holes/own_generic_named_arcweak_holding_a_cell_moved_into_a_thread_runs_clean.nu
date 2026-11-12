// own_generic_named_arcweak_holding_a_cell_moved_into_a_thread_runs_clean: the program declares a generic struct of its own named `ArcWeak` (`stdlib/std/arc.nu` is not imported) — a plain value holding its argument. An `( ArcWeak Cell )` is moved into a `thread_spawn` closure, which writes the Cell: a `Cell` is Send and the struct is in one thread at a time.
// The library's `ArcWeak` holds its payload to Sync, as its `Arc` does; a type that merely has the name is what its fields make it.
// map: §6.5 | A3 | runs-clean | - | guard: a program's own `: ArcWeak [T] { T inner i n }` at `Cell` moved into a spawned closure: the ArcWeak rule asks what the type is, not what it is called (agora #690)
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/cell.nu`

: ArcWeak [T] { T inner i n }

@ main → i {
    : ( ArcWeak Cell ) p @ ( ArcWeak Cell ) { ( cell_new 8 ) 1 }
    : ( Channel i ) out ( chan_new [i] )
    ?? ( thread_spawn \ → v {
        ( cell_write_u8 . p inner 0 7 )
        : b told ( chan_send [i] out ( cell_read_u8 . p inner 0 ) )
    } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T got → { ^ - got 7 }
        F → {}
    }
    ^ 9
}
