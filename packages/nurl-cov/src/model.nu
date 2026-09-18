// nurl-cov/model.nu — one coverage picture from many test binaries.
//
// A suite is not one program. Each test is built and run on its own, so
// each leaves its own pair of coverage graphs, and each sees only the part
// of the package it exercises. The number a person wants is the union: a
// line covered by the parser test and the writer test is covered, and one
// covered by neither is the finding.
//
// Merging is addition, on three axes:
//
//   * line counts add, so a helper called by every test reports the
//     traffic of every test,
//   * branch outcomes add, matched by (line, ordinal) — the numbering the
//     notes fix, which every binary built from the same source agrees on,
//   * a function's call count adds, matched by (line, name).
//
// A file no test ever compiled in is simply absent, and absent is not the
// same as uncovered: this model reports what the tests built. `runner.nu`
// is what makes sure they build everything the package ships.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `gcov.nu`
$ `lines.nu`

: CovFn {
    String name
    i line
    i called  // entries, summed over every object
}

// Branch table stride.
: i CBR_W 3
: i CBR_LINE 0
: i CBR_IDX 1  // ordinal within the line, as the notes numbered it
: i CBR_COUNT 2

: CovFile {
    String path
    ( Vec i ) exists  // indexed by line number: 1 when the line has code
    ( Vec i ) count  // indexed by line number: executions
    ( Vec i ) branches  // stride CBR_W
    ( Vec CovFn ) funcs
}

: Cov {
    ( Vec CovFile ) files
    i objects  // how many coverage objects were folded in
}

: CovStat {
    i lines_found
    i lines_hit
    i branches_found
    i branches_hit
    i funcs_found
    i funcs_hit
}

@ cov_new → *Cov {
    : *Cov c # *Cov ( nurl_alloc Z Cov )
    = . c files ( vec_new [CovFile] )
    = . c objects 0
    ^ c
}

@ cov_free sink * Cov c → v {
    : i n ( vec_len [CovFile] . c files )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [CovFile] . c files i ) {
            T f → {
                ( string_free . f path )
                ( vec_free [i] . f exists )
                ( vec_free [i] . f count )
                ( vec_free [i] . f branches )
                ( __cov_free_fns . f funcs )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [CovFile] . c files )
    ( nurl_free # s c )
}

@ __cov_free_fns ( Vec CovFn ) v → v {
    : i n ( vec_len [CovFn] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [CovFn] v i ) { T f → ( string_free . f name ) F _ → {} }
        = i + i 1
    }
    ( vec_free [CovFn] v )
}

@ __cov_at ( Vec i ) v i idx → i {
    ^ ?? ( vec_get [i] v idx ) { T x → x F _ → 0 }
}

@ __cov_grow ( Vec i ) v i idx → v {
    : i have ( vec_len [i] v )
    ? > + idx 1 have {
        : ~ i k have
        ~ < k + idx 1 { ( vec_push [i] v 0 ) = k + k 1 }
    } {}
}

@ cov_file_count * Cov c → i { ^ ( vec_len [CovFile] . c files ) }

@ cov_file_path * Cov c i idx → s {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ( string_data . f path )
        F _ → ``
    }
}

// The row for `path`, created when this is the first object to mention it.
@ cov_file_idx * Cov c s path → i {
    : i n ( vec_len [CovFile] . c files )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [CovFile] . c files i ) {
            T f → ? != 0 ( nurl_str_eq ( string_data . f path ) path ) { ^ i } {}
            F _ → {}
        }
        = i + i 1
    }
    ( vec_push [CovFile] . c files @ CovFile {
        ( string_from path )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [CovFn] )
    } )
    ^ n
}

// ── Folding one object in ────────────────────────────────────────

@ cov_add_object * Cov c * GcovObj o → v {
    : i nf ( gcov_file_count o )
    : ~ i src 0
    ~ < src nf {
        : *LineTab t ( lines_build o src )
        ( __cov_add_file c o t src )
        ( linetab_free t )
        = src + src 1
    }
    = . c objects + 1 . c objects
}

@ __cov_add_file * Cov c * GcovObj o * LineTab t i src → v {
    : i fidx ( cov_file_idx c ( gcov_file_path o src ) )
    ?? ( vec_get [CovFile] . c files fidx ) {
        T f → {
            : i n ( vec_len [i] . t exists )
            : ~ i l 0
            ~ < l n {
                ? != 0 ( __cov_at . t exists l ) {
                    ( __cov_grow . f exists l )
                    ( __cov_grow . f count l )
                    ( vec_set [i] . f exists l 1 )
                    ( vec_set [i] . f count l
                    + ( __cov_at . f count l ) ( __cov_at . t count l ) )
                } {}
                = l + l 1
            }
            ( __cov_add_branches f t )
            ( __cov_add_funcs f o t )
        }
        F _ → {}
    }
}

