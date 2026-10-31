// let_join_drop_locals: agora #242 — `: w ? c l m` over two `% Drop` locals, used where it is bound: the value was released through the binding and again through its owner (let_join_drop_locals).
// Closed: the selected owner moves into the binding on its path (§2.2; agora #242).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.2 | A2 | runs-clean | - | agora #242: a `?` over two `% Drop` locals bound by an inferred `:`: released through both names
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ main → i {
    : D l @ D { ( string_from `local string long enough for a heap buffer` ) }
    : D m @ D { ( string_from `other string long enough for a heap buffer` ) }
    : b c T
    : w ? c l m
    ( nurl_println_int ( string_len . w s ) )
    ^ 0
}
