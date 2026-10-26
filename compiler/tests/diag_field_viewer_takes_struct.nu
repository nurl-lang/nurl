// A binding read out of a library handle field takes the field over when
// it is consumed: emptied, the field holds no handle, so the struct goes
// with it — reading it after is rejected (h348).
$ `stdlib/dist/crdt.nu`

: Holder { PNCounter c }

@ eat sink PNCounter x → v { ( pncounter_inc x 1 1 ) }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter x . h c
    ( eat x )
    ^ % ( pncounter_value . h c ) 256
}
