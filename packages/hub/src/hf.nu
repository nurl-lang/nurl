// packages/hub/src/hf.nu — Hugging Face refs and the repo file listing.
//
// A ref is one of:
//   https://…  |  http://…            a direct URL, passed through
//   org/repo                          a whole repository (rev = main)
//   org/repo/path/to/file.gguf        one file inside a repository
//   org/repo@revision[/path…]         pinned to a branch/tag/commit
//   hf.co/org/repo[/path…]            the hf.co shorthand (prefix stripped)
//
// hub_hf_tree asks GET /api/models/<repo>/tree/<rev>?recursive=1 for the
// file list and reads each file's size and — for LFS files, which is
// where the weights live — the sha256 Hugging Face publishes as lfs.oid.
// Small non-LFS files (config.json, tokenizer.json) carry only a git
// blob oid (a sha1), so they get no external anchor; hub sha256s them
// locally for the content address. The listing follows the Link:
// rel="next" pagination so a repository with hundreds of files is never
// silently truncated.
//
//   $HF_ENDPOINT overrides https://huggingface.co (mirrors).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`

: HubRef {
    b is_url
    String url
    String repo
    String rev
    String subpath
}

: HubFile {
    String path
    String sha
    i size
    b lfs
}

@ hub_ref_free HubRef r → v {
    ( string_free . r url )
    ( string_free . r repo )
    ( string_free . r rev )
    ( string_free . r subpath )
}

@ hub_file_free HubFile f → v {
    ( string_free . f path )
    ( string_free . f sha )
}

@ hub_hf_endpoint → String {
    : ?String ov ( env_get `HF_ENDPOINT` )
    ?? ov {
        T v → { ^ v }
        F → {}
    }
    ^ ( string_from `https://huggingface.co` )
}

