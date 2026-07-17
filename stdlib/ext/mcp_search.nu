// stdlib/ext/mcp_search.nu — the search surface an MCP toolchain server
// offers a language model, shared by the playground API (nurlapi) and
// the local nurl-mcp package so the two never diverge:
//
//   * msearch_api_module — one module's API surface via nurldoc
//     (signatures + doc comments + full type definitions, no bodies)
//   * msearch_api_query  — AND-term search over every module's
//     declaration blocks; zero hits widen automatically to example
//     programs and the package registry; an exact package-name term is
//     noted in a footer regardless of hit count
//   * msearch_grep       — case-insensitive substring grep with
//     word-boundary RANKING (boundary-clean lines first, in-word tail
//     labeled; word=T drops the tail), plus registry name+description
//     search
//   * msearch_walk_nu_files — recursive .nu lister ({name,path,bytes}
//     into a Json array), shared by the corpus walkers and list tools
//
// All entry points take explicit directory paths and a registry base
// URL ("" skips that part) — no environment reads in here; resolve
// paths/registry at the call site (msearch_default_registry helps).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/nurldoc.nu`

// The registry to search: $NURL_REGISTRY, else the public default.
@ msearch_default_registry → String {
    ^ ( env_var_or `NURL_REGISTRY` `https://reg.nurl-lang.org/` )
}

// Lowercase an owned copy of a borrowed `s`.
@ __ms_lc s raw → String {
    : String tmp ( string_from raw )
    : String lc ( string_to_lower tmp )
    ( string_free tmp )
    ^ lc
}

// Join `root` with `prefix`; when `prefix` is empty, returns a fresh
// copy of `root`. Factored out because inline ternary on a String
// return trips a codegen bug ("call @?" with String args).
@ __ms_join_or_root s root s prefix → String {
    ? > ( nurl_str_len prefix ) 0 { ^ ( path_join root prefix ) } {}
    ^ ( string_from root )
}

// Walk `root_dir` recursively. For every regular .nu file found,
// append { name: <rel>, path: <rel>, bytes: N } to `arr`. `rel` is
// the path relative to root_dir (POSIX-style, "/" separator).
// Subdirectories are entered if dir_list succeeds on them. Entries
// at each level are sorted alphabetically before walking, which gives
// a globally sorted output (top-level "foo.nu" comes before subdir
// "g/bar.nu" iff "foo.nu" < "g" lexicographically).
@ msearch_walk_nu_files Json arr s root_dir s rel_prefix → v {
    : String full ( __ms_join_or_root root_dir rel_prefix )
    : !( Vec String ) IoErr dr ( dir_list ( string_data full ) )
    ?? dr {
        T entries → {
            ( sort_by [String] entries \ String a String b → i {
                ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) )
            } )
            : i n ( vec_len [String] entries )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [String] entries i ) {
                    T name → {
                        : String child_rel ( __ms_join_or_root rel_prefix ( string_data name ) )
                        : String child_full ( path_join ( string_data full ) ( string_data name ) )
                        ? ( string_ends_with name `.nu` ) {
                            : !i IoErr sz ( file_size ( string_data child_full ) )
                            ?? sz {
                                T bytes → {
                                    : Json o ( json_obj_new )
                                    ( json_obj_set o `name` ( json_str_lit ( string_data child_rel ) ) )
                                    ( json_obj_set o `path` ( json_str_lit ( string_data child_rel ) ) )
                                    ( json_obj_set o `bytes` ( json_int bytes ) )
                                    ( json_arr_push arr o )
                                }
                                F _ → {}
                            }
                        } {
                            // Try to recurse — if it's a directory, dir_list succeeds.
                            ( msearch_walk_nu_files arr root_dir ( string_data child_rel ) )
                        }
                        ( string_free child_full )
                        ( string_free child_rel )
                    }
                    F _ → {}
                }
                = i + i 1
            }
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] entries k ) { T fs → ( string_free fs ) F _ → {} }
                = k + k 1
            }
            ( vec_free [String] entries )
        }
        F _ → {}
    }
    ( string_free full )
}

