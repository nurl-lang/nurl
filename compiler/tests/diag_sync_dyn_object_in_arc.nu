// diag_sync_dyn_object_in_arc.nu — an Arc's payload is reached from every
// thread holding a clone, so a trait object in one must be Sync, and
// `: Send` alone does not promise that: every `Job` type may move, but
// not every one may be reached from two threads at once. The fix the
// message names is `: Send Sync` on the trait.
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Count { i n }

% Job [T] : Send { @ run T self → i }

% Job Count { @ run Count c → i { ^ . c n } }

@ main → i {
    : ( Arc % Job ) a ( arc_new [% Job] ( dyn Job @ Count { 1 } ) )
    : ( Arc % Job ) b ( arc_clone [% Job] a )
    ?? ( thread_spawn \ → v { ( nurl_print_int ( arc_strong [% Job] b ) ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
