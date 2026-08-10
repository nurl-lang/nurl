// diag_paren_type_bad.nu — parentheses in type position used as
// grouping. They are not: there are exactly two parenthesised type
// forms, and the message now names both rather than only listing what
// was expected.
@ main → i {
    : ( 5 ) x 0
    ^ 0
}
