// struct_named_with_leading_underscores_holding_an_rc_captured_by_a_thread: a struct of the program's own is named `__Holder` — leading underscores are a name's own — and holds an `Rc`. A value of it is captured by a `thread_spawn` closure while the spawner keeps another share of the same `Rc`: both threads clone and drop it, and its count is not atomic. Every rule that walks a type by its name reads the name's base; read as "up to the first `__`" the base of `__Holder` was the empty name, a type with no fields, and the `Rc` in it crossed unseen.
// main: accepted — the Send walk found no fields under the empty base; the count is torn and a share freed early (ASan: heap-use-after-free). The base is the declared name whole, its leading underscores included (`__lty_base_end`).
// map: §6.5 | A3 | rejected | - | a struct named `__Holder` holding an Rc captured by a spawned closure: the name's leading underscores are part of its base, so the Send walk finds the Rc (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

: __Holder { ( Rc i ) r }

@ churn __Holder h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] . h r ) ) = j + j 1 }
        = k + k 1
    }
    ^ ( rc_strong [i] . h r )
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : __Holder h2 @ __Holder { ( rc_clone [i] r ) }
    : __Holder h3 @ __Holder { ( rc_clone [i] r ) }
    ?? ( thread_spawn \ → v { ( churn h3 20000 ) } ) {
        T t → { ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 3
}