// Branch rows arrive grouped by line and numbered from zero within each
// line, which is what makes them addressable across binaries.
@ __cov_add_branches CovFile f * LineTab t → v {
    : i n / ( vec_len [i] . t br ) LBR_W
    : ~ i k 0
    : ~ i line -1
    : ~ i idx 0
    ~ < k n {
        : i l ( __cov_at . t br + * k LBR_W LBR_LINE )
        ? != l line { = line l = idx 0 } {}
        ( __cov_branch_add . f branches l idx
        ( __cov_at . t br + * k LBR_W LBR_COUNT ) )
        = idx + idx 1
        = k + k 1
    }
}

@ __cov_branch_add ( Vec i ) br i line i idx i count → v {
    : i n ( vec_len [i] br )
    : ~ i k 0
    ~ < k n {
        ? & == line ( __cov_at br + k CBR_LINE ) == idx ( __cov_at br + k CBR_IDX ) {
            ( vec_set [i] br + k CBR_COUNT + count ( __cov_at br + k CBR_COUNT ) )
            ^ v
        } {}
        = k + k CBR_W
    }
    ( vec_push [i] br line )
    ( vec_push [i] br idx )
    ( vec_push [i] br count )
}

// Block 0 is the entry block, so its count is the call count.
@ __cov_add_funcs CovFile f * GcovObj o * LineTab t → v {
    : i n / ( vec_len [i] . t fnrow ) LFN_W
    : ~ i k 0
    ~ < k n {
        : i line ( __cov_at . t fnrow + * k LFN_W LFN_LINE )
        : i fi ( __cov_at . t fnrow + * k LFN_W LFN_FN )
        ? > ( gcov_fn_nblocks o fi ) 0 {
            ( __cov_fn_add . f funcs ( gcov_fn_name o fi ) line
            ( gcov_block_count o fi 0 ) )
        } {}
        = k + k 1
    }
}

@ __cov_fn_add ( Vec CovFn ) funcs s name i line i called → v {
    : i n ( vec_len [CovFn] funcs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CovFn] funcs k ) {
            T e → ? & == . e line line
            != 0 ( nurl_str_eq ( string_data . e name ) name ) {
                ( vec_set [CovFn] funcs k
                @ CovFn { . e name line + . e called called } )
                ^ v
            } {}
            F _ → {}
        }
        = k + k 1
    }
    ( vec_push [CovFn] funcs @ CovFn { ( string_from name ) line called } )
}

// ── Dropping files out of the picture ────────────────────────────
//
// A test binary compiles the whole stdlib in with it. Reporting that as
// the package's coverage would drown the package: the number a maintainer
// acts on is the coverage of the code they wrote.

