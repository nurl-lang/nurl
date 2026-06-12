// fs_glob.nu — std/fs.nu B6 (rename/copy/tempfile) + B7 (glob).
//
// Builds a known tree under a unique temp dir, then exercises rename,
// copy, tempfile, and glob patterns (* ? [...] ** , literal, dotfile
// rule). Output is normalized to be path-stable: the temp root prefix
// is stripped so the golden is deterministic. Cleans up at the end.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`

// strip a leading `root/` prefix from `p` for stable output
@ rel s root s p → String {
    : i rn ( nurl_str_len root )
    : i pn ( nurl_str_len p )
    ? & > pn rn ( __starts_with p root ) {
        : ~ i st rn
        ? & < st pn == ( nurl_str_get p st ) 47 { = st + st 1 } {}
        : String out ( string_with_cap + - pn st 1 )
        : ~ i k st
        ~ < k pn { ( string_push_char out ( nurl_str_get p k ) ) = k + k 1 }
        ^ out
    } {}
    ^ ( string_from p )
}

@ __starts_with s p s pre → b {
    : i n ( nurl_str_len pre )
    ? > n ( nurl_str_len p ) { ^ F } {}
    : ~ i k 0
    ~ < k n { ? != ( nurl_str_get p k ) ( nurl_str_get pre k ) { ^ F } {} = k + k 1 }
    ^ T
}

@ show_glob s label s root s pat → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : !( Vec String ) IoErr gr ( fs_glob pat )
    ?? gr {
        T matches → {
            : i n ( vec_len [String] matches )
            // collect relative strings, sort for determinism
            : ( Vec String ) rels ( vec_new [String] )
            : ~ i k 0
            ~ < k n {
                : ?String mo ( vec_get [String] matches k )
                ?? mo { T m → ( vec_push [String] rels ( rel root ( string_data m ) ) ) F _ → {} }
                = k + k 1
            }
            : ( @ i String String ) cmp \ String a String b → i { ^ ( cmp_string a b ) }
            ( sort_by [String] rels cmp )
            : ~ i j 0
            ~ < j ( vec_len [String] rels ) {
                : ?String ro ( vec_get [String] rels j )
                ?? ro { T r → { ( nurl_print ( string_data r ) ) ( nurl_print ` ` ) } F _ → {} }
                = j + j 1
            }
            : i rn ( vec_len [String] rels )
            : ~ i fk 0
            ~ < fk rn { : ?String ro2 ( vec_get [String] rels fk ) ?? ro2 { T r → ( string_free r ) F _ → {} } = fk + fk 1 }
            ( vec_free [String] rels )
            : ~ i mk 0
            ~ < mk n { : ?String mo2 ( vec_get [String] matches mk ) ?? mo2 { T m → ( string_free m ) F _ → {} } = mk + mk 1 }
            ( vec_free [String] matches )
        }
        F _ → ( nurl_print `<err>` )
    }
    ( nurl_print `\n` )
}

// join base+name, write_file, free the joined path (leak-clean)
@ wfj s base s name s content → v {
    : String p ( __glob_join base name )
    : !v IoErr r ( write_file ( string_data p ) content )
    ?? r { T _ → {} F _ → ( nurl_print `write FAILED\n` ) }
    ( string_free p )
}

// join base+name, dir_create, free
@ mkd s base s name → v {
    : String p ( __glob_join base name )
    : !v IoErr r ( dir_create ( string_data p ) )
    ?? r { T _ → {} F _ → {} }
    ( string_free p )
}

// join root+pat, run a glob report, free the joined pattern
@ globj s label s root s pat → v {
    : String p ( __glob_join root pat )
    ( show_glob label root ( string_data p ) )
    ( string_free p )
}

