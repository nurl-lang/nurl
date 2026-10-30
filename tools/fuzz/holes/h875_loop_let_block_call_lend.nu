// H875: agora #193 — `: String r { : W w ( mkw ) ( gets w ) }` then `= out r` in a loop: the block's local dies with the loop body, `out` outlives it (loop_let_block_call_lend).
// Closed: A `:` binding of a value block whose tail call lends a binding made while the block ran — its own locals, which live only to the end of the enclosing scope — copies the value in place, and the binding owns it (gen_let_or_struct: mem_blk_tail_deeper_args from the first register the right-hand side took, then mem_blk_tail_copy_slot; agora #193). The walk takes the value for what those locals held (h216); this makes it so. One that cannot be copied is refused.
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : ~ String out ( string_from `start` )
    : ~ i k 0
    ~ < k 3 {
        : String r {
            : W w ( mkw )
            ( gets w )
        }
        = out r
        = k + k 1
    }
    ( nurl_println_int ( string_len out ) )
    ^ 0
}
