// packages/cas/src/manifest.nu — the minimal manifest: a named set of
// files as (hash, size, path) triples, serialised CANONICALLY so that
// the same tree always produces the same bytes — and therefore the same
// BLAKE3 name when the manifest is stored in the CAS. That makes a
// manifest hash a Merkle root: one 64-hex string names an entire tree,
// dedups against every other tree sharing files, and verifies all the
// way down.
//
// Wire format (text, one object kind, self-identifying):
//   cas-manifest v1\n
//   <64-hex> <size> <path>\n        entries sorted bytewise by path
//
// Paths are relative, '/'-separated, no leading './'. The format is the
// canonical encoding — decode(encode(m)) round-trips and encode(decode(b))
// == b for any valid manifest, so hashes are stable across
// implementations.
//
//   ( manifest_new )                          → CasManifest
//   ( manifest_add m hex size path )          → v
//   ( manifest_encode m )                     → ( Vec u )   canonical bytes
//   ( manifest_decode bytes )                 → !CasManifest String
//   ( manifest_len m ) / ( manifest_hash m i ) / ( manifest_size m i ) /
//   ( manifest_path m i )                     → accessors (borrowed views)
//   ( manifest_free m )
//
// Store-level operations built on it (import src/cas.nu first):
//   ( cas_snapshot c dir )                    → !String String   manifest hex
//   ( cas_checkout c manifest_hex dest )      → !i String        files written
//   ( cas_verify c hex )                      → !i String        objects proven

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `cas.nu`

: CasManifest {
    ( Vec String ) hashes
    ( Vec i ) sizes
    ( Vec String ) paths
}

@ manifest_new → CasManifest {
    ^ @ CasManifest { ( vec_new [String] ) ( vec_new [i] ) ( vec_new [String] ) }
}

@ manifest_free CasManifest m → v {
    ( vec_free_with [String] . m hashes \ String s → v { ( string_free s ) } )
    ( vec_free [i] . m sizes )
    ( vec_free_with [String] . m paths \ String s → v { ( string_free s ) } )
}

@ manifest_len CasManifest m → i { ^ ( vec_len [String] . m paths ) }

// Accessors return OWNED copies (vec_get on Vec String hands back an
// aliasing copy the compiler tracks — copying keeps call sites simple).
@ manifest_hash CasManifest m i k → String {
    ^ ?? ( vec_get [String] . m hashes k ) { T s → ( string_from ( string_data s ) ) F → ( string_new ) }
}

@ manifest_size CasManifest m i k → i {
    ^ ?? ( vec_get [i] . m sizes k ) { T v → v F → 0 }
}

@ manifest_path CasManifest m i k → String {
    ^ ?? ( vec_get [String] . m paths k ) { T s → ( string_from ( string_data s ) ) F → ( string_new ) }
}

@ manifest_add CasManifest m s hex i size s path → v {
    ( vec_push [String] . m hashes ( string_from hex ) )
    ( vec_push [i] . m sizes size )
    ( vec_push [String] . m paths ( string_from path ) )
}

@ __mf_header → s { ^ `cas-manifest v1` }

