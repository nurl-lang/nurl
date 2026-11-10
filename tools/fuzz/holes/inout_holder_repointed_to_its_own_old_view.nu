// inout_holder_repointed_to_its_own_old_view: a helper whose new value for its
// inout holder reads the holder itself (`= w @ W { . w v }`) keeps the old view
// — no answer names it, so a repoint summary that credited it ended the
// caller's borrow of the viewed String and its later read was a
// heap-use-after-free (#386's adversarial pass). The repoint is credited only
// for a value that reads no binding: still refused (agora #386).
// map: §3.3d | A2 | rejected | - | a helper repointing its inout holder to a value made from the holder's own view: not taken as repointed, the caller's borrow stays (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { = w @ W { . w v } ^ 0 }

@ main → i { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) : ~ W w @ W { ( string_data b ) } ( reset w ) ( string_free b ) ( nurl_println . w v ) ^ 0 }
