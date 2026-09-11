// diag_block_binding_escape.nu — a block-expression initialiser is the
// one place where a `:` binding can name something declared deeper than
// itself: the block's own frame. A closure that captures a `: ~`
// multi-field struct holds a pointer into that frame (docs/MEMORY.md
// §2.3), so binding it OUTSIDE the block dangles exactly as assigning it
// there does — and `=` has always rejected that. The `:` path recorded
// the referent depth without comparing it, so this compiled clean and
// the closure ran against a dead frame.

: Counter { i n i max }

@ main → i {
    : ( @ v ) f {
        : ~ Counter c @ Counter { 0 10 }
        \ → v { = . c n + . c n 1 }
    }
    ( f )
    ^ 0
}
