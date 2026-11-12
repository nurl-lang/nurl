// A generic of eight fields nested eight deep, owned by a binding and
// captured by a thread (agora #722): every type walk that asks what a type
// holds — a `% Drop` of the program's own, whether it needs drop glue, the
// thread-shared nodes, the shares a crossing counts — asks each of its
// eight types once per question. Walked as every path to a type, it was
// 8^8 lookups per question and ~117 s to compile; the test runner's
// compile timeout fails it if that comes back.
$ `stdlib/std/thread.nu`

: D [T] { T f0 T f1 T f2 T f3 T f4 T f5 T f6 T f7 }

@ look ( D ( D ( D ( D ( D ( D ( D ( D i ) ) ) ) ) ) ) ) x → v {}

@ run sink ( D ( D ( D ( D ( D ( D ( D ( D i ) ) ) ) ) ) ) ) x → v {
    ?? ( thread_spawn \ → v { ( look x ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
}

@ main → i {
    ( nurl_println_int 8 )
    ^ 0
}
