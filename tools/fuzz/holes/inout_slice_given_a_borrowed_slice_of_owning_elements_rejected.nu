// inout_slice_given_a_borrowed_slice_of_owning_elements_rejected: `@ setq inout [String p [String q → v { = p q }`: a slice of Strings the parameter does not own cannot be copied element by element here, so it is refused
// main: the caller's slot shared q's Strings with their owner (heap-use-after-free).
// map: §2.4 | A2 | rejected | - | agora #545: an inout slice of elements that own values given a slice it does not own is refused
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ setq inout [String p [String q → v { = p q }

@ main → i {
    : ~ [String d [String | ( string_from `old element long enough for a heap buffer` )]
    : [String q [String | ( string_from `q element long enough for a heap buffer` )]
    ( setq d q )
    ^ 0
}
