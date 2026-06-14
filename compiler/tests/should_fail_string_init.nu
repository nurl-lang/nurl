// should_fail_string_init.nu — a String binding must not be initialised
// from a raw string literal / i8*. A String owns a heap control block +
// buffer; storing a borrowed i8* into the %String slot used to emit IR
// that only clang rejected ("ptr but expected %String"). nurlc now
// diagnoses it up front and points at ( string_from … ).

$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ``
    = s ( string_from `hi` )
    ( nurl_print ( string_data s ) )
    ^ 0
}
