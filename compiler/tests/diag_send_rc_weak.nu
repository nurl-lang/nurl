// An Rc's Weak shares the Rc's count block: `weak_upgrade` on another thread
// is a clone of the Rc on a count that is not atomic. A Weak is no more Send
// than its Rc.
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Weak i ) w ( rc_downgrade [i] mine )
    ?? ( thread_spawn \ → v {
        ?? ( weak_upgrade [i] w ) {
            T up → { : i n ( rc_strong [i] up ) }
            F → {}
        }
    } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
