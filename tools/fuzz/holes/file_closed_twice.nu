// file_closed_twice: a C FILE handle typed as a string, closed twice from safe code.
// map: §3 | B | rejected | h100 | FFI FILE handle typed as s, fclose called twice from safe code
@ main → i {
    : s f ( fopen `/etc/hostname` `r` )
    ? == # i f 0 { ^ 0 } {}
    ( fclose f )
    ( fclose f )
    ^ 0
}
