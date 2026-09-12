// A closure literal is still a dead value, even with try in its body.
: | ClosureErr { ClosureFailed }

@ step → !i ClosureErr { ^ @ !i ClosureErr { T 1 } }

@ main → i {
    \ → !i ClosureErr { : i x \ ( step ) ^ @ !i ClosureErr { T x } }
    ( nurl_print `closure discarded\n` )
    ^ 0
}
