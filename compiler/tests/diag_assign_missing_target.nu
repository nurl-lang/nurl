// diag_assign_missing_target.nu — '=' with the value where the target
// belongs. Assignment is prefix ('= name value'), so a model carrying
// infix habits writes '= 5 n' or 'n = 5'; the message has to name the
// form rather than only reject the token.
@ main → i {
    : ~ i n 0
    = 5 n
    ^ n
}
