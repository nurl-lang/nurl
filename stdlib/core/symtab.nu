// stdlib/core/symtab.nu — string→string symbol table (insertion-ordered,
// hash-indexed map).
//
//   ( nurl_sym_new )          → i      fresh empty table handle
//   ( nurl_sym_def h k v )    → v      bind key k to value v; a key that
//                                       is already bound has its value
//                                       replaced in place
//   ( nurl_sym_get h k )      → s      value bound to k, or `` if absent
//                                       (always an owned copy)
//   ( nurl_sym_free h )       → v      release the table and every key
//                                       and value it holds
//
// The handle is a `nurl_zalloc`'d 72-byte (9-slot) header:
//   slot 0: count   slot 1: (unused)
//   slot 2: cap     slot 3: names[]  slot 4: types[]  slot 5: lens[]
//   slot 6: nbuckets  slot 7: buckets[] (head index+1; 0 = empty)
//   slot 8: prev[]    (per-entry link to the previous entry in its bucket)
//
// Lookup is O(1) amortised (FNV-1a bucket chain) rather than a backward
// linear scan, and the bucket array grows with the table, so building a
// large table stays linear overall. This is the same table nurlc uses
// internally; it was lifted out of the compiler so other NURL programs
// (e.g. the language server) can reuse it. Keys and values are copied in;
// the table owns its copies until nurl_sym_free.
//
// A re-definition replaces the value rather than pushing a second entry:
// nothing here can read an older binding, so a pushed entry was only a
// copy nothing would ever free — a long-running process that re-defines
// the same keys (the language server re-indexes a document on every
// edit) grew without bound.

// FNV-1a (32-bit) over the first n bytes of the key. Uses raw byte reads
// so this core module stays import-free.
@ __sym_hash_n s name i n → i {
    : *u p # *u name
    : ~ i hsh 2166136261
    : ~ i k 0
    ~ < k n {
        = hsh & ^^ hsh # i . p k 4294967295
        = hsh & * hsh 16777619 4294967295
        = k + k 1
    }
    ^ hsh
}

