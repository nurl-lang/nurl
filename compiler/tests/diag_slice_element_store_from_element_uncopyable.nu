// An element store whose value is read out of another element stores a
// copy, and a value with a `% Drop` of its own and no clone has none: the
// store is refused. It moved the value as it was, so two slots owned it and
// the slice released it twice.
$ `stdlib/core/string.nu`

: R { String name i n }

% Drop R { @ drop R r → v { ( nurl_println `drop R` ) } }

@ main → i {
    : ~ [R a [R | @ R { ( string_from `a long enough string to be on the heap, one` ) 1 } @ R { ( string_from `a long enough string to be on the heap, two` ) 2 }]
    : i k 0
    : i j 1
    = . a k . a j
    ^ 0
}
