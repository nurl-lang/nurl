// stdlib/ext/mcp_search.nu — the search surface an MCP toolchain server
// offers a language model, shared by the playground API (nurlapi) and
// the local nurl-mcp package so the two never diverge:
//
//   * msearch_api_module — one module's API surface via nurldoc
//     (signatures + doc comments + full type definitions, no bodies)
//   * msearch_api_query  — AND-term search over every module's
//     declaration blocks (terms split on spaces and commas); on zero
//     hits, a term that exactly NAMES a stdlib module ('csv' →
//     ext/csv.nu) returns that module's whole API surface; otherwise
//     the terms are re-run as a whole-word OR ranked by coverage, and
//     only if THAT finds nothing does the search widen to example
//     programs and the package registry; an exact package-name term is
//     noted in a footer regardless of hit count
//   * msearch_grep       — case-insensitive substring grep with
//     word-boundary RANKING (boundary-clean lines first, in-word tail
//     labeled; word=T drops the tail), plus registry name+description
//     search
//   * msearch_docs_list / msearch_docs_resolve / msearch_docs_read —
//     the docs/ prose tree (MEMORY.md, CRYPTO.md, …): what exists, and
//     one document by a forgiving name
//   * msearch_walk_nu_files / msearch_walk_md_files — recursive
//     listers ({name,path,bytes} into a Json array), shared by the
//     corpus walkers and list tools
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
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
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