@ nurl_sym_new → i {
    : i nb 4096
    : s t # s ( nurl_zalloc 72 )
    ( nurl_poke t 2 64 )
    ( nurl_poke t 3 # i # s ( nurl_alloc * 64 8 ) )
    ( nurl_poke t 4 # i # s ( nurl_alloc * 64 8 ) )
    ( nurl_poke t 5 # i # s ( nurl_alloc * 64 8 ) )
    ( nurl_poke t 6 nb )
    ( nurl_poke t 7 # i # s ( nurl_zalloc * nb 8 ) )
    ( nurl_poke t 8 # i # s ( nurl_alloc * 64 8 ) )
    ^ # i t
}

// Release the table: every key and value copy, the parallel arrays, the
// buckets and the header. 0 is accepted and ignored.
@ nurl_sym_free i h → v {
    ? == h 0 { ^ } {}
    : s t # s h
    : i count ( nurl_peek t 0 )
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : ~ i k 0
    ~ < k count {
        ( nurl_free . names k )
        ( nurl_free . types k )
        = k + k 1
    }
    ( nurl_free # s ( nurl_peek t 3 ) )
    ( nurl_free # s ( nurl_peek t 4 ) )
    ( nurl_free # s ( nurl_peek t 5 ) )
    ( nurl_free # s ( nurl_peek t 7 ) )
    ( nurl_free # s ( nurl_peek t 8 ) )
    ( nurl_free t )
}

@ __sym_grow i h → v {
    : s t # s h
    : i cap ( nurl_peek t 2 )
    : i newcap * cap 2
    : i count ( nurl_peek t 0 )
    : s names_old # s ( nurl_peek t 3 )
    : s types_old # s ( nurl_peek t 4 )
    : s lens_old # s ( nurl_peek t 5 )
    : s prev_old # s ( nurl_peek t 8 )
    : s names_new # s ( nurl_alloc * newcap 8 )
    : s types_new # s ( nurl_alloc * newcap 8 )
    : s lens_new # s ( nurl_alloc * newcap 8 )
    : s prev_new # s ( nurl_alloc * newcap 8 )
    : i nbytes * count 8
    ( memcpy names_new names_old nbytes )
    ( memcpy types_new types_old nbytes )
    ( memcpy lens_new lens_old nbytes )
    ( memcpy prev_new prev_old nbytes )
    ( nurl_free names_old )
    ( nurl_free types_old )
    ( nurl_free lens_old )
    ( nurl_free prev_old )
    ( nurl_poke t 2 newcap )
    ( nurl_poke t 3 # i names_new )
    ( nurl_poke t 4 # i types_new )
    ( nurl_poke t 5 # i lens_new )
    ( nurl_poke t 8 # i prev_new )
}

// Four times the buckets once there are twice as many entries as buckets,
// every entry relinked in insertion order. Keys are distinct, so chain
// order does not matter for lookups.
@ __sym_rehash i h → v {
    : s t # s h
    : i count ( nurl_peek t 0 )
    : i nb * ( nurl_peek t 6 ) 4
    : *s names # *s # s ( nurl_peek t 3 )
    : *i prev # *i # s ( nurl_peek t 8 )
    ( nurl_free # s ( nurl_peek t 7 ) )
    : *i buckets # *i # s ( nurl_zalloc * nb 8 )
    ( nurl_poke t 7 # i # s buckets )
    ( nurl_poke t 6 nb )
    : ~ i k 0
    ~ < k count {
        : s nm . names k
        : i bh % ( __sym_hash_n nm ( strlen nm ) ) nb
        = . prev k . buckets bh
        = . buckets bh + k 1
        = k + k 1
    }
}

// Index of `name`'s entry, or -1.
@ __sym_find i h s name i nl → i {
    : s t # s h
    : *s names # *s # s ( nurl_peek t 3 )
    : *i buckets # *i # s ( nurl_peek t 7 )
    : *i prev # *i # s ( nurl_peek t 8 )
    : i bh % ( __sym_hash_n name nl ) ( nurl_peek t 6 )
    : ~ i cur . buckets bh
    ~ != cur 0 {
        : i idx - cur 1
        ? == 0 # i ( strcmp name . names idx ) { ^ idx } {}
        = cur . prev idx
    }
    -1
}

@ nurl_sym_def i h s name s type → v {
    : s t # s h
    : i nl ( strlen name )
    : i tl ( strlen type )
    : i found ( __sym_find h name nl )
    ? >= found 0 {
        : *s vals # *s # s ( nurl_peek t 4 )
        : *i vlens # *i # s ( nurl_peek t 5 )
        // Copy before releasing: `type` may be a value read back out of
        // this very entry.
        : s copy # s ( nurl_strdup_n type tl )
        ( nurl_free . vals found )
        = . vals found copy
        = . vlens found tl
        ^
    } {}
    : i count ( nurl_peek t 0 )
    : i cap ( nurl_peek t 2 )
    ? >= count cap { ( __sym_grow h ) } {}
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : *i lens # *i # s ( nurl_peek t 5 )
    : *i buckets # *i # s ( nurl_peek t 7 )
    : *i prev # *i # s ( nurl_peek t 8 )
    : i bh % ( __sym_hash_n name nl ) ( nurl_peek t 6 )
    = . names count # s ( nurl_strdup_n name nl )
    = . types count # s ( nurl_strdup_n type tl )
    = . lens count tl
    = . prev count . buckets bh
    = . buckets bh + count 1
    ( nurl_poke t 0 + count 1 )
    ? > + count 1 * 2 ( nurl_peek t 6 ) { ( __sym_rehash h ) } {}
}

@ nurl_sym_get i h s name → s {
    : s t # s h
    : i idx ( __sym_find h name ( strlen name ) )
    ? < idx 0 { ^ # s ( nurl_strdup `` ) } {}
    : *s types # *s # s ( nurl_peek t 4 )
    : *i lens # *i # s ( nurl_peek t 5 )
    ^ # s ( nurl_strdup_n . types idx . lens idx )
}
