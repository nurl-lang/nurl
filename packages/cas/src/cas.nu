// packages/cas/src/cas.nu — a content-addressed store over BLAKE3.
//
// The keystone primitive of a verifiable build/distribution chain:
// bytes go in, their BLAKE3-256 hex comes back, and from then on the
// hash IS the name. Storing the same bytes twice is free (dedup by
// existence), and every read re-hashes what it found and refuses to
// return bytes that don't match their name — a store you can rsync,
// cache, or fetch from an untrusted mirror without losing integrity.
//
// Layout (git/OCI-shaped, two-level fan-out):
//   <root>/objects/<hex[0:2]>/<hex[2:64]>     immutable objects
//   <root>/tmp/                               staging for atomic writes
//
// Writes stage into tmp/ and fs_rename into place — readers never see a
// torn object, and concurrent writers of the same content converge on
// the same file. Objects are plain files: no index, no database, no
// lock; the filesystem is the whole data structure.
//
//   ( cas_open `/path/to/store` )       → !Cas String
//   ( cas_put c bytes )                 → !String String   BLAKE3 hex
//   ( cas_put_file c path )             → !String String
//   ( cas_get c hex )                   → !( Vec u ) String  (verified)
//   ( cas_has c hex )                   → b
//   ( cas_object_path c hex )           → String
//   ( cas_hash_hex bytes )              → String   the naming function
//   ( cas_free c )

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/std/time.nu`

: Cas {
    String root
}

@ cas_free Cas c → v { ( string_free . c root ) }

// The naming function: BLAKE3-256, lowercase hex.
@ cas_hash_hex ( Vec u ) data → String {
    ^ ( blake3_hex data )
}

@ __cas_is_hex s hex → b {
    ? != ( nurl_str_len hex ) 64 { ^ F } {}
    : ~ b ok T
    : ~ i k 0
    ~ < k 64 {
        : i ch ( nurl_str_get hex k )
        ? | & >= ch 48 <= ch 57 & >= ch 97 <= ch 102 {} { = ok F }
        = k + k 1
    }
    ^ ok
}

@ cas_open s root → !Cas String {
    : String o ( path_join root `objects` )
    : String t ( path_join root `tmp` )
    : !v IoErr r1 ( dir_create_all ( string_data o ) )
    : !v IoErr r2 ( dir_create_all ( string_data t ) )
    ( string_free o ) ( string_free t )
    : ~ b ok T
    ?? r1 { T _ → {} F _ → { = ok F } }
    ?? r2 { T _ → {} F _ → { = ok F } }
    ? ok { ^ @ !Cas String { T @ Cas { ( string_from root ) } } } {}
    : String msg ( string_from `cas: cannot create store at ` )
    ( string_push_str msg root )
    ^ @ !Cas String { F msg }
}

// <root>/objects/<hex[0:2]>/<hex[2:]>
@ cas_object_path Cas c s hex → String {
    : String p ( string_with_cap + ( string_len . c root ) 80 )
    ( string_push_str p ( string_data . c root ) )
    ( string_push_str p `/objects/` )
    ( string_push_char p ( nurl_str_get hex 0 ) )
    ( string_push_char p ( nurl_str_get hex 1 ) )
    ( string_push_char p 47 )
    : ~ i k 2
    ~ < k ( nurl_str_len hex ) {
        ( string_push_char p ( nurl_str_get hex k ) )
        = k + k 1
    }
    ^ p
}

@ cas_has Cas c s hex → b {
    ? ( __cas_is_hex hex ) {} { ^ F }
    : String p ( cas_object_path c hex )
    : b r ( file_exists ( string_data p ) )
    ( string_free p )
    ^ r
}

// Store bytes; returns their hex name. Existing object = dedup hit (the
// name already proves the content — cas_get verifies on the way out).
// New object: stage under tmp/ with a unique name, then one atomic
// rename into place.
@ cas_put Cas c ( Vec u ) data → !String String {
    : String hex ( cas_hash_hex data )
    ? ( cas_has c ( string_data hex ) ) { ^ @ !String String { T hex } } {}

    : String fan ( string_with_cap 96 )
    ( string_push_str fan ( string_data . c root ) )
    ( string_push_str fan `/objects/` )
    ( string_push_char fan ( string_get hex 0 ) )
    ( string_push_char fan ( string_get hex 1 ) )
    : !v IoErr mk ( dir_create_all ( string_data fan ) )
    ( string_free fan )
    ?? mk { T _ → {} F _ → {
            ( string_free hex )
            ^ @ !String String { F ( string_from `cas: cannot create object directory` ) }
        } }

    // unique staging name: <hex>.<monotonic>.tmp
    : String tp ( string_with_cap 128 )
    ( string_push_str tp ( string_data . c root ) )
    ( string_push_str tp `/tmp/` )
    ( string_push_str tp ( string_data hex ) )
    ( string_push_char tp 46 )
    ( string_push_int tp ( monotonic_ns ) )
    ( string_push_str tp `.tmp` )
    : !v IoErr wr ( write_file_bytes ( string_data tp ) data )
    ?? wr { T _ → {} F _ → {
            ( string_free tp ) ( string_free hex )
            ^ @ !String String { F ( string_from `cas: staging write failed (is the store writable?)` ) }
        } }

    : String dst ( cas_object_path c ( string_data hex ) )
    : !v IoErr mv ( fs_rename ( string_data tp ) ( string_data dst ) )
    ?? mv {
        T _ → {}
        F _ → {
            // A concurrent writer may have won the rename race with the
            // identical content — that is still success. Anything else
            // is a real error.
            ? ( file_exists ( string_data dst ) ) { ( file_delete ( string_data tp ) ) } {
                ( file_delete ( string_data tp ) )
                ( string_free tp ) ( string_free dst ) ( string_free hex )
                ^ @ !String String { F ( string_from `cas: object rename failed` ) }
            }
        }
    }
    ( string_free tp ) ( string_free dst )
    ^ @ !String String { T hex }
}

@ cas_put_file Cas c s path → !String String {
    : !( Vec u ) IoErr r ( read_file_bytes path )
    ?? r {
        T data → {
            : !String String pr ( cas_put c data )
            ( vec_free [u] data )
            ^ pr
        }
        F _ → {
            : String msg ( string_from `cas: cannot read ` )
            ( string_push_str msg path )
            ^ @ !String String { F msg }
        }
    }
}

// Fetch by name — and PROVE the name. The stored bytes are re-hashed and
// compared to the requested hex; a corrupted or tampered object is an
// error, never silently returned. This is the verifiability loop: any
// store you can point cas_get at (local disk, a synced mirror, a cache
// you don't trust) yields either the exact original bytes or a failure.
@ cas_get Cas c s hex → !( Vec u ) String {
    ? ( __cas_is_hex hex ) {} {
        ^ @ !( Vec u ) String { F ( string_from `cas: not a BLAKE3 hex name (64 lowercase hex chars)` ) }
    }
    : String p ( cas_object_path c hex )
    : !( Vec u ) IoErr r ( read_file_bytes ( string_data p ) )
    ( string_free p )
    ?? r {
        T data → {
            : String got ( cas_hash_hex data )
            : b match ( nurl_str_eq ( string_data got ) hex )
            ( string_free got )
            ? match { ^ @ !( Vec u ) String { T data } } {}
            ( vec_free [u] data )
            : String msg ( string_from `cas: INTEGRITY FAILURE — object ` )
            ( string_push_str msg hex )
            ( string_push_str msg ` does not hash to its name (corrupted or tampered)` )
            ^ @ !( Vec u ) String { F msg }
        }
        F _ → {
            : String msg ( string_from `cas: no such object ` )
            ( string_push_str msg hex )
            ^ @ !( Vec u ) String { F msg }
        }
    }
}