@ main → i {
    // ── B6 fs_tempfile (standalone: create, assert, delete, free) ──
    : !String IoErr tro ( fs_tempfile `/tmp` `nurlglob_` )
    ?? tro {
        T p → {
            ( nurl_print `tempfile_ok=` )
            ( nurl_print ? ( __starts_with ( string_data p ) `/tmp/nurlglob_` ) `T` `F` ) ( nurl_print `\n` )
            : !v IoErr _d ( file_delete ( string_data p ) )
            ?? _d { T _ → {} F _ → {} }
            ( string_free p )
        }
        F _ → ( nurl_print `tempfile FAILED\n` )
    }

    // Unique root dir, fully owned (rootstr); `root` is a borrowed view.
    // getpid keeps it collision-free without printing into the golden.
    : String rootstr ( string_with_cap 48 )
    ( string_push_str rootstr `/tmp/nurlglob_root_` )
    ( string_push_str rootstr ( nurl_str_int ( getpid ) ) )
    : s root ( string_data rootstr )
    : !v IoErr _rm0 ( dir_remove_all root )   // clear any stale tree
    ?? _rm0 { T _ → {} F _ → {} }
    : !v IoErr _mk ( dir_create root )
    ?? _mk { T _ → {} F _ → ( nurl_print `mkdir root FAILED\n` ) }

    // build tree:
    //   root/a.nu root/b.nu root/c.txt root/.hidden
    //   root/src/main.nu root/src/util.nu root/src/sub/deep.nu
    : String src ( __glob_join root `src` )
    : String sub ( __glob_join ( string_data src ) `sub` )
    ( mkd root `src` )
    ( mkd ( string_data src ) `sub` )
    ( wfj root `a.nu` `a` )
    ( wfj root `b.nu` `b` )
    ( wfj root `c.txt` `c` )
    ( wfj root `.hidden` `h` )
    ( wfj ( string_data src ) `main.nu` `m` )
    ( wfj ( string_data src ) `util.nu` `u` )
    ( wfj ( string_data sub ) `deep.nu` `d` )

    // ── B7 glob patterns ──
    ( globj `star_nu` root `*.nu` )
    ( globj `star_all` root `*` )          // hides .hidden
    ( globj `question` root `?.nu` )       // a.nu b.nu
    ( globj `class` root `[ab].nu` )       // a.nu b.nu
    ( globj `class_neg` root `[!a]*.nu` )  // b.nu
    ( globj `dotglob` root `.*` )          // .hidden
    ( globj `nested` root `src/*.nu` )
    ( globj `doublestar` root `**/*.nu` )  // recursive
    ( globj `literal` root `c.txt` )
    ( globj `nomatch` root `*.md` )

    // ── B6 rename + copy ──
    : String af ( __glob_join root `a.nu` )
    : String renamed ( __glob_join root `renamed.nu` )
    : !v IoErr rr ( fs_rename ( string_data af ) ( string_data renamed ) )
    ( nurl_print `rename_ok=` ) ?? rr { T _ → ( nurl_print `T` ) F _ → ( nurl_print `F` ) }
    ( nurl_print ` a_gone=` ) ( nurl_print ? ( file_exists ( string_data af ) ) `F` `T` )
    ( nurl_print ` renamed_exists=` ) ( nurl_print ? ( file_exists ( string_data renamed ) ) `T` `F` ) ( nurl_print `\n` )

    : String csrc ( __glob_join root `c.txt` )
    : String cf ( __glob_join root `copy.txt` )
    : !v IoErr cr ( fs_copy_file ( string_data csrc ) ( string_data cf ) )
    ( nurl_print `copy_ok=` ) ?? cr { T _ → ( nurl_print `T` ) F _ → ( nurl_print `F` ) }
    : !String IoErr cc ( read_file ( string_data cf ) )
    ( nurl_print ` copy_content=` ) ?? cc { T s → { ( nurl_print ( string_data s ) ) ( string_free s ) } F _ → ( nurl_print `<err>` ) } ( nurl_print `\n` )

    // cleanup
    : !v IoErr _rm ( dir_remove_all root )
    ?? _rm { T _ → {} F _ → {} }
    ( string_free src ) ( string_free sub )
    ( string_free af ) ( string_free renamed )
    ( string_free csrc ) ( string_free cf )
    ( string_free rootstr )
    ^ 0
}
