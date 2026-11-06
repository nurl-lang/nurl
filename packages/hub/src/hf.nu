// packages/hub/src/hf.nu — Hugging Face refs and the repo file listing.
//
// A ref is one of:
//   org/repo                          a whole repository (rev = main)
//   org/repo/path/to/file.gguf        one file inside a repository
//   org/repo@revision[/path…]         pinned to a branch/tag/commit
//   hf.co/org/repo[/path…]            the hf.co shorthand (prefix stripped)
//   https://huggingface.co/org/repo[/tree/<rev>]
//   https://huggingface.co/org/repo/(resolve|blob|raw)/<rev>/<path>
//                                     a Hugging Face web URL, as a browser
//                                     shows it (also hf.co, the
//                                     $HF_ENDPOINT host, or no scheme)
//   https://…  |  http://…            any other URL: downloaded as-is
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
$ `stdlib/core/slice.nu`

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
    : ( Slice u ) src_v ( slice_of_str src )
    : i n ( nurl_str_len src )
    : ~ i k from
    ~ < k n {
        ? == ( slice_byte src_v k ) c { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ __hub_slice s src i a i b → String {
    : ( Slice u ) src_v ( slice_of_str src )
    : String out ( string_new )
    : ~ i k a
    ~ < k b {
        ( string_push_char out ( slice_byte src_v k ) )
        = k + k 1
    }
    ^ out
}

// `url` without its scheme: the host, then the path from its first `/`
// on (or "" when there is none). A URL without http(s):// gives "".
@ __hub_url_rest s url → String {
    : i n ( nurl_str_len url )
    ? != ( nurl_str_starts url `https://` ) 0 { ^ ( __hub_slice url 8 n ) } {}
    ? != ( nurl_str_starts url `http://` ) 0 { ^ ( __hub_slice url 7 n ) } {}
    ^ ( string_new )
}

// The host of a scheme-less URL rest (up to the first `/`).
@ __hub_rest_host s rest → String {
    : i n ( nurl_str_len rest )
    : i sl ( __hub_idx rest 0 47 )
    ^ ( __hub_slice rest 0 ? >= sl 0 sl n )
}

// Is `host` one that serves Hugging Face repositories? huggingface.co,
// its www. alias and the hf.co short domain, or the host of
// $HF_ENDPOINT (a mirror).
@ __hub_is_hf_host s host → b {
    ? != ( nurl_str_eq host `huggingface.co` ) 0 { ^ T } {}
    ? != ( nurl_str_eq host `www.huggingface.co` ) 0 { ^ T } {}
    ? != ( nurl_str_eq host `hf.co` ) 0 { ^ T } {}
    : String ep ( hub_hf_endpoint )
    : String eprest ( __hub_url_rest ( string_data ep ) )
    : String ephost ( __hub_rest_host ( string_data eprest ) )
    ^ & > ( string_len ephost ) 0 != ( nurl_str_eq ( string_data ephost ) host ) 0
}

// A Hugging Face web URL's path (no leading `/`, query and fragment
// cut) parsed as a ref — what a browser's address bar shows:
//   <org>/<repo>                                 the whole repo at main
//   <org>/<repo>/tree/<rev>                      the whole repo at rev
//   <org>/<repo>/(resolve|blob|raw)/<rev>/<path> one file at rev
// Anything else (a dataset or Space, a subdirectory of a tree, a
// discussion page) yields an empty repo, which the caller reports,
// rather than downloading a web page in place of a model.
@ __hub_hf_page_ref s url_path → HubRef {
    : HubRef bad @ HubRef { F ( string_new ) ( string_new ) ( string_from `main` ) ( string_new ) }
    // cut a query (?download=true) or fragment (#L12)
    : i un ( nurl_str_len url_path )
    : i q ( __hub_idx url_path 0 63 )
    : i h ( __hub_idx url_path 0 35 )
    : ~ i pend un
    ? & >= q 0 < q pend { = pend q } {}
    ? & >= h 0 < h pend { = pend h } {}
    : String pv ( __hub_slice url_path 0 pend )
    : s path ( string_data pv )
    : i n ( string_len pv )
    : i s1 ( __hub_idx path 0 47 )
    ? <= s1 0 { ^ bad } {}
    : String org ( __hub_slice path 0 s1 )
    ? | != ( nurl_str_eq ( string_data org ) `datasets` ) 0 != ( nurl_str_eq ( string_data org ) `spaces` ) 0 { ^ bad } {}
    : i s2 ( __hub_idx path + s1 1 47 )
    : i repo_end ? >= s2 0 s2 n
    ? <= repo_end + s1 1 { ^ bad } {}
    : String repo ( __hub_slice path 0 repo_end )
    // <org>/<repo> or <org>/<repo>/
    ? | < s2 0 == + s2 1 n {
        ^ @ HubRef { F ( string_new ) repo ( string_from `main` ) ( string_new ) }
    } {}
    : i s3 ( __hub_idx path + s2 1 47 )
    ? < s3 0 { ^ bad } {}
    : String kind ( __hub_slice path + s2 1 s3 )
    : i s4 ( __hub_idx path + s3 1 47 )
    : i rev_end ? >= s4 0 s4 n
    ? <= rev_end + s3 1 { ^ bad } {}
    : String rev ( __hub_slice path + s3 1 rev_end )
    : String rest ? >= s4 0 ( __hub_slice path + s4 1 n ) ( string_new )
    ? != ( nurl_str_eq ( string_data kind ) `tree` ) 0 {
        ? > ( string_len rest ) 0 { ^ bad } {}
        ^ @ HubRef { F ( string_new ) repo rev ( string_new ) }
    } {}
    : b is_file | | != ( nurl_str_eq ( string_data kind ) `resolve` ) 0 != ( nurl_str_eq ( string_data kind ) `blob` ) 0 != ( nurl_str_eq ( string_data kind ) `raw` ) 0
    ? & is_file > ( string_len rest ) 0 {
        ^ @ HubRef { F ( string_new ) repo rev rest }
    } {}
    ^ bad
}

// Parse a ref into its parts. Never fails — a malformed ref simply
// yields an empty repo, which the caller reports.
@ hub_ref_parse s ref → HubRef {
    // huggingface.co/… without a scheme is the same web URL
    ? != ( nurl_str_starts ref `huggingface.co/` ) 0 {
        : String bare ( __hub_slice ref 15 ( nurl_str_len ref ) )
        ^ ( __hub_hf_page_ref ( string_data bare ) )
    } {}
    : String rest ( __hub_url_rest ref )
    ? > ( string_len rest ) 0 {
        : String host ( __hub_rest_host ( string_data rest ) )
        ? ( __hub_is_hf_host ( string_data host ) ) {
            // the path after the host's `/`
            : i rn ( string_len rest )
            : i hl ( string_len host )
            : String path ( __hub_slice ( string_data rest ) ? < hl rn + hl 1 rn rn )
            ^ ( __hub_hf_page_ref ( string_data path ) )
        } {}
        ^ @ HubRef { T ( string_from ref ) ( string_new ) ( string_from `main` ) ( string_new ) }
    } {}
    // strip a leading hf.co/
    : ~ String body ( string_new )
    ? != ( nurl_str_starts ref `hf.co/` ) 0 {
        = body ( __hub_slice ref 6 ( nurl_str_len ref ) )
    } {
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
        = repo ( __hub_slice bd 0 at )
        : i afterat + at 1
        : i sl ( __hub_idx bd afterat 47 )
        ? >= sl 0 {
            = rev ( __hub_slice bd afterat sl )
            = subpath ( __hub_slice bd + sl 1 n )
        } {
            = rev ( __hub_slice bd afterat n )
        }
    } {
        // org/repo [/ subpath] — repo is the first two segments
        : i s1 ( __hub_idx bd 0 47 )
        ? >= s1 0 {
            : i s2 ( __hub_idx bd + s1 1 47 )
            ? >= s2 0 {
                = repo ( __hub_slice bd 0 s2 )
                = subpath ( __hub_slice bd + s2 1 n )
            } {
                = repo ( string_from bd )
            }
        } {
            = repo ( string_from bd )
        }
    }
    ^ @ HubRef { F ( string_new ) repo rev subpath }
}

// https://<endpoint>/<repo>/resolve/<rev>/<subpath>
@ hub_resolve_url HubRef r → String {
    ? . r is_url { ^ ( string_from ( string_data . r url ) ) } {}
    : String ep ( hub_hf_endpoint )
    : String out ( string_from ( string_data ep ) )
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
    : ( Slice u ) needle_v ( slice_of_str needle )
    : ( Slice u ) hay_v ( slice_of_str hay )
    : i hn ( nurl_str_len hay )
    : i nn ( nurl_str_len needle )
    ? == nn 0 { ^ from } {}
    : ~ i k from
    ~ <= k - hn nn {
        : ~ b hit T
        : ~ i j 0
        ~ & < j nn hit {
            ? == ( slice_byte hay_v + k j ) ( slice_byte needle_v j ) {} { = hit F }
            = j + j 1
        }
        ? hit { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Extract the rel="next" URL from a Link header value, or "" .
@ __hub_link_next s link → String {
    : ( Slice u ) link_v ( slice_of_str link )
    : i found ( __hub_find_sub link 0 `rel="next"` )
    ? < found 0 { ^ ( string_new ) } {}
    // the URL for this rel is the last <...> at or before `found`
    : ~ i lt -1
    : ~ i gt -1
    : ~ i j 0
    ~ < j found {
        ? == ( slice_byte link_v j ) 60 { = lt j } {}
        ? == ( slice_byte link_v j ) 62 { = gt j } {}
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
                                    T pj → { = path ( string_from ( json_str_data pj ) ) }
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
                                            T oj → { = sha ( string_from ( json_str_data oj ) ) }
                                            F → {}
                                        }
                                    }
                                    F → {}
                                }
                                ? > ( string_len path ) 0 {
                                    ( vec_push [HubFile] out @ HubFile { path sha size lfs } )
                                } {
                                }
                            } {}
                        }
                        F → {}
                    }
                    = k + k 1
                }
            } {}
        }
        F _ → {}
    }
}

// List every file in <repo>@<rev>, following pagination.
@ hub_hf_tree HubRef r → !( Vec HubFile ) String {
    : ( Vec HubFile ) out ( vec_new [HubFile] )
    : String ep ( hub_hf_endpoint )
    : ~ String url ( string_from ( string_data ep ) )
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
                        ? ( nurl_str_eq ( string_data hl ) `link` ) {
                            = next ( __hub_link_next ( http_header_value resp k ) )
                        } {}
                        = k + k 1
                    }
                    ? > ( string_len next ) 0 {
                        = url next
                    } {
                        = more F
                    }
                } {
                    = ok F
                    = err ( string_from `hub: cannot list the repository (HTTP ` )
                    ( string_push_int err st )
                    ( string_push_str err `) — check the org/repo and revision` )
                }
            }
            F _ → {
                = ok F
                = err ( string_from `hub: cannot reach Hugging Face to list the repository` )
            }
        }
    }
    ? ok {
        ^ @ !( Vec HubFile ) String { T out }
    } {}
    ^ @ !( Vec HubFile ) String { F err }
}