// Render one stdlib module's doc surface; "" when unreadable.
@ __ms_api_render_module s stdlib_dir s rel → String {
    : String fp ( path_join stdlib_dir rel )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free fp )
    ?? rd {
        T bytes → {
            : String src ( bytes_to_str bytes )
            ( vec_free [u] bytes )
            : String md ( nurldoc_render ( string_data src ) rel )
            ( string_free src )
            ^ md
        }
        F _ → ^ ( string_new )
    }
}

@ __ms_api_out_cap → i { ^ 28672 }

// AND-match every non-empty lowercase term against hay_lc.
@ __ms_api_terms_match String hay_lc ( Vec String ) terms → b {
    : i n ( vec_len [String] terms )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] terms k ) {
            T t → {
                ? & > ( string_len t ) 0 < ( nurl_str_find ( string_data hay_lc ) ( string_data t ) ) 0 { ^ F } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ T
}

// Match one rendered module's "### "-delimited declaration blocks and
// append hits to `out`. ctr = [matched, emitted].
@ __ms_api_match_blocks String md s rel ( Vec String ) terms String out ( Vec i ) ctr → v {
    : ( Vec String ) parts ( string_split md `\n### ` )
    : i np ( vec_len [String] parts )
    : ~ i k 1  // part 0 = title + module header, not a declaration block
    ~ < k np {
        ?? ( vec_get [String] parts k ) {
            T blk → {
                : String hay ( string_with_cap + ( string_len blk ) 64 )
                ( string_push_str hay rel )
                ( string_push_char hay 32 )
                ( string_push_str hay ( string_data blk ) )
                : String hay_lc ( string_to_lower hay )
                ( string_free hay )
                ? ( __ms_api_terms_match hay_lc terms ) {
                    : i matched ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
                    ( vec_set [i] ctr 0 + matched 1 )
                    ? < ( string_len out ) ( __ms_api_out_cap ) {
                        // Block body, trimmed to keep many hits in view.
                        ( string_push_str out rel )
                        ( string_push_str out ` › ` )
                        : i bn ( string_len blk )
                        : i keep ? > bn 700 700 bn
                        : ~ i j 0
                        : s raw ( string_data blk )
                        ~ < j keep {
                            ( string_push_char out ( nurl_str_get raw j ) )
                            = j + j 1
                        }
                        ? > bn keep { ( string_push_str out `…` ) } {}
                        ( string_push_str out `\n\n` )
                        : i emitted ?? ( vec_get [i] ctr 1 ) { T v → v F _ → 0 }
                        ( vec_set [i] ctr 1 + emitted 1 )
                    } {}
                } {}
                ( string_free hay_lc )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] parts \ String p → v { ( string_free p ) } )
}

// List matching examples as `examples/<rel> — <header blurb>`. Returns
// the number shown (≤ 15).
@ __ms_api_fallback_examples s examples_dir ( Vec String ) terms String out → i {
    : String dir ( string_from examples_dir )
    : Json files ( json_arr_new )
    ( msearch_walk_nu_files files ( string_data dir ) `` )
    : i nf ( json_arr_len files )
    : ~ i shown 0
    : ~ i k 0
    ~ & < k nf < shown 15 {
        ?? ( json_arr_get files k ) {
            T fo → {
                : ~ s rel ``
                ?? ( json_obj_get fo `path` ) {
                    T pj → { ? ( json_is_str pj ) { = rel ( json_as_str pj ) } {} }
                    F _ → {}
                }
                ? > ( nurl_str_len rel ) 0 {
                    : String fp ( path_join ( string_data dir ) rel )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                    ( string_free fp )
                    ?? rd {
                        T bytes → {
                            : String src ( bytes_to_str bytes )
                            ( vec_free [u] bytes )
                            : String hay ( string_with_cap + ( string_len src ) 64 )
                            ( string_push_str hay rel )
                            ( string_push_char hay 32 )
                            ( string_push_str hay ( string_data src ) )
                            : String hay_lc ( string_to_lower hay )
                            ( string_free hay )
                            ? ( __ms_api_terms_match hay_lc terms ) {
                                ? == shown 0 { ( string_push_str out `Examples containing every term:\n` ) } {}
                                ( string_push_str out `  examples/` )
                                ( string_push_str out rel )
                                // Blurb: the file's first `//` header line.
                                : s sraw ( string_data src )
                                ? & >= ( string_len src ) 2 & == ( nurl_str_get sraw 0 ) 47 == ( nurl_str_get sraw 1 ) 47 {
                                    : ~ i b 2
                                    ~ & < b ( string_len src ) | == ( nurl_str_get sraw b ) 47 == ( nurl_str_get sraw b ) 32 { = b + b 1 }
                                    ( string_push_str out ` — ` )
                                    : ~ i e b
                                    ~ & & < e ( string_len src ) < - e b 100 != ( nurl_str_get sraw e ) 10 { = e + e 1 }
                                    : ~ i j b
                                    ~ < j e {
                                        ( string_push_char out ( nurl_str_get sraw j ) )
                                        = j + j 1
                                    }
                                } {}
                                ( string_push_char out 10 )
                                = shown + shown 1
                            } {}
                            ( string_free hay_lc )
                            ( string_free src )
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_free files )
    ( string_free dir )
    ^ shown
}

// Registry search per term (≤ 3 terms), de-duplicated by package name.
// Returns the number of packages listed.
@ __ms_api_fallback_packages s regbase ( Vec String ) terms String out → i {
    : ( Vec String ) seen ( vec_new [String] )
    : ~ i shown 0
    : i tn ( vec_len [String] terms )
    : ~ i tk 0
    ~ & < tk tn < tk 3 {
        ?? ( vec_get [String] terms tk ) {
            T t → {
                ? > ( string_len t ) 0 {
                    : String url ( string_with_cap 128 )
                    ( string_push_str url regbase )
                    ? != ( string_get url - ( string_len url ) 1 ) 47 { ( string_push_char url 47 ) } {}
                    ( string_push_str url `api/v1/search?q=` )
                    : String enc ( url_percent_encode ( string_data t ) )
                    ( string_push_str url ( string_data enc ) )
                    ( string_free enc )
                    : !Response HttpErr r ( http_get ( string_data url ) )
                    ( string_free url )
                    ?? r {
                        T resp → {
                            ?? ( json_parse ( http_body_str resp ) ) {
                                T root → {
                                    ?? ( json_obj_get root `results` ) {
                                        T arr → {
                                            : i n ( json_arr_len arr )
                                            : ~ i k 0
                                            ~ < k n {
                                                ?? ( json_arr_get arr k ) {
                                                    T o → {
                                                        : ~ s nm ``
                                                        ?? ( json_obj_get o `name` ) {
                                                            T nj → { ? ( json_is_str nj ) { = nm ( json_as_str nj ) } {} }
                                                            F _ → {}
                                                        }
                                                        ? & > ( nurl_str_len nm ) 0 ! ( __ms_has_str seen nm ) {
                                                            ( vec_push [String] seen ( string_from nm ) )
                                                            ? == shown 0 { ( string_push_str out `Registry packages matching (name/description):\n` ) } {}
                                                            ( string_push_str out `  package ` )
                                                            ( string_push_str out nm )
                                                            ?? ( json_obj_get o `version` ) {
                                                                T vj → {
                                                                    ? ( json_is_str vj ) {
                                                                        ( string_push_char out 32 )
                                                                        ( string_push_str out ( json_as_str vj ) )
                                                                    } {}
                                                                }
                                                                F _ → {}
                                                            }
                                                            ?? ( json_obj_get o `description` ) {
                                                                T dj → {
                                                                    ? ( json_is_str dj ) {
                                                                        : s d ( json_as_str dj )
                                                                        : i dn ( nurl_str_len d )
                                                                        ? > dn 0 {
                                                                            ( string_push_str out ` — ` )
                                                                            : ~ i keep ? > dn 160 160 dn
                                                                            : ~ i j 0
                                                                            ~ < j keep {
                                                                                : i c ( nurl_str_get d j )
                                                                                ( string_push_char out ? == c 10 32 c )
                                                                                = j + j 1
                                                                            }
                                                                            ? > dn 160 { ( string_push_str out `…` ) } {}
                                                                        } {}
                                                                    } {}
                                                                }
                                                                F _ → {}
                                                            }
                                                            ( string_push_char out 10 )
                                                            = shown + shown 1
                                                        } {}
                                                    }
                                                    F _ → {}
                                                }
                                                = k + k 1
                                            }
                                        }
                                        F _ → {}
                                    }
                                    ( json_free root )
                                }
                                F _ → {}
                            }
                            ( response_free resp )
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = tk + tk 1
    }
    ( vec_free_with [String] seen \ String v → v { ( string_free v ) } )
    ^ shown
}

// Exact-name registry note: when a query TERM is itself a package name,
// say so in one footer line — regardless of how many stdlib declarations
// matched. "http" returns 385 declarations; the fact that a package
// named http exists (and what it IS) must not drown under them.
@ __ms_api_exact_pkg_note s regbase ( Vec String ) terms String out → v {
    : i tn ( vec_len [String] terms )
    : ~ i tk 0
    ~ & < tk tn < tk 2 {
        ?? ( vec_get [String] terms tk ) {
            T t → {
                ? >= ( string_len t ) 2 {
                    : String url ( string_with_cap 128 )
                    ( string_push_str url regbase )
                    ? != ( string_get url - ( string_len url ) 1 ) 47 { ( string_push_char url 47 ) } {}
                    ( string_push_str url `api/v1/search?q=` )
                    : String enc ( url_percent_encode ( string_data t ) )
                    ( string_push_str url ( string_data enc ) )
                    ( string_free enc )
                    : !Response HttpErr r ( http_get ( string_data url ) )
                    ( string_free url )
                    ?? r {
                        T resp → {
                            ?? ( json_parse ( http_body_str resp ) ) {
                                T root → {
                                    ?? ( json_obj_get root `results` ) {
                                        T arr → {
                                            : i n ( json_arr_len arr )
                                            : ~ i k 0
                                            ~ < k n {
                                                ?? ( json_arr_get arr k ) {
                                                    T o → {
                                                        : ~ s nm ``
                                                        ?? ( json_obj_get o `name` ) {
                                                            T nj → { ? ( json_is_str nj ) { = nm ( json_as_str nj ) } {} }
                                                            F _ → {}
                                                        }
                                                        ? != 0 ( nurl_str_eq nm ( string_data t ) ) {
                                                            ( string_push_str out `\nNote: the registry has a package named '` )
                                                            ( string_push_str out nm )
                                                            ( string_push_str out `'` )
                                                            ?? ( json_obj_get o `description` ) {
                                                                T dj → {
                                                                    ? ( json_is_str dj ) {
                                                                        : s d ( json_as_str dj )
                                                                        : i dn ( nurl_str_len d )
                                                                        ? > dn 0 {
                                                                            ( string_push_str out ` — ` )
                                                                            : ~ i keep ? > dn 200 200 dn
                                                                            : ~ i j 0
                                                                            ~ < j keep {
                                                                                : i c ( nurl_str_get d j )
                                                                                ( string_push_char out ? == c 10 32 c )
                                                                                = j + j 1
                                                                            }
                                                                            ? > dn 200 { ( string_push_str out `…` ) } {}
                                                                        } {}
                                                                    } {}
                                                                }
                                                                F _ → {}
                                                            }
                                                            ( string_push_char out 10 )
                                                        } {}
                                                    }
                                                    F _ → {}
                                                }
                                                = k + k 1
                                            }
                                        }
                                        F _ → {}
                                    }
                                    ( json_free root )
                                }
                                F _ → {}
                            }
                            ( response_free resp )
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = tk + tk 1
    }
}

// Registry package search: /api/v1/search matches name + description.
@ __ms_grep_packages s regbase s pattern String out → v {
    : String url ( string_with_cap 128 )
    ( string_push_str url regbase )
    ? != ( string_get url - ( string_len url ) 1 ) 47 { ( string_push_char url 47 ) } {}
    ( string_push_str url `api/v1/search?q=` )
    : String enc ( url_percent_encode pattern )
    ( string_push_str url ( string_data enc ) )
    ( string_free enc )
    : !Response HttpErr r ( http_get ( string_data url ) )
    ( string_free url )
    ?? r {
        T resp → {
            : s body ( http_body_str resp )
            ?? ( json_parse body ) {
                T root → {
                    ?? ( json_obj_get root `results` ) {
                        T arr → {
                            : i n ( json_arr_len arr )
                            ? > n 0 { ( string_push_str out `\nRegistry packages matching (name/description):\n` ) } {}
                            : ~ i k 0
                            ~ < k n {
                                ?? ( json_arr_get arr k ) {
                                    T o → {
                                        ( string_push_str out `  package ` )
                                        ?? ( json_obj_get o `name` ) {
                                            T nj → { ( string_push_str out ( json_as_str nj ) ) }
                                            F _ → {}
                                        }
                                        ?? ( json_obj_get o `version` ) {
                                            T vj → {
                                                ? ( json_is_str vj ) {
                                                    ( string_push_char out 32 )
                                                    ( string_push_str out ( json_as_str vj ) )
                                                } {}
                                            }
                                            F _ → {}
                                        }
                                        ?? ( json_obj_get o `description` ) {
                                            T dj → {
                                                ? ( json_is_str dj ) {
                                                    ( string_push_str out ` — ` )
                                                    // First 200 bytes of the description.
                                                    : s d ( json_as_str dj )
                                                    : i dn ( nurl_str_len d )
                                                    : ~ i keep ? > dn 200 200 dn
                                                    : ~ i j 0
                                                    ~ < j keep {
                                                        : i c ( nurl_str_get d j )
                                                        ( string_push_char out ? == c 10 32 c )
                                                        = j + j 1
                                                    }
                                                    ? > dn 200 { ( string_push_str out `…` ) } {}
                                                } {}
                                            }
                                            F _ → {}
                                        }
                                        ( string_push_char out 10 )
                                    }
                                    F _ → {}
                                }
                                = k + k 1
                            }
                        }
                        F _ → {}
                    }
                    ( json_free root )
                }
                F _ → {}
            }
            ( response_free resp )
        }
        F _ → { ( string_push_str out `\n(registry search unavailable)\n` ) }
    }
}

// Borrow-safe contains for the dedupe list above.
@ __ms_has_str ( Vec String ) v s want → b {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) {
            T e → {
                ? != 0 ( nurl_str_eq ( string_data e ) want ) { ^ T } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

@ __ms_grep_out_cap → i { ^ 24576 }

@ __ms_grep_file_hits_cap → i { ^ 8 }

@ __ms_grep_alpha i c → b {
    ? & >= c 97 <= c 122 { ^ T } {}
    ^ & >= c 65 <= c 90
}

// Classify one line against the pattern:
//   0 — no substring match at all
//   1 — at least one occurrence sits at word boundaries: the adjacent
//       bytes are not LETTERS (line edges qualify; digits, underscore
//       and punctuation all count as boundaries — `mcp` is clean in
//       `mcp_call`, `/mcp` and `mcp2`, but not in `memcpy` or `-mcpu`)
//   2 — substring occurrences only, every one inside a longer word
// Scans every occurrence: an early in-word hit must not mask a later
// boundary-clean one on the same line.
@ __ms_grep_line_class String line_lc String pat_lc → i {
    : s hay ( string_data line_lc )
    : s pat ( string_data pat_lc )
    ? < ( nurl_str_find hay pat ) 0 { ^ 0 } {}
    : i n ( string_len line_lc )
    : i m ( string_len pat_lc )
    ? | == m 0 > m n { ^ 2 } {}
    : ~ i k 0
    ~ <= k - n m {
        : ~ b hit T
        : ~ i j 0
        ~ & hit < j m {
            ? != ( nurl_str_get hay + k j ) ( nurl_str_get pat j ) { = hit F } {}
            = j + j 1
        }
        ? hit {
            : ~ b lb T
            ? > k 0 { = lb ! ( __ms_grep_alpha ( nurl_str_get hay - k 1 ) ) } {}
            : ~ b rb T
            ? < + k m n { = rb ! ( __ms_grep_alpha ( nurl_str_get hay + k m ) ) } {}
            ? & lb rb { ^ 1 } {}
        } {}
        = k + k 1
    }
    ^ 2
}

// Byte budgets: boundary-clean hits get the lion's share; in-word hits
// are usually noise for short patterns, so a small tail is enough to
// show they exist without drowning the signal.
@ __ms_grep_clean_cap → i { ^ 20480 }

@ __ms_grep_word_cap → i { ^ 4096 }

// Append one `<label>/<rel>:<ln>: <text>` hit line (200-byte trim).
@ __ms_grep_push_hit String buf s label s rel i lineno String line → v {
    ( string_push_str buf label )
    ( string_push_char buf 47 )
    ( string_push_str buf rel )
    ( string_push_char buf 58 )
    ( string_push_int buf lineno )
    ( string_push_str buf `: ` )
    : ~ i keep ( string_len line )
    ? > keep 200 { = keep 200 } {}
    : s lraw ( string_data line )
    : ~ i j 0
    ~ < j keep {
        : i c ( nurl_str_get lraw j )
        ( string_push_char buf ? == c 9 32 c )
        = j + j 1
    }
    ? > ( string_len line ) 200 { ( string_push_str buf `…` ) } {}
    ( string_push_char buf 10 )
}

// Grep one file into the two class buffers. word=T drops in-word lines
// entirely (they are still counted, so the header can say how many were
// filtered). ctr = [matched_clean, emitted_clean, matched_word,
// emitted_word]; per-file cap applies per class.
@ __ms_grep_one_file s root s rel s label String pat_lc b word String out_clean String out_word ( Vec i ) ctr → v {
    : String fp ( path_join root rel )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free fp )
    ?? rd {
        T bytes → {
            : String src ( bytes_to_str bytes )
            ( vec_free [u] bytes )
            : ( Vec String ) lines ( string_split src `\n` )
            ( string_free src )
            : i nl ( vec_len [String] lines )
            : ~ i file_clean 0
            : ~ i file_word 0
            : ~ i li 0
            ~ < li nl {
                ?? ( vec_get [String] lines li ) {
                    T line → {
                        : String line_lc ( string_to_lower line )
                        : i cls ( __ms_grep_line_class line_lc pat_lc )
                        ? == cls 1 {
                            : i mc ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
                            ( vec_set [i] ctr 0 + mc 1 )
                            ? & < file_clean ( __ms_grep_file_hits_cap ) < ( string_len out_clean ) ( __ms_grep_clean_cap ) {
                                ( __ms_grep_push_hit out_clean label rel + li 1 line )
                                = file_clean + file_clean 1
                                : i ec ?? ( vec_get [i] ctr 1 ) { T v → v F _ → 0 }
                                ( vec_set [i] ctr 1 + ec 1 )
                            } {}
                        } {}
                        ? == cls 2 {
                            : i mw ?? ( vec_get [i] ctr 2 ) { T v → v F _ → 0 }
                            ( vec_set [i] ctr 2 + mw 1 )
                            ? & & ! word < file_word ( __ms_grep_file_hits_cap ) < ( string_len out_word ) ( __ms_grep_word_cap ) {
                                ( __ms_grep_push_hit out_word label rel + li 1 line )
                                = file_word + file_word 1
                                : i ew ?? ( vec_get [i] ctr 3 ) { T v → v F _ → 0 }
                                ( vec_set [i] ctr 3 + ew 1 )
                            } {}
                        } {}
                        ( string_free line_lc )
                    }
                    F _ → {}
                }
                = li + li 1
            }
            ? >= file_clean ( __ms_grep_file_hits_cap ) {
                ( string_push_str out_clean `  (…more hits in ` )
                ( string_push_str out_clean rel )
                ( string_push_str out_clean ` capped)\n` )
            } {}
            ? >= file_word ( __ms_grep_file_hits_cap ) {
                ( string_push_str out_word `  (…more hits in ` )
                ( string_push_str out_word rel )
                ( string_push_str out_word ` capped)\n` )
            } {}
            ( vec_free_with [String] lines \ String l → v { ( string_free l ) } )
        }
        F _ → {}
    }
}

// Grep one corpus directory (recursively, .nu files).
@ __ms_grep_corpus s root s label String pat_lc b word String out_clean String out_word ( Vec i ) ctr → v {
    : Json files ( json_arr_new )
    ( msearch_walk_nu_files files root `` )
    : i nf ( json_arr_len files )
    : ~ i k 0
    ~ < k nf {
        ? < ( string_len out_clean ) ( __ms_grep_clean_cap ) {
            ?? ( json_arr_get files k ) {
                T fo → {
                    ?? ( json_obj_get fo `path` ) {
                        T pj → {
                            ? ( json_is_str pj ) {
                                ( __ms_grep_one_file root ( json_as_str pj ) label pat_lc word out_clean out_word ctr )
                            } {}
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        } {}
        = k + k 1
    }
    ( json_free files )
}

// One module's API surface (nurldoc render, byte-capped with a note);
// "" when the module is unreadable/missing.
@ msearch_api_module s stdlib_dir s rel → String {
    : String md ( __ms_api_render_module stdlib_dir rel )
    ? == ( string_len md ) 0 { ^ md } {}
    ? > ( string_len md ) ( __ms_api_out_cap ) {
        : String cut ( string_substr md 0 ( __ms_api_out_cap ) )
        ( string_push_str cut `\n… truncated — use nurl_read_stdlib for the full source.\n` )
        ( string_free md )
        ^ cut
    } {}
    ^ md
}

// Declaration search over every module under stdlib_dir. Zero hits
// widen to examples_dir ("" skips) and the registry (regbase "" skips);
// an exact package-name term is footnoted regardless of hit count.
// Returns the COMPLETE reply text.
@ msearch_api_query s stdlib_dir s examples_dir s regbase s query → String {
    : String q_lc ( __ms_lc query )
    : ( Vec String ) terms ( string_split q_lc ` ` )
    : String out ( string_with_cap 4096 )
    : ( Vec i ) ctr ( vec_new [i] )
    ( vec_push [i] ctr 0 ) ( vec_push [i] ctr 0 )

    : String dir ( string_from stdlib_dir )
    : Json files ( json_arr_new )
    ( msearch_walk_nu_files files ( string_data dir ) `` )
    : i nf ( json_arr_len files )
    : ~ i k 0
    ~ < k nf {
        ?? ( json_arr_get files k ) {
            T fo → {
                : ~ s rel ``
                ?? ( json_obj_get fo `path` ) {
                    T pj → { ? ( json_is_str pj ) { = rel ( json_as_str pj ) } {} }
                    F _ → {}
                }
                ? > ( nurl_str_len rel ) 0 {
                    // Cheap raw-source pre-filter: skip modules where the
                    // terms can't all occur (path counts as haystack too).
                    : String fp ( path_join ( string_data dir ) rel )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                    ( string_free fp )
                    ?? rd {
                        T bytes → {
                            : String src ( bytes_to_str bytes )
                            ( vec_free [u] bytes )
                            : String pre ( string_with_cap + ( string_len src ) 64 )
                            ( string_push_str pre rel )
                            ( string_push_char pre 32 )
                            ( string_push_str pre ( string_data src ) )
                            : String pre_lc ( string_to_lower pre )
                            ( string_free pre )
                            ? ( __ms_api_terms_match pre_lc terms ) {
                                : String md ( nurldoc_render ( string_data src ) rel )
                                ( __ms_api_match_blocks md rel terms out ctr )
                                ( string_free md )
                            } {}
                            ( string_free pre_lc )
                            ( string_free src )
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_free files )
    ( string_free dir )

    : i matched ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
    : i emitted ?? ( vec_get [i] ctr 1 ) { T v → v F _ → 0 }
    : String hdr ( string_with_cap + ( string_len out ) 256 )
    ( string_push_int hdr matched )
    ( string_push_str hdr ` stdlib declaration(s) match '` )
    ( string_push_str hdr query )
    ( string_push_str hdr `'.\n\n` )
    ( string_push_str hdr ( string_data out ) )
    ? == matched 0 {
        // Widen rather than shrug: the same terms against example files
        // and the package registry, in the same reply.
        ( string_push_str hdr `No stdlib declaration matches — widened the search:\n\n` )
        : ~ i ex_n 0
        ? > ( nurl_str_len examples_dir ) 0 { = ex_n ( __ms_api_fallback_examples examples_dir terms hdr ) } {}
        ? > ex_n 0 { ( string_push_char hdr 10 ) } {}
        : ~ i pk_n 0
        ? > ( nurl_str_len regbase ) 0 { = pk_n ( __ms_api_fallback_packages regbase terms hdr ) } {}
        ? == + ex_n pk_n 0 {
            ( string_push_str hdr `Nothing in examples or the registry either — terms are AND-ed substrings; try fewer or shorter terms, or nurl_grep for raw line search.\n` )
        } {}
    } {}
    ? > matched emitted {
        ( string_push_str hdr `… ` )
        ( string_push_int hdr - matched emitted )
        ( string_push_str hdr ` more matching declarations omitted (byte cap) — narrow the query or read one module with 'module'.\n` )
    } {}
    // The 0-hit path already listed registry matches in full; otherwise an
    // exact package-name hit still deserves its one-line footer.
    ? & > matched 0 > ( nurl_str_len regbase ) 0 { ( __ms_api_exact_pkg_note regbase terms hdr ) } {}
    ( string_free out ) ( vec_free [i] ctr )
    ( vec_free_with [String] terms \ String t → v { ( string_free t ) } )
    ( string_free q_lc )
    ^ hdr
}

// Ranked grep across up to three corpora ("" skips one) plus the
// registry (regbase "" skips). Returns the COMPLETE reply text.
@ msearch_grep s pattern b word s stdlib_dir s examples_dir s tests_dir s regbase → String {
    : String pat_lc ( __ms_lc pattern )
    : String out_clean ( string_with_cap 4096 )
    : String out_word ( string_with_cap 1024 )
    : ( Vec i ) ctr ( vec_new [i] )
    ( vec_push [i] ctr 0 ) ( vec_push [i] ctr 0 ) ( vec_push [i] ctr 0 ) ( vec_push [i] ctr 0 )
    ? > ( nurl_str_len stdlib_dir ) 0 { ( __ms_grep_corpus stdlib_dir `stdlib` pat_lc word out_clean out_word ctr ) } {}
    ? > ( nurl_str_len examples_dir ) 0 { ( __ms_grep_corpus examples_dir `examples` pat_lc word out_clean out_word ctr ) } {}
    ? > ( nurl_str_len tests_dir ) 0 { ( __ms_grep_corpus tests_dir `tests` pat_lc word out_clean out_word ctr ) } {}

    : i m_clean ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
    : i e_clean ?? ( vec_get [i] ctr 1 ) { T v → v F _ → 0 }
    : i m_word ?? ( vec_get [i] ctr 2 ) { T v → v F _ → 0 }
    : i e_word ?? ( vec_get [i] ctr 3 ) { T v → v F _ → 0 }

    // Header + boundary-clean hits first, then the in-word tail (or the
    // filtered count when word=true) — for a short pattern like `mcp`
    // this puts the signal on top and the memcpy noise, clearly labeled,
    // at the bottom.
    : String hdr ( string_with_cap + + ( string_len out_clean ) ( string_len out_word ) 512 )
    ( string_push_int hdr m_clean )
    ( string_push_str hdr ` line(s) match '` )
    ( string_push_str hdr pattern )
    ( string_push_str hdr `' at word boundaries` )
    ? > m_word 0 {
        ( string_push_str hdr `, plus ` )
        ( string_push_int hdr m_word )
        ( string_push_str hdr ` inside longer words` )
    } {}
    ( string_push_str hdr ` (case-insensitive).\n\n` )
    ( string_push_str hdr ( string_data out_clean ) )
    ? & word > m_word 0 {
        ( string_push_str hdr `(word=true — ` )
        ( string_push_int hdr m_word )
        ( string_push_str hdr ` line(s) with only in-word matches filtered out)\n` )
    } {}
    ? & ! word > m_word 0 {
        ( string_push_str hdr `\n— matches inside longer words (substring only):\n` )
        ( string_push_str hdr ( string_data out_word ) )
    } {}
    ? > ( nurl_str_len regbase ) 0 { ( __ms_grep_packages regbase pattern hdr ) } {}
    : i omitted - + m_clean ? word 0 m_word + e_clean e_word
    ? > omitted 0 {
        ( string_push_str hdr `… ` )
        ( string_push_int hdr omitted )
        ( string_push_str hdr ` more matching lines omitted (per-file/total caps) — narrow the pattern or scope with 'where'.\n` )
    } {}
    ( string_free out_clean ) ( string_free out_word )
    ( vec_free [i] ctr ) ( string_free pat_lc )
    ^ hdr
}