@ cov_keep_only * Cov c ( Vec String ) prefixes → v {
    ? == 0 ( vec_len [String] prefixes ) { ^ v } {}
    : ( Vec CovFile ) keep ( vec_new [CovFile] )
    : i n ( vec_len [CovFile] . c files )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [CovFile] . c files i ) {
            T f → ? ( __cov_matches ( string_data . f path ) prefixes ) {
                ( vec_push [CovFile] keep f )
            } {
                ( string_free . f path )
                ( vec_free [i] . f exists )
                ( vec_free [i] . f count )
                ( vec_free [i] . f branches )
                ( __cov_free_fns . f funcs )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_clear [CovFile] . c files )
    : i m ( vec_len [CovFile] keep )
    : ~ i k 0
    ~ < k m {
        ?? ( vec_get [CovFile] keep k ) {
            T f → ( vec_push [CovFile] . c files f )
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [CovFile] keep )
}

@ __cov_matches s path ( Vec String ) prefixes → b {
    : i n ( vec_len [String] prefixes )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] prefixes k ) {
            T p → ? ( __cov_has_prefix path ( string_data p ) ) { ^ T } {}
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

@ __cov_has_prefix s path s prefix → b {
    : i n ( nurl_str_len prefix )
    ? > n ( nurl_str_len path ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ? != ( nurl_str_at path ( nurl_str_len path ) k ) ( nurl_str_at prefix n k ) {
            ^ F
        } {}
        = k + k 1
    }
    ^ T
}

// Order the report the way a person reads it: by path.
@ cov_sort * Cov c → v {
    : i n ( vec_len [CovFile] . c files )
    : ~ i i 1
    ~ < i n {
        : ~ i j i
        ~ > j 0 {
            : b swap ?? ( vec_get [CovFile] . c files - j 1 ) {
                T a → ?? ( vec_get [CovFile] . c files j ) {
                    T b → > ( nurl_str_cmp ( string_data . a path ) ( string_data . b path ) ) 0
                    F _ → F
                }
                F _ → F
            }
            ? swap { ( vec_swap [CovFile] . c files - j 1 j ) = j - j 1 } { = j 0 }
        }
        = i + i 1
    }
}

// ── Reading the model back ───────────────────────────────────────

@ cov_file_stat * Cov c i idx → CovStat {
    : ~ i lf 0
    : ~ i lh 0
    : ~ i bf 0
    : ~ i bh 0
    : ~ i ff 0
    : ~ i fh 0
    ?? ( vec_get [CovFile] . c files idx ) {
        T f → {
            : i n ( vec_len [i] . f exists )
            : ~ i l 0
            ~ < l n {
                ? != 0 ( __cov_at . f exists l ) {
                    = lf + lf 1
                    ? > ( __cov_at . f count l ) 0 { = lh + lh 1 } {}
                } {}
                = l + l 1
            }
            : i bn ( vec_len [i] . f branches )
            : ~ i k 0
            ~ < k bn {
                = bf + bf 1
                ? > ( __cov_at . f branches + k CBR_COUNT ) 0 { = bh + bh 1 } {}
                = k + k CBR_W
            }
            : i fn ( vec_len [CovFn] . f funcs )
            : ~ i q 0
            ~ < q fn {
                = ff + ff 1
                ?? ( vec_get [CovFn] . f funcs q ) {
                    T e → ? > . e called 0 { = fh + fh 1 } {}
                    F _ → {}
                }
                = q + q 1
            }
        }
        F _ → {}
    }
    ^ @ CovStat { lf lh bf bh ff fh }
}

@ cov_total * Cov c → CovStat {
    : ~ i lf 0
    : ~ i lh 0
    : ~ i bf 0
    : ~ i bh 0
    : ~ i ff 0
    : ~ i fh 0
    : i n ( vec_len [CovFile] . c files )
    : ~ i i 0
    ~ < i n {
        : CovStat s ( cov_file_stat c i )
        = lf + lf . s lines_found
        = lh + lh . s lines_hit
        = bf + bf . s branches_found
        = bh + bh . s branches_hit
        = ff + ff . s funcs_found
        = fh + fh . s funcs_hit
        = i + i 1
    }
    ^ @ CovStat { lf lh bf bh ff fh }
}

@ cov_max_line * Cov c i idx → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ? > ( vec_len [i] . f exists ) 0 - ( vec_len [i] . f exists ) 1 0
        F _ → 0
    }
}

@ cov_line_exists * Cov c i idx i line → b {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → != 0 ( __cov_at . f exists line )
        F _ → F
    }
}

@ cov_line_count * Cov c i idx i line → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ( __cov_at . f count line )
        F _ → 0
    }
}

@ cov_branch_rows * Cov c i idx → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → / ( vec_len [i] . f branches ) CBR_W
        F _ → 0
    }
}

@ cov_branch_field * Cov c i idx i row i field → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ( __cov_at . f branches + * row CBR_W field )
        F _ → 0
    }
}

@ cov_fn_rows * Cov c i idx → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ( vec_len [CovFn] . f funcs )
        F _ → 0
    }
}

@ cov_fn_name * Cov c i idx i row → s {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ?? ( vec_get [CovFn] . f funcs row ) {
            T e → ( string_data . e name )
            F _ → ``
        }
        F _ → ``
    }
}

@ cov_fn_line * Cov c i idx i row → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ?? ( vec_get [CovFn] . f funcs row ) { T e → . e line F _ → 0 }
        F _ → 0
    }
}

@ cov_fn_called * Cov c i idx i row → i {
    ^ ?? ( vec_get [CovFile] . c files idx ) {
        T f → ?? ( vec_get [CovFn] . f funcs row ) { T e → . e called F _ → 0 }
        F _ → 0
    }
}

// Percentages in tenths, so a report prints one decimal without floating
// point. An empty denominator is 100%: there is nothing left uncovered.
@ cov_pct_tenths i hit i found → i {
    ? <= found 0 { ^ 1000 } {}
    ^ / + * hit 1000 / found 2 found
}
