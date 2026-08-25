// nested_field_store.nu — `= . . obj field subfield value`, a store whose
// target is reached through more than one field hop.
//
// Reading a nested path always worked (`. . o inner x`). Writing one did not:
//
//     = . . o inner x 7
//     error: cannot assign to a field of '': it is a by-value NIn with no
//            storage to write through …
//
// The empty name in that message is the tell — the code read the object's
// name from a token that was a `.`, not an identifier. The single-hop path
// takes the object's address from the `<name>__ptr` alloca a `:`-bound struct
// owns; a nested path has no such name, because its object is a field path
// that `gen_expr` evaluates to a by-value register, and a register is not
// somewhere a store can land. So a struct inside a struct was writable only
// by copying the inner one out, mutating it, and writing it back whole.
//
// `gen_nested_lvalue_addr` walks the chain by ADDRESS instead: one GEP per
// navigation field, handing the last container's address to the ordinary
// store dispatch, which does the store, the width coercion and the
// diagnostics exactly as it does for a one-hop store. When a hop is NOT an
// aggregate the field itself is the object — `= . . d op idx v` writes
// through a `*u` field at an index — so that field is loaded and handed over
// as a value, which is how those spellings kept working unchanged.
//
// Pinned below: three levels deep, each level written and read back;
// neighbouring fields left alone; the same width-coercion rule the one-hop
// store follows (a u16 field takes 70000 as 4464); a store through an
// `inout` parameter, which is the one parameter shape allowed to be written
// through. `diag_nested_field_store_param.nu` pins the rejection of a
// by-value parameter.
//
// Expected output:
//   dx=-56 dy=60000 mz=70000 tw=5
//   dx=7 dy=4464 mz=-3 tw=42
//   after inout: dx=9 mz=-3
//   done

$ `stdlib/core/string.nu`

: Deep { i8 dx u16 dy }
: Mid { Deep dm i32 mz }
: Top { Mid tm i64 tw }

@ bump inout Top t → v {
    = . . . t tm dm dx # i8 9
}

@ show Top t → v {
    ( nurl_print `dx=` )
    ( nurl_print ( nurl_str_int # i . . . t tm dm dx ) )
    ( nurl_print ` dy=` )
    ( nurl_print ( nurl_str_int # i . . . t tm dm dy ) )
    ( nurl_print ` mz=` )
    ( nurl_print ( nurl_str_int # i . . t tm mz ) )
    ( nurl_print ` tw=` )
    ( nurl_print ( nurl_str_int . t tw ) )
    ( nurl_print `\n` )
}

@ main → i {
    : ~ Top o @ Top { @ Mid { @ Deep { # i8 200 # u16 60000 } # i32 70000 } 5 }
    ( show o )

    // Three hops, two hops, one hop — each written, all read back.
    = . . . o tm dm dx # i8 7
    = . . . o tm dm dy # u16 70000  // width-coerced like any field store
    = . . o tm mz # i32 -3
    = . o tw 42
    ( show o )

    // …and through an `inout` parameter, whose `__ptr` is the caller's
    // address. Only `dx` changes; `mz` proves the neighbour survived.
    ( bump o )
    ( nurl_print `after inout: dx=` )
    ( nurl_print ( nurl_str_int # i . . . o tm dm dx ) )
    ( nurl_print ` mz=` )
    ( nurl_print ( nurl_str_int # i . . o tm mz ) )
    ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
