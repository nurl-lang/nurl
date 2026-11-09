// payload_of_a_loop_element_read_after_its_container_is_cleared_through_a_cursor: agora #482 — `~ o t` (`t` a Vec of `?String`); `?? o` in place; `t` cleared through `cur`, a cursor over `t`; the payload `y` read after
// Closed: a `??` payload read in place out of a loop element borrows it, as one out of a `vec_at` binding does, so it ends with the container's owners (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a payload of a loop element read after its container is cleared through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ? String ) t ( vec_new [? String] )
    ( vec_push [? String] t @ ?String { T ( string_from `a payload long enough for a heap buffer here` ) } )
    : ~ ( Vec ? String ) cur t
    ~ o t {
        ?? o {
            T y → {
                ( vec_clear [? String] cur )
                ( nurl_println ( string_data y ) )
            }
            F → {}
        }
        break
    }
    ^ 0
}