// Walk `root_dir` recursively. For every regular file whose name ends
// in `ext`, append { name: <rel>, path: <rel>, bytes: N } to `arr`.
// `rel` is the path relative to root_dir (POSIX-style, "/" separator).
// Subdirectories are entered if dir_list succeeds on them. Entries
// at each level are sorted alphabetically before walking, which gives
// a globally sorted output (top-level "foo.nu" comes before subdir
// "g/bar.nu" iff "foo.nu" < "g" lexicographically).
@ __ms_walk_ext Json arr s root_dir s rel_prefix s ext → v {
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
                        ? ( string_ends_with name ext ) {
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
                            ( __ms_walk_ext arr root_dir ( string_data child_rel ) ext )
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

// The .nu corpus walker every search path uses.
@ msearch_walk_nu_files Json arr s root_dir s rel_prefix → v {
    ( __ms_walk_ext arr root_dir rel_prefix `.nu` )
}

// The .md corpus walker behind nurl_docs.
@ msearch_walk_md_files Json arr s root_dir s rel_prefix → v {
    ( __ms_walk_ext arr root_dir rel_prefix `.md` )
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
                                                            ( __ms_push_reg_next out nm o )
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

// The two lines an agent needs after a registry hit: how to depend on the
// package, and how to read its API surface (whose symbol names it cannot
// otherwise guess). `nm` is the already-known name; `o` carries the version.
@ __ms_push_reg_next String out s nm Json o → v {
    // Which of the package's symbols the query hit (registry symbol index) —
    // so a term the agent couldn't map to a package (e.g. 'gqa attention')
    // shows WHY 'nn' came back: it exports nn_gqa_attention.
    ?? ( json_obj_get o `matched_symbols` ) {
        T sa → {
            ? ( json_is_arr sa ) {
                : i sn ( json_arr_len sa )
                ? > sn 0 {
                    ( string_push_str out `    matched symbols: ` )
                    : ~ i si 0
                    ~ < si sn {
                        ?? ( json_arr_get sa si ) {
                            T sj → { ? ( json_is_str sj ) { ? > si 0 { ( string_push_char out 32 ) } {} ( string_push_str out ( json_as_str sj ) ) } {} }
                            F → {}
                        }
                        = si + si 1
                    }
                    ( string_push_char out 10 )
                } {}
            } {}
        }
        F → {}
    }
    ( string_push_str out `    add:  ` )
    ( string_push_str out nm )
    ( string_push_str out ` = "^` )
    : ~ b hasv F
    ?? ( json_obj_get o `version` ) {
        T vj → { ? ( json_is_str vj ) { ( string_push_str out ( json_as_str vj ) ) = hasv T } {} }
        F → {}
    }
    ? hasv {} { ( string_push_char out 42 ) }
    ( string_push_str out `"   ·   API: nurl_api package=` )
    ( string_push_str out nm )
    ( string_push_char out 10 )
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
                                        : ~ s nm ``
                                        ?? ( json_obj_get o `name` ) {
                                            T nj → { ? ( json_is_str nj ) { = nm ( json_as_str nj ) } {} }
                                            F _ → {}
                                        }
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
                                        ( __ms_push_reg_next out nm o )
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

// ── nurl_api: OR widening when every term together matches nothing ──
//
// A model that asks for "string builder append" or "vec_push new
// string_new" is naming a CONCEPT, not a conjunction any single
// declaration satisfies — and the AND search answers 0. Jumping
// straight from there to examples + registry throws away the fact that
// the stdlib does have string_push_str and vec_push; it just never has
// them in one declaration.
//
// So before widening the corpus, widen the OPERATOR: re-run the same
// terms as an OR over the same declaration blocks — but counting only
// WHOLE-word occurrences (the adjacent byte must not be a letter, so
// `string` hits string_push_str, string_new and `a string`, and misses
// substring), and rank each block by how much of the query it covers —
// see __ms_or_score2 for the weighting. That floats vec_push and
// string_new to the top of a three-term query instead of burying them
// under the ~200 declarations that merely say `new`.

// How many blocks the OR pass shows. Small on purpose: the point is the
// two or three declarations the model actually meant, not a corpus dump.
@ __ms_api_or_cap → i { ^ 12 }

// Terms shorter than this are dropped from the OR pass — a one-letter
// whole word matches half the corpus and tells the model nothing.
@ __ms_or_min_term → i { ^ 2 }

@ __ms_or_usable_terms ( Vec String ) terms → i {
    : i n ( vec_len [String] terms )
    : ~ i c 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] terms k ) {
            T t → { ? >= ( string_len t ) ( __ms_or_min_term ) { = c + c 1 } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ c
}

// Whole-word occurrences of `pat` in `hay` (both already lowercase) —
// the counting twin of __ms_grep_line_class, same boundary rule.
@ __ms_word_occ s hay s pat → i {
    : i n ( nurl_str_len hay )
    : i m ( nurl_str_len pat )
    ? | == m 0 > m n { ^ 0 } {}
    : ~ i cnt 0
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
            ? & lb rb { = cnt + cnt 1 } {}
        } {}
        = k + k 1
    }
    ^ cnt
}

// Coverage score for one declaration, packed into a single sortable i:
//
//   coverage: Σ length of the distinct terms found  × 100000
//   the same sum restricted to `sig_lc`             ×   1000
//   total occurrences (clamped to 999)                        tiebreak
//
// Terms are weighted by LENGTH, not counted: `new` is three characters
// that half the stdlib constructors contain, `vec_push` is eight that
// name one function, and a ranking that scores them equally buries the
// exact hit under the generic ones. `sig_lc` — module path + the
// declaration's signature line — then separates a term in the NAME from
// a term in the prose, so "string builder append" reaches
// string_push_bytes before the ArgParser struct, which wins on raw
// repetition alone (its body says String eight times).
//
// `stats` (≥ 1 element) receives the distinct-term count at [0] for the
// "[2/3 terms]" label. Pass "" as sig_lc for a plain any-term test.
// Returns 0 ⇔ no term occurs at all.
@ __ms_or_score2 s sig_lc s hay_lc ( Vec String ) terms ( Vec i ) stats → i {
    : i n ( vec_len [String] terms )
    : ~ i hits 0
    : ~ i cov 0
    : ~ i sig_cov 0
    : ~ i total 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] terms k ) {
            T t → {
                : i tl ( string_len t )
                ? >= tl ( __ms_or_min_term ) {
                    : i c ( __ms_word_occ hay_lc ( string_data t ) )
                    ? > c 0 {
                        = hits + hits 1
                        = cov + cov tl
                        = total + total c
                    } {}
                    ? > ( nurl_str_len sig_lc ) 0 {
                        ? > ( __ms_word_occ sig_lc ( string_data t ) ) 0 { = sig_cov + sig_cov tl } {}
                    } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_set [i] stats 0 hits )
    ? == hits 0 { ^ 0 } {}
    ^ + + * cov 100000 * sig_cov 1000 ? > total 999 999 total
}

// Keep the `cap` highest-scoring snippets, best first. `scores`/`texts`
// stay parallel and sorted descending; a snippet that cannot make the
// cut is simply not copied.
@ __ms_topk_push ( Vec i ) scores ( Vec String ) texts i cap i score s text → v {
    : i n ( vec_len [i] scores )
    : ~ i pos n
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] scores k ) {
            T sv → { ? & == pos n > score sv { = pos k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ? | < n cap < pos cap {
        ( vec_insert [i] scores pos score )
        ( vec_insert [String] texts pos ( string_from text ) )
        ? > ( vec_len [i] scores ) cap {
            ( vec_remove [i] scores cap )
            ?? ( vec_remove [String] texts cap ) { T old → ( string_free old ) F _ → {} }
        } {}
    } {}
}

// Score one rendered module's declaration blocks against the OR terms
// and offer each hit to the top-K. ctr = [matched].
@ __ms_or_match_blocks String md s rel ( Vec String ) terms i nterms ( Vec i ) scores ( Vec String ) texts ( Vec i ) ctr ( Vec i ) stats → v {
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
                // The signature haystack: module path + the block's first
                // line, which nurldoc renders as the declaration itself.
                : String sig ( string_with_cap 160 )
                ( string_push_str sig rel )
                ( string_push_char sig 32 )
                : s braw ( string_data blk )
                : i bl ( string_len blk )
                : ~ i si 0
                ~ & < si bl != ( nurl_str_get braw si ) 10 {
                    ( string_push_char sig ( nurl_str_get braw si ) )
                    = si + si 1
                }
                : String sig_lc ( string_to_lower sig )
                ( string_free sig )
                : i sc ( __ms_or_score2 ( string_data sig_lc ) ( string_data hay_lc ) terms stats )
                ( string_free sig_lc )
                ( string_free hay_lc )
                ? > sc 0 {
                    : i m ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
                    ( vec_set [i] ctr 0 + m 1 )
                    : String snip ( string_with_cap 640 )
                    ( string_push_str snip rel )
                    ( string_push_str snip ` [` )
                    ( string_push_int snip ?? ( vec_get [i] stats 0 ) { T v → v F _ → 0 } )
                    ( string_push_char snip 47 )
                    ( string_push_int snip nterms )
                    ( string_push_str snip ` terms] › ` )
                    : i bn ( string_len blk )
                    : i keep ? > bn 500 500 bn
                    : s raw ( string_data blk )
                    : ~ i j 0
                    ~ < j keep {
                        ( string_push_char snip ( nurl_str_get raw j ) )
                        = j + j 1
                    }
                    ? > bn keep { ( string_push_str snip `…` ) } {}
                    ( __ms_topk_push scores texts ( __ms_api_or_cap ) sc ( string_data snip ) )
                    ( string_free snip )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] parts \ String p → v { ( string_free p ) } )
}

// Run the OR pass over every module under stdlib_dir, append the ranked
// hits to `out`, and return how many declarations matched at least one
// term (0 ⇒ nothing found; the caller falls through to the corpus
// widening exactly as before).
@ __ms_api_or_widen s stdlib_dir ( Vec String ) terms String out → i {
    : i nterms ( __ms_or_usable_terms terms )
    ? < nterms 2 { ^ 0 } {}
    : ( Vec i ) scores ( vec_new [i] )
    : ( Vec String ) texts ( vec_new [String] )
    : ( Vec i ) ctr ( vec_new [i] )
    ( vec_push [i] ctr 0 )
    : ( Vec i ) stats ( vec_new [i] )
    ( vec_push [i] stats 0 )
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
                    : String fp ( path_join ( string_data dir ) rel )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                    ( string_free fp )
                    ?? rd {
                        T bytes → {
                            : String src ( bytes_to_str bytes )
                            ( vec_free [u] bytes )
                            // Same raw-source pre-filter as the AND pass,
                            // ORed: render only modules that can contribute.
                            : String pre ( string_with_cap + ( string_len src ) 64 )
                            ( string_push_str pre rel )
                            ( string_push_char pre 32 )
                            ( string_push_str pre ( string_data src ) )
                            : String pre_lc ( string_to_lower pre )
                            ( string_free pre )
                            ? > ( __ms_or_score2 `` ( string_data pre_lc ) terms stats ) 0 {
                                : String md ( nurldoc_render ( string_data src ) rel )
                                ( __ms_or_match_blocks md rel terms nterms scores texts ctr stats )
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
    : i shown ( vec_len [String] texts )
    ? > shown 0 {
        ( string_push_str out `No declaration contains every term. Nearest declarations matching ANY term as a whole word, ranked by how much of the query they cover — a longer, more specific term counts for more than a short common one, and a term in the declaration's own name counts for more than one in its prose:\n\n` )
        : ~ i j 0
        ~ < j shown {
            ?? ( vec_get [String] texts j ) {
                T t → {
                    ( string_push_str out ( string_data t ) )
                    ( string_push_str out `\n\n` )
                }
                F _ → {}
            }
            = j + j 1
        }
        ? > matched shown {
            ( string_push_str out `(` )
            ( string_push_int out matched )
            ( string_push_str out ` declarations match at least one term; the ` )
            ( string_push_int out shown )
            ( string_push_str out ` with the best coverage are above. Search one of the terms alone for the rest, or read a module with 'module'.)\n` )
        } {}
    } {}
    ( vec_free [i] scores )
    ( vec_free [i] ctr )
    ( vec_free [i] stats )
    ( vec_free_with [String] texts \ String t → v { ( string_free t ) } )
    ^ matched
}

// Does `td` (a lowercase query term) exactly name the module whose
// lowercase relative path is rel_lc? Accepted spellings: the full path
// ('ext/csv.nu'), the path without '.nu' ('ext/csv'), the basename
// ('csv.nu'), and the bare stem ('csv').
@ __ms_term_names_module s td String rel_lc String stem String base String bstem → b {
    ? != 0 ( nurl_str_eq td ( string_data rel_lc ) ) { ^ T } {}
    ? != 0 ( nurl_str_eq td ( string_data stem ) ) { ^ T } {}
    ? != 0 ( nurl_str_eq td ( string_data base ) ) { ^ T } {}
    ? != 0 ( nurl_str_eq td ( string_data bstem ) ) { ^ T } {}
    ^ F
}

// The exact-module pass a 0-hit query earns BEFORE any fuzzy widening:
// each term is compared against every stdlib module's name (the
// spellings __ms_term_names_module accepts). An agent that queries
// "csv json string" wants ext/csv.nu's API surface, not an OR-ranked
// declaration list. Modules are emitted WHOLE or not at all — a partial
// module reads as the complete one, and an agent must never conclude a
// function is missing because a byte cap cut it off. What the cap
// excludes is listed by name for a follow-up module= call, and terms
// that named NO module are listed as not-searched-here so their
// concepts don't silently vanish from the reply. Returns how many
// modules a term named (0 ⇒ the caller falls through to the OR pass
// as before).
@ __ms_api_exact_modules s stdlib_dir ( Vec String ) terms String out → i {
    : Json files ( json_arr_new )
    ( msearch_walk_nu_files files stdlib_dir `` )
    : i nf ( json_arr_len files )
    : i tn ( vec_len [String] terms )
    : ( Vec String ) rels ( vec_new [String] )
    : ( Vec String ) hits ( vec_new [String] )
    : ( Vec String ) misses ( vec_new [String] )
    // Terms outer, files inner: the reply lists modules in QUERY order
    // ("csv json …" leads with ext/csv.nu), deduplicated by rel path.
    : ~ i tk 0
    ~ < tk tn {
        ?? ( vec_get [String] terms tk ) {
            T t → {
                ? > ( string_len t ) 0 {
                    : ~ b tmatched F
                    : ~ i k 0
                    ~ < k nf {
                        ?? ( json_arr_get files k ) {
                            T fo → {
                                : ~ s rel ``
                                ?? ( json_obj_get fo `path` ) {
                                    T pj → { ? ( json_is_str pj ) { = rel ( json_as_str pj ) } {} }
                                    F _ → {}
                                }
                                ? > ( nurl_str_len rel ) 3 {
                                    : String rel_lc ( __ms_lc rel )
                                    : String stem ( string_substr rel_lc 0 - ( string_len rel_lc ) 3 )
                                    : String base ( __ms_basename ( string_data rel_lc ) )
                                    : String bstem ( string_substr base 0 - ( string_len base ) 3 )
                                    ? ( __ms_term_names_module ( string_data t ) rel_lc stem base bstem ) {
                                        = tmatched T
                                        ? ! ( __ms_has_str rels rel ) {
                                            ( vec_push [String] rels ( string_from rel ) )
                                            ( vec_push [String] hits ( string_from ( string_data t ) ) )
                                        } {}
                                    } {}
                                    ( string_free bstem )
                                    ( string_free base )
                                    ( string_free stem )
                                    ( string_free rel_lc )
                                } {}
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ? ! tmatched { ( vec_push [String] misses ( string_from ( string_data t ) ) ) } {}
                } {}
            }
            F _ → {}
        }
        = tk + tk 1
    }
    ( json_free files )

    : i n ( vec_len [String] rels )
    : i cap ( __ms_api_out_cap )
    : i base_len ( string_len out )
    ? > n 0 {
        ? == n 1 {
            ( string_push_str out `No declaration contains every term, but a term names a stdlib module exactly — its whole API surface:\n\n` )
        } {
            ( string_push_str out `No declaration contains every term, but ` )
            ( string_push_int out n )
            ( string_push_str out ` terms name stdlib modules exactly — their API surfaces:\n\n` )
        }
        // Whole modules only. A surface that would overflow the cap is
        // deferred to a one-line module= pointer instead of being cut
        // mid-module — a partial surface reads as the complete one.
        : String defer ( string_with_cap 256 )
        : ~ i j 0
        ~ < j n {
            : ~ s relj ``
            ?? ( vec_get [String] rels j ) { T r → = relj ( string_data r ) F _ → {} }
            : ~ s tj ``
            ?? ( vec_get [String] hits j ) { T h → = tj ( string_data h ) F _ → {} }
            ? > ( nurl_str_len relj ) 0 {
                : String md ( __ms_api_render_module stdlib_dir relj )
                : i add + ( string_len md ) + ( nurl_str_len relj ) 64
                ? & > ( string_len md ) 0 >= cap + - ( string_len out ) base_len add {
                    ( string_push_str out `── ` )
                    ( string_push_str out relj )
                    ( string_push_str out ` (term '` )
                    ( string_push_str out tj )
                    ( string_push_str out `') ──\n` )
                    ( string_push_str out ( string_data md ) )
                    ( string_push_char out 10 )
                } {
                    ( string_push_str defer `  ` )
                    ( string_push_str defer relj )
                    ( string_push_str defer ` (term '` )
                    ( string_push_str defer tj )
                    ( string_push_str defer `') — read it with module='` )
                    ( string_push_str defer relj )
                    ( string_push_str defer `'.\n` )
                }
                ( string_free md )
            } {}
            = j + j 1
        }
        ? > ( string_len defer ) 0 {
            ( string_push_str out `Named by a term but did not fit in this reply — each is one module= call:\n` )
            ( string_push_str out ( string_data defer ) )
            ( string_push_char out 10 )
        } {}
        ( string_free defer )
        // Every remaining term was NOT searched here. Say so, or an
        // agent reads "vec sort string split lowercase contains" coming
        // back without lowercase as "lowercase does not exist".
        : i nm ( vec_len [String] misses )
        ? > nm 0 {
            ( string_push_str out `NOT searched in this reply: ` )
            : ~ i mi 0
            ~ < mi nm {
                ?? ( vec_get [String] misses mi ) {
                    T m → {
                        ? > mi 0 { ( string_push_str out `, ` ) } {}
                        ( string_push_char out 39 )
                        ( string_push_str out ( string_data m ) )
                        ( string_push_char out 39 )
                    }
                    F _ → {}
                }
                = mi + mi 1
            }
            ( string_push_str out ` — these name no module, and this reply answered only the module-name terms. What they describe may well exist (likely inside the modules above); query each concept separately, e.g. query='string lowercase'.\n` )
        } {}
    } {}
    ( vec_free_with [String] rels \ String r → v { ( string_free r ) } )
    ( vec_free_with [String] hits \ String h → v { ( string_free h ) } )
    ( vec_free_with [String] misses \ String m → v { ( string_free m ) } )
    ^ n
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

// Declaration search over every module under stdlib_dir; terms are the
// query split on spaces and commas. Zero hits first try each term as an
// exact stdlib module NAME ('csv' → ext/csv.nu's API surface), then the
// whole-word OR pass, then widen to examples_dir ("" skips) and the
// registry (regbase "" skips); an exact package-name term is footnoted
// regardless of hit count. Returns the COMPLETE reply text.
@ msearch_api_query s stdlib_dir s examples_dir s regbase s query → String {
    : String q_lc ( __ms_lc query )
    // Agents separate terms with commas about as often as with spaces
    // ("csv,json") — treat both as term boundaries.
    : String q_norm ( string_replace q_lc `,` ` ` )
    : ( Vec String ) terms ( string_split q_norm ` ` )
    ( string_free q_norm )
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
    // `widened` = the corpus fallback ran and already listed registry
    // matches in full, so the one-line exact-name footer would repeat it.
    : ~ b widened F
    ? == matched 0 {
        // A term that exactly NAMES a stdlib module wins before any
        // fuzzy widening: "csv json string" means ext/csv.nu's API
        // surface, not an OR-ranked declaration list.
        : i nm_n ( __ms_api_exact_modules stdlib_dir terms hdr )
        ? == nm_n 0 {
            // Widen the OPERATOR next: the same terms ORed, whole-word,
            // ranked by coverage. A multi-term concept query ("string builder
            // append") lands on real declarations here, and when it does the
            // corpus fallback stays out of the reply — the point of the pass
            // is fewer, better hits, not more of them.
            : i or_n ( __ms_api_or_widen stdlib_dir terms hdr )
            ? == or_n 0 {
                // Widen rather than shrug: the same terms against example files
                // and the package registry, in the same reply.
                = widened T
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
        } {}
    } {}
    ? > matched emitted {
        ( string_push_str hdr `… ` )
        ( string_push_int hdr - matched emitted )
        ( string_push_str hdr ` more matching declarations omitted (byte cap) — narrow the query or read one module with 'module'.\n` )
    } {}
    // An exact package-name hit still deserves its one-line footer.
    ? & ! widened > ( nurl_str_len regbase ) 0 { ( __ms_api_exact_pkg_note regbase terms hdr ) } {}
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

// ── Registry package API surface (item: nurl_api package=<name>) ───────

// <regbase>/pkgs/<name>/<name>-<version>.tar.gz
@ __ms_tarball_url s regbase s name s version → String {
    : String u ( string_with_cap 160 )
    ( string_push_str u regbase )
    ? != ( string_get u - ( string_len u ) 1 ) 47 { ( string_push_char u 47 ) } {}
    ( string_push_str u `pkgs/` )
    ( string_push_str u name )
    ( string_push_char u 47 )
    ( string_push_str u name )
    ( string_push_char u 45 )
    ( string_push_str u version )
    ( string_push_str u `.tar.gz` )
    ^ u
}

// The newest non-yanked version from /index/<name>.json, or "" when the
// package is unknown / the index is unreachable.
@ __ms_latest_version s regbase s name → String {
    : String u ( string_with_cap 128 )
    ( string_push_str u regbase )
    ? != ( string_get u - ( string_len u ) 1 ) 47 { ( string_push_char u 47 ) } {}
    ( string_push_str u `index/` )
    ( string_push_str u name )
    ( string_push_str u `.json` )
    : ~ String out ( string_new )
    : !Response HttpErr r ( http_get ( string_data u ) )
    ( string_free u )
    ?? r {
        T resp → {
            ?? ( json_parse ( http_body_str resp ) ) {
                T root → {
                    ?? ( json_obj_get root `versions` ) {
                        T arr → {
                            : i n ( json_arr_len arr )
                            : ~ i k 0
                            ~ < k n {
                                ?? ( json_arr_get arr k ) {
                                    T o → {
                                        : ~ b yanked F
                                        ?? ( json_obj_get o `yanked` ) { T yj → { ? ( json_is_bool yj ) { = yanked ( json_as_bool yj ) } {} } F → {} }
                                        ? yanked {} {
                                            ?? ( json_obj_get o `version` ) {
                                                T vj → { ? ( json_is_str vj ) { ( string_free out ) = out ( string_from ( json_as_str vj ) ) } {} }
                                                F → {}
                                            }
                                        }
                                    }
                                    F → {}
                                }
                                = k + k 1
                            }
                        }
                        F → {}
                    }
                    ( json_free root )
                }
                F → {}
            }
            ( response_free resp )
        }
        F → {}
    }
    ^ out
}

// The API surface (nurldoc over every src/*.nu) of a PUBLISHED package,
// streamed from its registry tarball — the ecosystem counterpart of
// msearch_api_module. `version` "" resolves to the latest. "" on failure.
@ msearch_api_package s regbase s name s version → String {
    : ~ String ver ( string_from version )
    ? == ( string_len ver ) 0 {
        ( string_free ver )
        = ver ( __ms_latest_version regbase name )
    } {}
    ? == ( string_len ver ) 0 { ( string_free ver ) ^ ( string_new ) } {}
    : String url ( __ms_tarball_url regbase name ( string_data ver ) )
    : ~ String md ( string_new )
    : !Response HttpErr r ( http_get ( string_data url ) )
    ( string_free url )
    ?? r {
        T resp → {
            ? == ( http_status resp ) 200 {
                : ( Vec u ) gz ( http_body_bytes resp )
                ?? ( gzip_decompress gz ) {
                    T raw → {
                        ?? ( tar_parse raw ) {
                            T ents → {
                                : String hdr ( string_with_cap 64 )
                                ( string_push_str hdr name )
                                ( string_push_char hdr 32 )
                                ( string_push_str hdr ( string_data ver ) )
                                ( string_push_str hdr ` — package API surface (published src/*.nu)\n` )
                                ( string_push_str md ( string_data hdr ) )
                                ( string_free hdr )
                                : i n ( vec_len [TarEntry] ents )
                                : ~ i k 0
                                ~ < k n {
                                    ?? ( vec_get [TarEntry] ents k ) {
                                        T e → {
                                            ? == . e typeflag 48 {
                                                : ~ String pnorm ( string_from ( string_data . e path ) )
                                                ? ( string_starts_with pnorm `./` ) {
                                                    : String c2 ( string_substr pnorm 2 - ( string_len pnorm ) 2 )
                                                    ( string_free pnorm )
                                                    = pnorm c2
                                                } {}
                                                ? & ( string_starts_with pnorm `src/` ) ( string_ends_with pnorm `.nu` ) {
                                                    : String content ( bytes_to_str . e data )
                                                    : String base ( __ms_basename ( string_data pnorm ) )
                                                    : String one ( nurldoc_render ( string_data content ) ( string_data base ) )
                                                    ( string_push_str md `\n---\n\n` )
                                                    ( string_push_str md ( string_data one ) )
                                                    ( string_free one ) ( string_free content ) ( string_free base )
                                                } {}
                                                ( string_free pnorm )
                                            } {}
                                        }
                                        F → {}
                                    }
                                    = k + k 1
                                }
                                ( tar_entries_free ents )
                            }
                            F → {}
                        }
                        ( vec_free [u] raw )
                    }
                    F → {}
                }
                ( vec_free [u] gz )
            } {}
            ( response_free resp )
        }
        F → {}
    }
    ( string_free ver )
    ? > ( string_len md ) ( __ms_api_out_cap ) {
        : String cut ( string_substr md 0 ( __ms_api_out_cap ) )
        ( string_push_str cut `\n… truncated — fetch the tarball for the full source.\n` )
        ( string_free md )
        ^ cut
    } {}
    ^ md
}

// ── Documentation corpus (item: nurl_docs) ─────────────────────────
//
// docs/ is the prose the API surface cannot answer: MEMORY.md (who owns
// what, and when it is freed), CRYPTO.md (which cipher suites ship),
// GOTCHAS.md, spec.md, … An agent that can only reach nurl_api ends up
// guessing at exactly the questions these files answer, so both servers
// expose the tree as one tool: no `name` lists what exists, a `name`
// returns that document verbatim.

// Byte budget for one document. spec.md (63 KB) and MEMORY.md (45 KB)
// are the outliers; the rest fit whole. `offset` pages past the cut.
@ __ms_docs_cap → i { ^ 49152 }

// A document's `# ` title, "" when the file has none in its first few
// lines. Used as the one-line blurb in the listing.
@ __ms_docs_title String src → String {
    : s raw ( string_data src )
    : i n ( string_len src )
    : ~ i k 0
    : ~ i lines 0
    : String t ( string_new )
    ~ & & < k n < lines 8 == ( string_len t ) 0 {
        : ~ i e k
        ~ & < e n != ( nurl_str_get raw e ) 10 { = e + e 1 }
        // "# Title" — one hash, then the text after the spaces.
        ? & & < + k 1 e == ( nurl_str_get raw k ) 35 != ( nurl_str_get raw + k 1 ) 35 {
            : ~ i b + k 1
            ~ & < b e == ( nurl_str_get raw b ) 32 { = b + b 1 }
            : ~ i j b
            ~ & < j e < - j b 110 {
                ( string_push_char t ( nurl_str_get raw j ) )
                = j + j 1
            }
            ? > - e b 110 { ( string_push_str t `…` ) } {}
        } {}
        = k + e 1
        = lines + lines 1
    }
    ^ t
}

// Strip the decoration a model is likely to type around a doc name:
// a leading "./", "/" or "docs/", and a trailing "/". Lowercased, so
// callers compare case-insensitively. "" when `name` escapes the tree.
@ __ms_docs_norm s name → String {
    : ~ String w ( __ms_lc name )
    ? >= ( nurl_str_find ( string_data w ) `..` ) 0 {
        ( string_free w )
        ^ ( string_new )
    } {}
    : ~ b more T
    ~ more {
        = more F
        ? ( string_starts_with w `/` ) {
            : String c1 ( string_substr w 1 - ( string_len w ) 1 )
            ( string_free w ) = w c1 = more T
        } {}
        ? ( string_starts_with w `./` ) {
            : String c2 ( string_substr w 2 - ( string_len w ) 2 )
            ( string_free w ) = w c2 = more T
        } {}
        ? ( string_starts_with w `docs/` ) {
            : String c3 ( string_substr w 5 - ( string_len w ) 5 )
            ( string_free w ) = w c3 = more T
        } {}
    }
    ~ ( string_ends_with w `/` ) {
        : String c4 ( string_substr w 0 - ( string_len w ) 1 )
        ( string_free w ) = w c4
    }
    ^ w
}

// How well `rel` (a path under docs/) answers a request for `want`
// (already normalised + lowercased): 1 exact, 2 exact minus the .md
// suffix, 3 basename, 4 basename minus .md, 0 no match. Lower wins, so
// name='MEMORY' and name='docs/memory.md' both land on MEMORY.md while
// a request that names a directory does not silently match a file.
@ __ms_docs_rank s rel s want → i {
    : String rl ( __ms_lc rel )
    : String base ( __ms_basename ( string_data rl ) )
    : ~ String rl_stem ( string_from ( string_data rl ) )
    ? ( string_ends_with rl_stem `.md` ) {
        : String cut ( string_substr rl_stem 0 - ( string_len rl_stem ) 3 )
        ( string_free rl_stem )
        = rl_stem cut
    } {}
    : ~ String base_stem ( string_from ( string_data base ) )
    ? ( string_ends_with base_stem `.md` ) {
        : String cut2 ( string_substr base_stem 0 - ( string_len base_stem ) 3 )
        ( string_free base_stem )
        = base_stem cut2
    } {}
    : ~ i rank 0
    ? != 0 ( nurl_str_eq ( string_data rl ) want ) { = rank 1 } {}
    ? & == rank 0 != 0 ( nurl_str_eq ( string_data rl_stem ) want ) { = rank 2 } {}
    ? & == rank 0 != 0 ( nurl_str_eq ( string_data base ) want ) { = rank 3 } {}
    ? & == rank 0 != 0 ( nurl_str_eq ( string_data base_stem ) want ) { = rank 4 } {}
    ( string_free rl ) ( string_free base )
    ( string_free rl_stem ) ( string_free base_stem )
    ^ rank
}

// Resolve a requested document to its path relative to docs_dir; ""
// when nothing matches (or the name tried to escape the tree).
@ msearch_docs_resolve s docs_dir s name → String {
    : String want ( __ms_docs_norm name )
    : ~ String best ( string_new )
    ? == ( string_len want ) 0 {
        ( string_free want )
        ^ best
    } {}
    : Json files ( json_arr_new )
    ( msearch_walk_md_files files docs_dir `` )
    : i nf ( json_arr_len files )
    : ~ i best_rank 0
    : ~ i k 0
    ~ < k nf {
        ?? ( json_arr_get files k ) {
            T fo → {
                ?? ( json_obj_get fo `path` ) {
                    T pj → {
                        ? ( json_is_str pj ) {
                            : s rel ( json_as_str pj )
                            : i rank ( __ms_docs_rank rel ( string_data want ) )
                            ? & > rank 0 | == best_rank 0 < rank best_rank {
                                = best_rank rank
                                ( string_free best )
                                = best ( string_from rel )
                            } {}
                        } {}
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_free files )
    ( string_free want )
    ^ best
}

// The listing an agent gets when it calls nurl_docs with no `name`:
// every document under docs_dir with its size and title.
@ msearch_docs_list s docs_dir → String {
    : Json files ( json_arr_new )
    ( msearch_walk_md_files files docs_dir `` )
    : i nf ( json_arr_len files )
    : String out ( string_with_cap 2048 )
    ( string_push_int out nf )
    ( string_push_str out ` document(s) under docs/ — pass 'name' to read one (e.g. name='MEMORY.md').\n\n` )
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
                    ( string_push_str out `  ` )
                    ( string_push_str out rel )
                    // Pad to a column so the sizes line up.
                    : ~ i pad ( nurl_str_len rel )
                    ~ < pad 30 { ( string_push_char out 32 ) = pad + pad 1 }
                    ?? ( json_obj_get fo `bytes` ) {
                        T bj → {
                            ( string_push_char out 32 )
                            ( string_push_int out / ( json_as_int bj ) 1024 )
                            ( string_push_str out ` KB` )
                        }
                        F _ → {}
                    }
                    : String fp ( path_join docs_dir rel )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                    ( string_free fp )
                    ?? rd {
                        T bytes → {
                            : String src ( bytes_to_str bytes )
                            ( vec_free [u] bytes )
                            : String t ( __ms_docs_title src )
                            ? > ( string_len t ) 0 {
                                ( string_push_str out ` — ` )
                                ( string_push_str out ( string_data t ) )
                            } {}
                            ( string_free t )
                            ( string_free src )
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
    ( json_free files )
    ? == nf 0 {
        ( string_push_str out `(no .md files under the configured docs directory)\n` )
    } {}
    ^ out
}

// One document, from byte `offset`, capped. "" when `name` resolves to
// nothing — the caller turns that into an error listing what exists.
// ── Documents by section ───────────────────────────────────────────
//
// Whole-document reads answer "what does this cover"; they are a bad
// way to answer "who frees a String?". MEMORY.md is 44 KB and spec.md
// is 63 KB — past the per-call cap, so the whole-file path cannot even
// return it in one call. Both files are already carved into ATX
// headings, and the question a model actually has almost always maps
// to one of them. So: index the headings, and let a caller name a
// section, ask for the outline, or search every section at once.
//
// A section runs from its heading to the next heading of the SAME OR
// HIGHER level, so asking for `## 2. The borrow checker` yields its
// `###` subsections too, while asking for `### 2.1` yields just that.

// Count the leading '#' of an ATX heading line at `off`; 0 if the line
// is not a heading. A '#' must be followed by a space to count, so a
// `#define` inside a fenced code block is not mistaken for one.
@ __ms_heading_level s raw i n i off → i {
    : ~ i k off
    ~ & < k n == ( nurl_str_get raw k ) 35 { = k + k 1 }
    : i lvl - k off
    ? == lvl 0 { ^ 0 } {}
    ? >= k n { ^ 0 } {}
    ? != ( nurl_str_get raw k ) 32 { ^ 0 } {}
    ^ lvl
}

// Index every heading in `src`: byte offset of the line, its level, and
// its title text. Lines inside ``` fences are skipped — a Markdown
// document about a prefix language is full of `# comment` lines that
// are code, not structure.
@ __ms_doc_headings String src ( Vec i ) starts ( Vec i ) levels ( Vec String ) titles → v {
    : s raw ( string_data src )
    : i n ( string_len src )
    : ~ i k 0
    : ~ b fenced F
    ~ < k n {
        : ~ i e k
        ~ & < e n != ( nurl_str_get raw e ) 10 { = e + e 1 }
        // Fence toggle: a line whose first three bytes are ```.
        ? & <= + k 3 e & & == ( nurl_str_get raw k ) 96 == ( nurl_str_get raw + k 1 ) 96 == ( nurl_str_get raw + k 2 ) 96 {
            = fenced ! fenced
        } {
            ? ! fenced {
                : i lvl ( __ms_heading_level raw n k )
                ? > lvl 0 {
                    ( vec_push [i] starts k )
                    ( vec_push [i] levels lvl )
                    : String t ( string_with_cap 96 )
                    : ~ i j + k + lvl 1
                    ~ < j e {
                        ( string_push_char t ( nurl_str_get raw j ) )
                        = j + j 1
                    }
                    ( vec_push [String] titles t )
                } {}
            } {}
        }
        = k + e 1
    }
}

// Where heading `idx`'s prose ends, ignoring hierarchy: the very next
// heading, whatever its level. This is the unit SEARCH works on. The
// hierarchical rule below is wrong for search: a document's H1 has no
// same-or-higher sibling, so its "section" is the entire file — it then
// contains every term, outscores every real subsection, and the query
// path hands back the whole 44 KB document it was meant to replace.
// Retrieval still wants the hierarchy (asking for §2 should include
// §2.1), so the two rules stay separate on purpose.
@ __ms_section_end_flat ( Vec i ) starts i idx i n_src → i {
    : i nh ( vec_len [i] starts )
    ? >= + idx 1 nh { ^ n_src } {}
    ^ ?? ( vec_get [i] starts + idx 1 ) { T v → v F _ → n_src }
}

// Where the section owning heading `idx` ends: the next heading whose
// level is <= this one, or EOF.
@ __ms_section_end ( Vec i ) starts ( Vec i ) levels i idx i n_src → i {
    : i nh ( vec_len [i] starts )
    : i lvl ?? ( vec_get [i] levels idx ) { T v → v F _ → 1 }
    : ~ i k + idx 1
    ~ < k nh {
        : i l2 ?? ( vec_get [i] levels k ) { T v → v F _ → 1 }
        ? <= l2 lvl {
            ^ ?? ( vec_get [i] starts k ) { T v → v F _ → n_src }
        } {}
        = k + k 1
    }
    ^ n_src
}

// Does heading `title` answer to `want`? Either the title's leading
// number token matches exactly ("7.4", "2"), or `want` occurs in the
// title case-insensitively. The number form is what a table of
// contents gives a model; the text form is what it guesses.
@ __ms_section_matches String title s want → b {
    : String tl ( string_to_lower title )
    : s t ( string_data tl )
    : i tn ( string_len tl )
    // Leading number token, e.g. "2.1 move checking" → "2.1".
    : ~ i e 0
    ~ & < e tn | & >= ( nurl_str_get t e ) 48 <= ( nurl_str_get t e ) 57 == ( nurl_str_get t e ) 46 { = e + e 1 }
    : ~ b hit F
    ? > e 0 {
        : String num ( string_substr tl 0 e )
        // Trailing '.' is decoration in "2." — compare without it.
        : ~ String num2 ( string_from ( string_data num ) )
        ? & > ( string_len num2 ) 0 == ( string_get num2 - ( string_len num2 ) 1 ) 46 {
            : String cut ( string_substr num2 0 - ( string_len num2 ) 1 )
            ( string_free num2 )
            = num2 cut
        } {}
        ? != 0 ( nurl_str_eq ( string_data num2 ) want ) { = hit T } {}
        ? != 0 ( nurl_str_eq ( string_data num ) want ) { = hit T } {}
        ( string_free num ) ( string_free num2 )
    } {}
    ? ! hit {
        : String w ( __ms_lc want )
        ? >= ( nurl_str_find t ( string_data w ) ) 0 { = hit T } {}
        ( string_free w )
    } {}
    ( string_free tl )
    ^ hit
}

// The heading list of one document — what a model reads to find out
// which section to ask for, at a fraction of the document's bytes.
@ msearch_docs_outline s docs_dir s name → String {
    : String rel ( msearch_docs_resolve docs_dir name )
    : String out ( string_with_cap 2048 )
    ? == ( string_len rel ) 0 {
        ( string_free rel )
        ^ out
    } {}
    : String fp ( path_join docs_dir ( string_data rel ) )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free fp )
    ?? rd {
        T bytes → {
            : String src ( bytes_to_str bytes )
            ( vec_free [u] bytes )
            : ( Vec i ) starts ( vec_new [i] )
            : ( Vec i ) levels ( vec_new [i] )
            : ( Vec String ) titles ( vec_new [String] )
            ( __ms_doc_headings src starts levels titles )
            : i nh ( vec_len [i] starts )
            ( string_push_str out `docs/` )
            ( string_push_str out ( string_data rel ) )
            ( string_push_str out ` — ` )
            ( string_push_int out ( string_len src ) )
            ( string_push_str out ` bytes, ` )
            ( string_push_int out nh )
            ( string_push_str out ` sections. Ask for one with section='<number or words>'.\n\n` )
            : ~ i k 0
            ~ < k nh {
                : i lvl ?? ( vec_get [i] levels k ) { T v → v F _ → 1 }
                : ~ i pad 1
                ~ < pad lvl { ( string_push_str out `  ` ) = pad + pad 1 }
                ( string_push_str out `- ` )
                ?? ( vec_get [String] titles k ) {
                    T t → ( string_push_str out ( string_data t ) )
                    F _ → {}
                }
                : i s0 ?? ( vec_get [i] starts k ) { T v → v F _ → 0 }
                : i e0 ( __ms_section_end starts levels k ( string_len src ) )
                ( string_push_str out `  (` )
                ( string_push_int out - e0 s0 )
                ( string_push_str out ` B)\n` )
                = k + k 1
            }
            ( vec_free [i] starts ) ( vec_free [i] levels )
            ( vec_free_with [String] titles \ String t → v { ( string_free t ) } )
            ( string_free src )
        }
        F _ → {}
    }
    ( string_free rel )
    ^ out
}

// One named section of one document, "" when the document or the
// section is not found. On a miss the caller shows the outline.
@ msearch_docs_section s docs_dir s name s section → String {
    : String rel ( msearch_docs_resolve docs_dir name )
    : String out ( string_with_cap 4096 )
    ? == ( string_len rel ) 0 {
        ( string_free rel )
        ^ out
    } {}
    : String fp ( path_join docs_dir ( string_data rel ) )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free fp )
    ?? rd {
        T bytes → {
            : String src ( bytes_to_str bytes )
            ( vec_free [u] bytes )
            : ( Vec i ) starts ( vec_new [i] )
            : ( Vec i ) levels ( vec_new [i] )
            : ( Vec String ) titles ( vec_new [String] )
            ( __ms_doc_headings src starts levels titles )
            : i nh ( vec_len [i] starts )
            : ~ i found -1
            : ~ i k 0
            ~ < k nh {
                ? < found 0 {
                    ?? ( vec_get [String] titles k ) {
                        T t → { ? ( __ms_section_matches t section ) { = found k } {} }
                        F _ → {}
                    }
                } {}
                = k + k 1
            }
            ? >= found 0 {
                : i s0 ?? ( vec_get [i] starts found ) { T v → v F _ → 0 }
                : i e0 ( __ms_section_end starts levels found ( string_len src ) )
                ( string_push_str out `docs/` )
                ( string_push_str out ( string_data rel ) )
                ( string_push_str out ` › ` )
                ?? ( vec_get [String] titles found ) {
                    T t → ( string_push_str out ( string_data t ) )
                    F _ → {}
                }
                ( string_push_str out `\n\n` )
                : i want - e0 s0
                : i keep ? > want ( __ms_docs_cap ) ( __ms_docs_cap ) want
                : String slice ( string_substr src s0 keep )
                ( string_push_str out ( string_data slice ) )
                ( string_free slice )
                ? > want keep {
                    ( string_push_str out `\n… section truncated — read the whole file with offset=` )
                    ( string_push_int out + s0 keep )
                    ( string_push_char out 10 )
                } {}
            } {}
            ( vec_free [i] starts ) ( vec_free [i] levels )
            ( vec_free_with [String] titles \ String t → v { ( string_free t ) } )
            ( string_free src )
        }
        F _ → {}
    }
    ( string_free rel )
    ^ out
}

// Search every section of every document. Terms are matched as whole
// words and ranked by coverage — the same scorer nurl_api's OR pass
// uses, with the heading as the "signature" haystack, so a section
// titled "Move checking" outranks one that merely mentions moves.
// Returns the reply text; `hits` (≥1 element) receives the count.
@ msearch_docs_query s docs_dir s query ( Vec i ) hits → String {
    : String q_lc ( __ms_lc query )
    : ( Vec String ) terms ( string_split q_lc ` ` )
    : ( Vec i ) scores ( vec_new [i] )
    : ( Vec String ) texts ( vec_new [String] )
    : ( Vec i ) stats ( vec_new [i] )
    ( vec_push [i] stats 0 )
    : ~ i matched 0
    : Json files ( json_arr_new )
    ( msearch_walk_md_files files docs_dir `` )
    : i nf ( json_arr_len files )
    : ~ i fi 0
    ~ < fi nf {
        ?? ( json_arr_get files fi ) {
            T fo → {
                : ~ s rel ``
                ?? ( json_obj_get fo `path` ) {
                    T pj → { ? ( json_is_str pj ) { = rel ( json_as_str pj ) } {} }
                    F _ → {}
                }
                ? > ( nurl_str_len rel ) 0 {
                    : String fp ( path_join docs_dir rel )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                    ( string_free fp )
                    ?? rd {
                        T bytes → {
                            : String src ( bytes_to_str bytes )
                            ( vec_free [u] bytes )
                            : ( Vec i ) starts ( vec_new [i] )
                            : ( Vec i ) levels ( vec_new [i] )
                            : ( Vec String ) titles ( vec_new [String] )
                            ( __ms_doc_headings src starts levels titles )
                            : i nh ( vec_len [i] starts )
                            : ~ i k 0
                            ~ < k nh {
                                : i s0 ?? ( vec_get [i] starts k ) { T v → v F _ → 0 }
                                : i e0 ( __ms_section_end_flat starts k ( string_len src ) )
                                : String body ( string_substr src s0 - e0 s0 )
                                : String body_lc ( string_to_lower body )
                                : String sig ( string_with_cap 128 )
                                ( string_push_str sig rel )
                                ( string_push_char sig 32 )
                                ?? ( vec_get [String] titles k ) {
                                    T t → ( string_push_str sig ( string_data t ) )
                                    F _ → {}
                                }
                                : String sig_lc ( string_to_lower sig )
                                ( string_free sig )
                                : i sc ( __ms_or_score2 ( string_data sig_lc ) ( string_data body_lc ) terms stats )
                                ( string_free sig_lc ) ( string_free body_lc )
                                ? > sc 0 {
                                    = matched + matched 1
                                    : String snip ( string_with_cap 1200 )
                                    ( string_push_str snip `docs/` )
                                    ( string_push_str snip rel )
                                    ( string_push_str snip ` › ` )
                                    ?? ( vec_get [String] titles k ) {
                                        T t → ( string_push_str snip ( string_data t ) )
                                        F _ → {}
                                    }
                                    ( string_push_str snip `  [section=` )
                                    ?? ( vec_get [String] titles k ) {
                                        T t → ( __ms_push_section_key snip t )
                                        F _ → {}
                                    }
                                    ( string_push_str snip `]\n` )
                                    : i bn ( string_len body )
                                    : i keep ? > bn 900 900 bn
                                    : s braw ( string_data body )
                                    : ~ i j 0
                                    ~ < j keep {
                                        ( string_push_char snip ( nurl_str_get braw j ) )
                                        = j + j 1
                                    }
                                    ? > bn keep { ( string_push_str snip `\n…` ) } {}
                                    ( __ms_topk_push scores texts 6 sc ( string_data snip ) )
                                    ( string_free snip )
                                } {}
                                ( string_free body )
                                = k + k 1
                            }
                            ( vec_free [i] starts ) ( vec_free [i] levels )
                            ( vec_free_with [String] titles \ String t → v { ( string_free t ) } )
                            ( string_free src )
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = fi + fi 1
    }
    ( json_free files )
    : String out ( string_with_cap 4096 )
    : i shown ( vec_len [String] texts )
    ( string_push_int out matched )
    ( string_push_str out ` documentation section(s) match '` )
    ( string_push_str out query )
    ( string_push_str out `'` )
    ? > matched shown {
        ( string_push_str out `; the ` )
        ( string_push_int out shown )
        ( string_push_str out ` best follow` )
    } {}
    ( string_push_str out `. Read a whole one with name= and section=.\n\n` )
    : ~ i j 0
    ~ < j shown {
        ?? ( vec_get [String] texts j ) {
            T t → {
                ( string_push_str out ( string_data t ) )
                ( string_push_str out `\n\n` )
            }
            F _ → {}
        }
        = j + j 1
    }
    ? == matched 0 {
        ( string_push_str out `Nothing matched — terms are whole words. Call nurl_docs with no arguments for the index, or name=<doc> alone for that document's outline.\n` )
    } {}
    ( vec_set [i] hits 0 matched )
    ( vec_free [i] scores ) ( vec_free [i] stats )
    ( vec_free_with [String] texts \ String t → v { ( string_free t ) } )
    ( vec_free_with [String] terms \ String t → v { ( string_free t ) } )
    ( string_free q_lc )
    ^ out
}

// The shortest unambiguous way to name a section back to the tool: its
// leading number if it has one, else the whole title.
@ __ms_push_section_key String out String title → v {
    : s t ( string_data title )
    : i n ( string_len title )
    : ~ i e 0
    ~ & < e n | & >= ( nurl_str_get t e ) 48 <= ( nurl_str_get t e ) 57 == ( nurl_str_get t e ) 46 { = e + e 1 }
    ? > e 0 {
        : ~ i stop e
        ? & > stop 0 == ( nurl_str_get t - stop 1 ) 46 { = stop - stop 1 } {}
        : ~ i j 0
        ~ < j stop { ( string_push_char out ( nurl_str_get t j ) ) = j + j 1 }
    } {
        ( string_push_str out ( string_data title ) )
    }
}

@ msearch_docs_read s docs_dir s name i offset → String {
    : String rel ( msearch_docs_resolve docs_dir name )
    ? == ( string_len rel ) 0 {
        ( string_free rel )
        ^ ( string_new )
    } {}
    : String fp ( path_join docs_dir ( string_data rel ) )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free fp )
    : String out ( string_with_cap 4096 )
    ?? rd {
        T bytes → {
            : String src ( bytes_to_str bytes )
            ( vec_free [u] bytes )
            : i n ( string_len src )
            : ~ i from ? < offset 0 0 offset
            ? > from n { = from n } {}
            : i left - n from
            : i keep ? > left ( __ms_docs_cap ) ( __ms_docs_cap ) left
            ( string_push_str out `docs/` )
            ( string_push_str out ( string_data rel ) )
            ? > from 0 {
                ( string_push_str out ` [bytes ` )
                ( string_push_int out from )
                ( string_push_str out `–` )
                ( string_push_int out + from keep )
                ( string_push_str out ` of ` )
                ( string_push_int out n )
                ( string_push_char out 93 )
            } {}
            ( string_push_char out 10 )
            ( string_push_char out 10 )
            : String slice ( string_substr src from keep )
            ( string_push_str out ( string_data slice ) )
            ( string_free slice )
            ( string_free src )
            ? > left keep {
                ( string_push_str out `\n… truncated at ` )
                ( string_push_int out + from keep )
                ( string_push_str out ` of ` )
                ( string_push_int out n )
                ( string_push_str out ` bytes — continue with offset=` )
                ( string_push_int out + from keep )
                ( string_push_char out 10 )
            } {}
        }
        F _ → {
            ( string_push_str out `docs/` )
            ( string_push_str out ( string_data rel ) )
            ( string_push_str out ` could not be read.\n` )
        }
    }
    ( string_free rel )
    ^ out
}

// basename after the last '/'
@ __ms_basename s path → String {
    : i n ( nurl_str_len path )
    : ~ i start 0
    : ~ i k 0
    ~ < k n { ? == ( nurl_str_get path k ) 47 { = start + k 1 } {} = k + k 1 }
    : s p2 # s + # i path start
    ^ ( string_from p2 )
}
