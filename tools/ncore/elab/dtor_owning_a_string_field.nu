// A destructor struct owning a String moved into it: its field a buffer, measured by the destructor.
$ `stdlib/core/string.nu`

: B { String t }

% Drop B { @ drop B self → v { ( nurl_println_int ( string_len . self t ) ) } }

@ main → i {
    : String s ( string_from `a String moved into a holder that measures it when dropped` )
    : B b @ B { s }
    ^ 0
}
