// stdlib/core/symtab.nu — string→string symbol table (insertion-ordered
// linear-scan map).
//
//   ( nurl_sym_new )          → i      fresh empty table handle
//   ( nurl_sym_def h k v )    → v      bind key k to value v (last wins
//                                       on lookup; earlier bindings are
//                                       shadowed, not overwritten)
//   ( nurl_sym_get h k )      → s      newest value bound to k, or `` if
//                                       absent (always an owned strdup)
//
// The handle is a `nurl_zalloc`'d 48-byte (6-slot) header:
//   slot 0: count   slot 1: depth (scope cursor; unused by def/get)
//   slot 2: cap     slot 3: names[]  slot 4: types[]  slot 5: depths[]
//
// This is the same table nurlc uses internally; it was lifted out of the
// compiler so other NURL programs (e.g. the language server) can reuse
// it. Keys/values are `strdup`'d on insert; the table never frees them
// (grow-only), matching the compiler's lifetime contract.

@ nurl_sym_new → i {
    : s t # s ( nurl_zalloc 48 )
    ( nurl_poke t 2 64 )
    ( nurl_poke t 3 # i # s ( malloc * 64 8 ) )
    ( nurl_poke t 4 # i # s ( malloc * 64 8 ) )
    ( nurl_poke t 5 # i # s ( malloc * 64 8 ) )
    ^ # i t
}

@ __sym_grow i h → v {
    : s t # s h
    : i cap ( nurl_peek t 2 )
    : i newcap * cap 2
    : i count ( nurl_peek t 0 )
    : s names_old # s ( nurl_peek t 3 )
    : s types_old # s ( nurl_peek t 4 )
    : s depths_old # s ( nurl_peek t 5 )
    : s names_new # s ( malloc * newcap 8 )
    : s types_new # s ( malloc * newcap 8 )
    : s depths_new # s ( malloc * newcap 8 )
    : i nbytes * count 8
    ( memcpy names_new names_old nbytes )
    ( memcpy types_new types_old nbytes )
    ( memcpy depths_new depths_old nbytes )
    ( free names_old )
    ( free types_old )
    ( free depths_old )
    ( nurl_poke t 2 newcap )
    ( nurl_poke t 3 # i names_new )
    ( nurl_poke t 4 # i types_new )
    ( nurl_poke t 5 # i depths_new )
}

@ nurl_sym_def i h s name s type → v {
    : s t # s h
    : i count ( nurl_peek t 0 )
    : i cap ( nurl_peek t 2 )
    ? >= count cap { ( __sym_grow h ) } {}
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : *i depths # *i # s ( nurl_peek t 5 )
    = . names count # s ( strdup name )
    = . types count # s ( strdup type )
    = . depths count ( nurl_peek t 1 )
    ( nurl_poke t 0 + count 1 )
}

@ nurl_sym_get i h s name → s {
    : s t # s h
    : i count ( nurl_peek t 0 )
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : ~ i k - count 1
    ~ >= k 0 {
        ? == 0 # i ( strcmp name . names k )
        { ^ # s ( strdup . types k ) }
        {}
        = k - k 1
    }
    ^ # s ( strdup `` )
}
