// diag_assign_int_to_ptr.nu — assigning a bare integer into a pointer
// binding. `= p 5` with `p : ~ *i` used to emit `store i64* 5` /
// `store i8* %n` — invalid IR that nurlc accepted (rc 0) and only
// clang rejected. Same rule and cure as the binding-init form: no
// implicit integer-to-pointer conversion; '# *T expr' converts
// intentionally.
@ main → i {
    : ~ * i p # *i 0
    = p 5
    ^ 0
}
