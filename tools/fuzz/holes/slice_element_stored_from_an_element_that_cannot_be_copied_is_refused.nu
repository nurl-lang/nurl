// slice_element_stored_from_an_element_that_cannot_be_copied_is_refused: agora #545 — an element store whose value is read out of another element, the element a `% Drop` value with no clone: the store moved the value as it was, two slots owned it and the slice ran its destructor twice.
// Closed: the store needs a copy and the value has none: refused where the value is read, naming the type.
// main (before this PR): accepted; AddressSanitizer, heap-use-after-free (the destructor runs twice on one value).
// map: §7.6 | A2 | rejected | - | agora #545: an element store from another element of a `% Drop` type ran the destructor twice on one value
$ `stdlib/core/string.nu`

: R { String name }
% Drop R { @ drop R r → v { ( nurl_println `drop R` ) } }

@ main → i {
    : ~ [R rs [R | @ R { ( string_from `a long enough string to be on the heap, one` ) } @ R { ( string_from `a long enough string to be on the heap, two` ) }]
    : i z 0 : i o 1
    = . rs z . rs o
    ^ 0
}
