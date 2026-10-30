// dyn_inout_method_through_a_read_guard: a trait object read through an RwLocked's read guard, copied into a `: ~` binding and handed to a method with an `inout` receiver: the impl wrote the object's box in place — what every reader of the lock sees — and released the String it replaced while a view of it was still read.
// Closed: a `dyn` method with an `inout` receiver changes the object's box (the virtual callee's mutation summary has its receiver, whatever the impls write), so it is a change to what a read guard lends; and its replacement summary is the impls' (h365).
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §6.5 | A3 | rejected | h364 | a trait object read through a read guard, copied into a : ~ binding and handed to a method with an inout receiver: the impl wrote the box every reader sees; an inout receiver through a trait object changes the object, so it is a change to what the guard lends
$ `stdlib/core/string.nu`
$ `stdlib/std/rwlock.nu`

: Named { String name }

% Label [T] : Send Sync {
    @ rename inout T self → v
    @ name T self → String
}

% Label Named {
    @ rename inout Named c → v { = . c name ( string_from `a different name, long enough for a heap buffer` ) }
    @ name Named c → String { ^ . c name }
}

@ main → i {
    : ( RwLocked % Label ) l ( rw_new [% Label] ( dyn Label @ Named { ( string_from `the first name, long enough for a heap buffer` ) } ) )
    : ( RGuard % Label ) g ( rw_read [% Label] l )
    : String n ( name ( rguard_get [% Label] g ) )
    : ~ % Label k ( rguard_get [% Label] g )
    ( rename k )
    ( nurl_println ( string_data n ) )
    ^ 0
}
