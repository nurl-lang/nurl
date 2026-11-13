// An `inout` slice parameter given a slice it does not own gets a copy of its
// buffer, but a slice whose elements own values (Strings) cannot be copied
// element by element there: the caller's slot would share the Strings with
// their owner. Refused, with the ways out (agora #545).
$ `stdlib/core/string.nu`

@ setq inout [String p [String q → v { = p q }

@ main → i {
    : ~ [String d [String | ( string_from `old element long enough for a heap buffer` )]
    : [String q [String | ( string_from `q element long enough for a heap buffer` )]
    ( setq d q )
    ^ 0
}