// Canonical bytes: header + entries sorted bytewise by path. Sorting
// happens on an index permutation so the manifest itself is untouched.
@ manifest_encode CasManifest m → ( Vec u ) {
    : i n ( manifest_len m )
    // Build "path\x00index" keys, sort them, read the order back out.
    : ( Vec String ) keys ( vec_new [String] )
    : ~ i k 0
    ~ < k n {
        : String key ( manifest_path m k )
        ( string_push_char key 1 )  // \x01 < any path byte we accept
        ( string_push_int key k )
        ( vec_push [String] keys key )
        = k + k 1
    }
    ( sort_by [String] keys \ String a String b → i { ^ ( string_cmp_bytes a b ) } )

    : ( Vec u ) out ( vec_new [u] )
    ( bytes_extend_str out ( __mf_header ) )
    ( vec_push [u] out # u 10 )
    : ~ i j 0
    ~ < j n {
        : ?String ko ( vec_get [String] keys j )
        ?? ko {
            T key → {
                // recover the original index after the \x01 separator
                : ~ i sep 0
                : ~ i q 0
                ~ < q ( string_len key ) {
                    ? == ( string_get key q ) 1 { = sep q = q ( string_len key ) } { = q + q 1 }
                }
                : ~ i idx 0
                : ~ i d + sep 1
                ~ < d ( string_len key ) {
                    = idx + * idx 10 - ( string_get key d ) 48
                    = d + d 1
                }
                : String h ( manifest_hash m idx )
                : String p ( manifest_path m idx )
                ( bytes_extend_str out ( string_data h ) )
                ( vec_push [u] out # u 32 )
                : String sz ( string_with_cap 24 )
                ( string_push_int sz ( manifest_size m idx ) )
                ( bytes_extend_str out ( string_data sz ) )
                ( string_free sz )
                ( vec_push [u] out # u 32 )
                ( bytes_extend_str out ( string_data p ) )
                ( vec_push [u] out # u 10 )
                ( string_free h ) ( string_free p )
            }
            F → {}
        }
        = j + j 1
    }
    ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
    ^ out
}

// Bytewise string compare for the canonical sort (string_cmp in the
// stdlib is locale-free already, but be explicit and self-contained).
@ string_cmp_bytes String a String b → i {
    : i na ( string_len a )
    : i nb ( string_len b )
    : i lim ? < na nb na nb
    : ~ i k 0
    ~ < k lim {
        : i ca ( string_get a k )
        : i cb ( string_get b k )
        ? != ca cb { ^ ? < ca cb - 0 1 1 } {}
        = k + k 1
    }
    ? == na nb { ^ 0 } {}
    ^ ? < na nb - 0 1 1
}

// True iff the bytes carry the manifest header (cheap kind probe).
@ manifest_is ( Vec u ) data → b {
    : s h ( __mf_header )
    : i hn ( nurl_str_len h )
    ? < ( vec_len [u] data ) + hn 1 { ^ F } {}
    : ~ b ok T
    : ~ i k 0
    ~ < k hn {
        : i c ?? ( vec_get [u] data k ) { T x → # i x F _ → 0 }
        ? != c ( nurl_str_get h k ) { = ok F } {}
        = k + k 1
    }
    : i nl ?? ( vec_get [u] data hn ) { T x → # i x F _ → 0 }
    ^ & ok == nl 10
}

@ manifest_decode ( Vec u ) data → !CasManifest String {
    ? ( manifest_is data ) {} {
        ^ @ !CasManifest String { F ( string_from `cas: not a manifest (missing "cas-manifest v1" header)` ) }
    }
    : CasManifest m ( manifest_new )
    : i n ( vec_len [u] data )
    : ~ i pos + ( nurl_str_len ( __mf_header ) ) 1
    : ~ b bad F
    ~ & < pos n ! bad {
        // <64 hex> ' ' <digits> ' ' <path> '\n'
        ? > + pos 66 n { = bad T } {
            : String hex ( string_with_cap 65 )
            : ~ i k 0
            ~ < k 64 {
                ( string_push_char hex ?? ( vec_get [u] data + pos k ) { T x → # i x F _ → 0 } )
                = k + k 1
            }
            = pos + pos 64
            ? != ?? ( vec_get [u] data pos ) { T x → # i x F _ → 0 } 32 { = bad T ( string_free hex ) } {
                = pos + pos 1
                : ~ i size 0
                : ~ b any F
                ~ & < pos n & >= ?? ( vec_get [u] data pos ) { T x → # i x F _ → 0 } 48 <= ?? ( vec_get [u] data pos ) { T x → # i x F _ → 0 } 57 {
                    = size + * size 10 - ?? ( vec_get [u] data pos ) { T x → # i x F _ → 0 } 48
                    = any T
                    = pos + pos 1
                }
                ? | ! any != ?? ( vec_get [u] data pos ) { T x → # i x F _ → 0 } 32 { = bad T ( string_free hex ) } {
                    = pos + pos 1
                    : String p ( string_with_cap 64 )
                    : ~ b nl F
                    ~ & < pos n ! nl {
                        : i c ?? ( vec_get [u] data pos ) { T x → # i x F _ → 0 }
                        ? == c 10 { = nl T } { ( string_push_char p c ) }
                        = pos + pos 1
                    }
                    ? & nl > ( string_len p ) 0 {
                        ( manifest_add m ( string_data hex ) size ( string_data p ) )
                    } { = bad T }
                    ( string_free p ) ( string_free hex )
                }
            }
        }
    }
    ? bad {
        ( manifest_free m )
        ^ @ !CasManifest String { F ( string_from `cas: malformed manifest entry` ) }
    } {}
    ^ @ !CasManifest String { T m }
}

// ── store-level operations ───────────────────────────────────────────

// Recursively walk `dir`, cas_put every regular file, then cas_put the
// canonical manifest of the tree. Returns the manifest's hex — one name
// for the whole snapshot.
@ cas_snapshot Cas c s dir → !String String {
    : CasManifest m ( manifest_new )
    : String prefix ( string_new )
    : !v String wr ( __cas_walk c dir ( string_data prefix ) m )
    ( string_free prefix )
    ?? wr { T _ → {} F e → { ( manifest_free m ) ^ @ !String String { F e } } }
    : ( Vec u ) enc ( manifest_encode m )
    ( manifest_free m )
    : !String String pr ( cas_put c enc )
    ( vec_free [u] enc )
    ^ pr
}

@ __cas_walk Cas c s dir s rel CasManifest m → !v String {
    : !( Vec String ) IoErr lr ( dir_list dir )
    ?? lr {
        T names → {
            : ~ i k 0
            : ~ b failed F
            : ~ String errmsg ( string_new )
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T name → {
                        ? failed {} {
                            : String full ( path_join dir ( string_data name ) )
                            : ~ String sub ( string_from rel )
                            ? > ( string_len sub ) 0 { ( string_push_char sub 47 ) } {}
                            ( string_push_str sub ( string_data name ) )
                            // directory probe: dir_list succeeds only on dirs
                            : !( Vec String ) IoErr dp ( dir_list ( string_data full ) )
                            ?? dp {
                                T inner → {
                                    ( vec_free_with [String] inner \ String s → v { ( string_free s ) } )
                                    : !v String rr ( __cas_walk c ( string_data full ) ( string_data sub ) m )
                                    ?? rr { T _ → {} F e → { = failed T ( string_free errmsg ) = errmsg e } }
                                }
                                F _ → {
                                    : !( Vec u ) IoErr fr ( read_file_bytes ( string_data full ) )
                                    ?? fr {
                                        T bytes → {
                                            : i sz ( vec_len [u] bytes )
                                            : !String String pr ( cas_put c bytes )
                                            ( vec_free [u] bytes )
                                            ?? pr {
                                                T hex → {
                                                    ( manifest_add m ( string_data hex ) sz ( string_data sub ) )
                                                    ( string_free hex )
                                                }
                                                F e → { = failed T ( string_free errmsg ) = errmsg e }
                                            }
                                        }
                                        F _ → {
                                            = failed T
                                            ( string_free errmsg )
                                            = errmsg ( string_from `cas: cannot read ` )
                                            ( string_push_str errmsg ( string_data full ) )
                                        }
                                    }
                                }
                            }
                            ( string_free full ) ( string_free sub )
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
            ? failed { ^ @ !v String { F errmsg } } {}
            ( string_free errmsg )
            ^ @ !v String { T }
        }
        F _ → {
            : String msg ( string_from `cas: cannot list directory ` )
            ( string_push_str msg dir )
            ^ @ !v String { F msg }
        }
    }
}

// Materialise a snapshot into `dest`. Every object read is verified by
// cas_get; a checkout therefore cannot produce bytes that differ from
// what was snapshotted. Returns the number of files written.
@ cas_checkout Cas c s manifest_hex s dest → !i String {
    : !( Vec u ) String mr ( cas_get c manifest_hex )
    : ~ ( Vec u ) mb ( vec_new [u] )
    ?? mr { T v → { ( vec_free [u] mb ) = mb v } F e → { ^ @ !i String { F e } } }
    : !CasManifest String dr ( manifest_decode mb )
    ( vec_free [u] mb )
    ?? dr {
        T m → {
            : ~ i written 0
            : ~ i k 0
            : ~ b failed F
            : ~ String errmsg ( string_new )
            : i n ( manifest_len m )
            ~ & < k n ! failed {
                : String hex ( manifest_hash m k )
                : String p ( manifest_path m k )
                // reject absolute / parent-escaping paths on the way OUT
                ? | ( string_starts_with p `/` ) | ( string_contains p `../` ) ( string_starts_with p `..` )
                { = failed T ( string_free errmsg ) = errmsg ( string_from `cas: manifest path escapes the checkout root` ) }
                {
                    : !( Vec u ) String gr ( cas_get c ( string_data hex ) )
                    ?? gr {
                        T bytes → {
                            : String full ( path_join dest ( string_data p ) )
                            : String parent ( path_dirname ( string_data full ) )
                            ( dir_create_all ( string_data parent ) )
                            ( string_free parent )
                            : !v IoErr wr ( write_file_bytes ( string_data full ) bytes )
                            ( vec_free [u] bytes )
                            ?? wr {
                                T _ → { = written + written 1 }
                                F _ → {
                                    = failed T
                                    ( string_free errmsg )
                                    = errmsg ( string_from `cas: cannot write ` )
                                    ( string_push_str errmsg ( string_data full ) )
                                }
                            }
                            ( string_free full )
                        }
                        F e → { = failed T ( string_free errmsg ) = errmsg e }
                    }
                }
                ( string_free hex ) ( string_free p )
                = k + k 1
            }
            ( manifest_free m )
            ? failed { ^ @ !i String { F errmsg } } {}
            ( string_free errmsg )
            ^ @ !i String { T written }
        }
        F e → { ^ @ !i String { F e } }
    }
}

// Deep-verify a name: a blob proves itself (cas_get re-hashes); a
// manifest additionally proves every entry it references. Returns the
// total number of objects proven (manifest itself included).
@ cas_verify Cas c s hex → !i String {
    : !( Vec u ) String r ( cas_get c hex )
    : ~ ( Vec u ) data ( vec_new [u] )
    ?? r { T v → { ( vec_free [u] data ) = data v } F e → { ^ @ !i String { F e } } }
    ? ( manifest_is data ) {} {
        ( vec_free [u] data )
        ^ @ !i String { T 1 }
    }
    : !CasManifest String dr ( manifest_decode data )
    ( vec_free [u] data )
    ?? dr {
        T m → {
            : ~ i proven 1
            : ~ i k 0
            : ~ b failed F
            : ~ String errmsg ( string_new )
            : i n ( manifest_len m )
            ~ & < k n ! failed {
                : String h ( manifest_hash m k )
                : !( Vec u ) String gr ( cas_get c ( string_data h ) )
                ?? gr {
                    T bytes → {
                        : i sz ( manifest_size m k )
                        ? == ( vec_len [u] bytes ) sz { = proven + proven 1 } {
                            = failed T
                            ( string_free errmsg )
                            = errmsg ( string_from `cas: size mismatch for ` )
                            ( string_push_str errmsg ( string_data h ) )
                        }
                        ( vec_free [u] bytes )
                    }
                    F e → { = failed T ( string_free errmsg ) = errmsg e }
                }
                ( string_free h )
                = k + k 1
            }
            ( manifest_free m )
            ? failed { ^ @ !i String { F errmsg } } {}
            ( string_free errmsg )
            ^ @ !i String { T proven }
        }
        F e → { ^ @ !i String { F e } }
    }
}
