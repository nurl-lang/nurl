// loader — fill a TplSet from a directory of template files.
//
// ( tset_load_dir t dir ext ) loads every `dir/*<ext>` file (e.g. ext
// `.html`) into the set, named by its basename without the extension:
// `views/index.html` → `index`. Returns the number of templates loaded,
// or -1 when the directory glob fails. Individual unreadable files are
// skipped (counted out), not fatal.
//
// Kept out of template.nu so the engine itself has no fs dependency.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `src/template.nu`

@ tset_load_dir * TplSet t s dir s ext → i {
    : String pat ( string_from dir )
    ( string_push_str pat `/*` )
    ( string_push_str pat ext )
    : ~ i count 0
    ?? ( fs_glob ( string_data pat ) ) {
        T files → {
            : i nf ( vec_len [String] files )
            : ~ i k 0
            ~ < k nf {
                ?? ( vec_get [String] files k ) {
                    T path → {
                        // name = basename minus extension
                        : ~ i b0 0
                        : i plen ( string_len path )
                        : ~ i j 0
                        ~ < j plen {
                            ? == ( string_get path j ) 47 { = b0 + j 1 } {}
                            = j + j 1
                        }
                        : i nlen - - plen b0 ( nurl_str_len ext )
                        ? > nlen 0 {
                            : String name ( string_substr path b0 nlen )
                            ?? ( read_file ( string_data path ) ) {
                                T body → {
                                    ( tset_add t ( string_data name ) ( string_data body ) )
                                    ( string_free body )
                                    = count + count 1
                                }
                                F _ → {}
                            }
                            ( string_free name )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            : ( @ v String ) sdrop \ String x → v { ( string_free x ) }
            ( vec_free_with [String] files sdrop )
        }
        F _ → { = count - 0 1 }
    }
    ( string_free pat )
    ^ count
}
