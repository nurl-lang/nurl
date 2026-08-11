// diag_dot_no_field_name.nu — '. obj' with the field left off. The
// message is the one that has to state prefix order, since the mistake
// usually comes from expecting 'obj.field'.
: S { i a }

@ main → i {
    : S s @ S { 1 }
    ^ . s
}
