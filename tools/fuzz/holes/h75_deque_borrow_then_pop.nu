// H75: a deque_get borrow; the element is popped and dropped; the borrow is read.
$ `stdlib/std/deque.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Deque String ) d ( deque_new [String] )
    ( deque_push_back [String] d ( string_from `a long element string on the heap` ) )
    ?? ( deque_get [String] d 0 ) {
        T e → {
            ?? ( deque_pop_front [String] d ) { T q → { ( string_free q ) } F → {} }
            ( nurl_println_int ( string_len e ) )
        }
        F → {}
    }
    ^ 0
}
