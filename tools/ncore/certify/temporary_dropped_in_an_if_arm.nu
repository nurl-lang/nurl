$ `stdlib/core/string.nu`

// A temporary bound and dropped inside an `if` arm. translate_test.sh (part 1)
// adds a read of it after the `if`: the translation must report that
// unsupported.

@ main → i {
    : String a ( string_from `abc` )
    : ~ i n 0
    ? > 1 0 { = n ( string_len ( string_from `xy` ) ) } {}
    ^ + n ( string_len a )
}
