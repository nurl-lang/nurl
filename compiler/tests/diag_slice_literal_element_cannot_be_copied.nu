// diag_slice_literal_element_cannot_be_copied.nu — a slice literal owns its
// elements (Agora #485): a fresh one moves in, any other is copied in. A
// binding of a type with a `% Drop` of its own cannot be copied, so naming
// it in a slice literal is refused; the element is built in place instead.
: D { i n }

% Drop D { @ drop D d → v { ( nurl_println ( nurl_str_int . d n ) ) } }

@ main → i {
    : D d @ D { 7 }
    : [D sl [D | d]
    ^ 0
}