// index of byte `c` in [from,len), or -1
@ __hub_idx s src i from i c → i {
    : i n ( nurl_str_len src )
    : ~ i k from
    ~ < k n {
        ? == ( nurl_str_get src k ) c { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ __hub_slice s src i a i b → String {
    : String out ( string_new )
    : ~ i k a
    ~ < k b {
        ( string_push_char out ( nurl_str_get src k ) )
        = k + k 1
    }
    ^ out
}

// Parse a ref into its parts. Never fails — a malformed ref simply
// yields an empty repo, which the caller reports.
@ hub_ref_parse s ref → HubRef {
    ? | != ( nurl_str_starts ref `http://` ) 0 != ( nurl_str_starts ref `https://` ) 0 {
        ^ @ HubRef { T ( string_from ref ) ( string_new ) ( string_from `main` ) ( string_new ) }
    } {}
    // strip a leading hf.co/
    : ~ String body ( string_new )
    ? != ( nurl_str_starts ref `hf.co/` ) 0 {
        ( string_free body )
        = body ( __hub_slice ref 6 ( nurl_str_len ref ) )
    } {
        ( string_free body )
        = body ( string_from ref )
    }
    : s bd ( string_data body )
    : i n ( string_len body )

    : ~ String repo ( string_new )
    : ~ String rev ( string_from `main` )
    : ~ String subpath ( string_new )

    : i at ( __hub_idx bd 0 64 )
    ? >= at 0 {
        // org/repo @ rev [/ subpath]
        ( string_free repo )
        = repo ( __hub_slice bd 0 at )
        : i afterat + at 1
        : i sl ( __hub_idx bd afterat 47 )
        ? >= sl 0 {
            ( string_free rev )
            = rev ( __hub_slice bd afterat sl )
            ( string_free subpath )
            = subpath ( __hub_slice bd + sl 1 n )
        } {
            ( string_free rev )
            = rev ( __hub_slice bd afterat n )
        }
    } {
        // org/repo [/ subpath] — repo is the first two segments
        : i s1 ( __hub_idx bd 0 47 )
        ? >= s1 0 {
            : i s2 ( __hub_idx bd + s1 1 47 )
            ? >= s2 0 {
                ( string_free repo )
                = repo ( __hub_slice bd 0 s2 )
                ( string_free subpath )
                = subpath ( __hub_slice bd + s2 1 n )
            } {
                ( string_free repo )
                = repo ( string_from bd )
            }
        } {
            ( string_free repo )
            = repo ( string_from bd )
        }
    }
    ( string_free body )
    ^ @ HubRef { F ( string_new ) repo rev subpath }
}

// https://<endpoint>/<repo>/resolve/<rev>/<subpath>
@ hub_resolve_url HubRef r → String {
    ? . r is_url { ^ ( string_from ( string_data . r url ) ) } {}
    : String ep ( hub_hf_endpoint )
    : String out ( string_from ( string_data ep ) )
    ( string_free ep )
    ( string_push_char out 47 )
    ( string_push_str out ( string_data . r repo ) )
    ( string_push_str out `/resolve/` )
    ( string_push_str out ( string_data . r rev ) )
    ( string_push_char out 47 )
    ( string_push_str out ( string_data . r subpath ) )
    ^ out
}

// index of `needle` in `hay` at or after `from`, or -1
@ __hub_find_sub s hay i from s needle → i {
    : i hn ( nurl_str_len hay )
    : i nn ( nurl_str_len needle )
    ? == nn 0 { ^ from } {}
    : ~ i k from
    ~ <= k - hn nn {
        : ~ b hit T
        : ~ i j 0
        ~ & < j nn hit {
            ? == ( nurl_str_get hay + k j ) ( nurl_str_get needle j ) {} { = hit F }
            = j + j 1
        }
        ? hit { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Extract the rel="next" URL from a Link header value, or "" .
@ __hub_link_next s link → String {
    : i found ( __hub_find_sub link 0 `rel="next"` )
    ? < found 0 { ^ ( string_new ) } {}
    // the URL for this rel is the last <...> at or before `found`
    : ~ i lt -1
    : ~ i gt -1
    : ~ i j 0
    ~ < j found {
        ? == ( nurl_str_get link j ) 60 { = lt j } {}
        ? == ( nurl_str_get link j ) 62 { = gt j } {}
        = j + j 1
    }
    ? & >= lt 0 & > gt lt < gt found {
        ^ ( __hub_slice link + lt 1 gt )
    } {}
    ^ ( string_new )
}

// Append the files of one /tree page (a JSON array) to `out`.
@ __hub_tree_page s body ( Vec HubFile ) out → v {
    : !Json JsonError pj ( json_parse body )
    ?? pj {
        T j → {
            ? ( json_is_arr j ) {
                : i n ( json_arr_len j )
                : ~ i k 0
                ~ < k n {
                    ?? ( json_arr_get j k ) {
                        T e → {
                            : ~ b isfile T
                            ?? ( json_obj_get e `type` ) {
                                T tj → { ? ( nurl_str_eq ( json_str_data tj ) `file` ) {} { = isfile F } }
                                F → {}
                            }
                            ? isfile {
                                : ~ String path ( string_new )
                                ?? ( json_obj_get e `path` ) {
                                    T pj → { ( string_free path ) = path ( string_from ( json_str_data pj ) ) }
                                    F → {}
                                }
                                : ~ i size 0
                                ?? ( json_obj_get e `size` ) {
                                    T sj → { ?? ( json_num_as_i sj ) { T v → { = size v } F → {} } }
                                    F → {}
                                }
                                : ~ String sha ( string_new )
                                : ~ b lfs F
                                ?? ( json_obj_get e `lfs` ) {
                                    T lj → {
                                        = lfs T
                                        ?? ( json_obj_get lj `oid` ) {
                                            T oj → { ( string_free sha ) = sha ( string_from ( json_str_data oj ) ) }
                                            F → {}
                                        }
                                    }
                                    F → {}
                                }
                                ? > ( string_len path ) 0 {
                                    ( vec_push [HubFile] out @ HubFile { path sha size lfs } )
                                } {
                                    ( string_free path )
                                    ( string_free sha )
                                }
                            } {}
                        }
                        F → {}
                    }
                    = k + k 1
                }
            } {}
            ( json_free j )
        }
        F _ → {}
    }
}

// List every file in <repo>@<rev>, following pagination.
@ hub_hf_tree HubRef r → !( Vec HubFile ) String {
    : ( Vec HubFile ) out ( vec_new [HubFile] )
    : String ep ( hub_hf_endpoint )
    : ~ String url ( string_from ( string_data ep ) )
    ( string_free ep )
    ( string_push_str url `/api/models/` )
    ( string_push_str url ( string_data . r repo ) )
    ( string_push_str url `/tree/` )
    ( string_push_str url ( string_data . r rev ) )
    ( string_push_str url `?recursive=1` )

    : ~ b more T
    : ~ b ok T
    : ~ String err ( string_new )
    ~ & more ok {
        : !Response HttpErr rr ( http_get ( string_data url ) )
        ?? rr {
            T resp → {
                : i st ( http_status resp )
                ? == st 200 {
                    : s bs ( http_body_str resp )
                    ( __hub_tree_page bs out )
                    // pagination: Link rel="next"
                    : ~ String next ( string_new )
                    : i hc ( http_header_count resp )
                    : ~ i k 0
                    ~ < k hc {
                        : String hn ( string_from ( http_header_name resp k ) )
                        : String hl ( string_to_lower hn )
                        ( string_free hn )
                        ? ( nurl_str_eq ( string_data hl ) `link` ) {
                            ( string_free next )
                            = next ( __hub_link_next ( http_header_value resp k ) )
                        } {}
                        ( string_free hl )
                        = k + k 1
                    }
                    ? > ( string_len next ) 0 {
                        ( string_free url )
                        = url next
                    } {
                        = more F
                        ( string_free next )
                    }
                } {
                    = ok F
                    ( string_free err )
                    = err ( string_from `hub: cannot list the repository (HTTP ` )
                    ( string_push_int err st )
                    ( string_push_str err `) — check the org/repo and revision` )
                }
                ( response_free resp )
            }
            F _ → {
                = ok F
                ( string_free err )
                = err ( string_from `hub: cannot reach Hugging Face to list the repository` )
            }
        }
    }
    ( string_free url )
    ? ok {
        ( string_free err )
        ^ @ !( Vec HubFile ) String { T out }
    } {}
    ( vec_free_with [HubFile] out \ HubFile f → v { ( hub_file_free f ) } )
    ^ @ !( Vec HubFile ) String { F err }
}
