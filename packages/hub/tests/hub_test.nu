// hub_test.nu — offline gates for the pure logic: ref parsing, name
// safety, URL resolution, and the store's manifest round-trip + blob
// GC-sharing rule. No network; the download/HF-oracle path is covered
// by tests/hub_test.sh against a real repository.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/hub_test.nu /tmp/ht && /tmp/ht

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/store.nu`
$ `src/hf.nu`
$ `src/pull.nu`
$ `src/hub.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ streq s a s b → b { ^ != ( nurl_str_eq a b ) 0 }

@ __ref_ck s ref s want_repo s want_rev s want_sub s label → v {
    : HubRef r ( hub_ref_parse ref )
    : b okr ( streq ( string_data . r repo ) want_repo )
    : b okv ( streq ( string_data . r rev ) want_rev )
    : b oks ( streq ( string_data . r subpath ) want_sub )
    ( check & & okr okv oks label )
}

@ main → i {
    ( nurl_print `hub — offline gates\n` )

    // ---- ref parsing ----
    ( __ref_ck `org/repo` `org/repo` `main` `` `ref: bare org/repo → whole repo, main` )
    ( __ref_ck `org/repo/a/b.gguf` `org/repo` `main` `a/b.gguf` `ref: org/repo/path → single file` )
    ( __ref_ck `org/repo@dev` `org/repo` `dev` `` `ref: @rev on a repo` )
    ( __ref_ck `org/repo@dev/sub/x.bin` `org/repo` `dev` `sub/x.bin` `ref: @rev then subpath` )
    ( __ref_ck `hf.co/org/repo/f.gguf` `org/repo` `main` `f.gguf` `ref: hf.co/ prefix stripped` )

    // a Hugging Face web URL, as the browser shows it, is a ref — not a
    // web page to download
    ( __ref_ck `https://huggingface.co/org/repo` `org/repo` `main` `` `url: repo page → whole repo` )
    ( __ref_ck `https://huggingface.co/org/repo/` `org/repo` `main` `` `url: repo page, trailing / → whole repo` )
    ( __ref_ck `https://huggingface.co/org/repo/tree/dev` `org/repo` `dev` `` `url: /tree/<rev> → whole repo at rev` )
    ( __ref_ck `https://huggingface.co/org/repo/blob/main/sub/m.gguf` `org/repo` `main` `sub/m.gguf` `url: /blob/ → one file` )
    ( __ref_ck `https://huggingface.co/org/repo/resolve/v2/m.gguf?download=true` `org/repo` `v2` `m.gguf` `url: /resolve/ with a query → one file at rev` )
    ( __ref_ck `https://huggingface.co/org/repo/raw/main/config.json` `org/repo` `main` `config.json` `url: /raw/ → one file` )
    ( __ref_ck `https://hf.co/org/repo/blob/main/m.gguf#L3` `org/repo` `main` `m.gguf` `url: hf.co host, fragment cut` )
    ( __ref_ck `https://www.huggingface.co/org/repo` `org/repo` `main` `` `url: www. alias` )
    ( __ref_ck `huggingface.co/org/repo/blob/main/m.gguf` `org/repo` `main` `m.gguf` `url: no scheme` )
    // shapes hub cannot fetch: an empty repo the caller reports, never a page download
    : HubRef rd ( hub_ref_parse `https://huggingface.co/datasets/org/data` )
    ( check & ! . rd is_url == ( string_len . rd repo ) 0 `url: a dataset → empty repo (reported), not a download` )
    : HubRef rt ( hub_ref_parse `https://huggingface.co/org/repo/tree/main/subdir` )
    ( check & ! . rt is_url == ( string_len . rt repo ) 0 `url: a tree subdirectory → empty repo (reported)` )
    : HubRef rx ( hub_ref_parse `https://huggingface.co/org/repo/discussions/4` )
    ( check & ! . rx is_url == ( string_len . rx repo ) 0 `url: a discussion page → empty repo (reported)` )
    : HubRef ro ( hub_ref_parse `https://huggingface.co/org` )
    ( check & ! . ro is_url == ( string_len . ro repo ) 0 `url: an org page → empty repo (reported)` )
    // the $HF_ENDPOINT mirror's own URLs are refs too
    : !v IoErr es ( env_set `HF_ENDPOINT` `https://hf-mirror.example` )
    ?? es { T _ → {} F _ → {} }
    ( __ref_ck `https://hf-mirror.example/org/repo/blob/main/m.gguf` `org/repo` `main` `m.gguf` `url: $HF_ENDPOINT host → one file` )
    : !v IoErr eu ( env_unset `HF_ENDPOINT` )
    ?? eu { T _ → {} F _ → {} }

    : HubRef ru ( hub_ref_parse `https://example.com/x.bin` )
    ( check . ru is_url `ref: http(s):// → is_url` )
    : String uu ( hub_resolve_url ru )
    ( check ( streq ( string_data uu ) `https://example.com/x.bin` ) `resolve: URL passes through unchanged` )

    // resolve an HF file ref to the /resolve/ URL
    : HubRef rf ( hub_ref_parse `TheOrg/TheRepo@main/model.gguf` )
    : String ur ( hub_resolve_url rf )
    ( check ( streq ( string_data ur ) `https://huggingface.co/TheOrg/TheRepo/resolve/main/model.gguf` ) `resolve: HF file ref → /resolve/ URL` )

    // ---- name safety ----
    : String sn ( _hub_safe_name `org/repo@main/a b.gguf` )
    ( check ( streq ( string_data sn ) `org_repo_main_a_b.gguf` ) `safe_name: only [A-Za-z0-9._-] survive` )

    // ---- hub_get: an existing local path passes straight through ----
    : String here ( string_from `/tmp/hub-test-store` )
    ( dir_remove_all ( string_data here ) )
    ?? ( dir_create_all ( string_data here ) ) { T _ → {} F _ → {} }
    ?? ( hub_get ( string_data here ) ) {
        T p → { ( check ( streq ( string_data p ) ( string_data here ) ) `hub_get: existing local dir passes through (no fetch)` ) }
        F _ → { ( check F `hub_get: existing local dir passes through (no fetch)` ) }
    }
    ( dir_remove_all ( string_data here ) )

    // ---- store: manifest round-trip + blob GC sharing ----
    : String root ( string_from `/tmp/hub-test-store` )
    ( dir_remove_all ( string_data root ) )
    : !v String ir ( hub_store_init root )
    ?? ir { T _ → { ( check T `store_init` ) } F _ → { ( check F `store_init` ) } }

    // two "manifests" that SHARE one blob sha, plus one unique each
    : s shared `1111111111111111111111111111111111111111111111111111111111111111`
    : s uniqA `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
    : s uniqB `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`
    // write blobs so file_exists is true
    : String bpS ( hub_blob_path root shared ) ( write_file ( string_data bpS ) `x` )
    : String bpA ( hub_blob_path root uniqA ) ( write_file ( string_data bpA ) `x` )
    : String bpB ( hub_blob_path root uniqB ) ( write_file ( string_data bpB ) `x` )

    // manifest A references {shared, uniqA}; B references {shared, uniqB}
    : Json ja ( json_obj_new )
    : b _ja1 ( json_obj_set ja `name` ( json_str_lit `A` ) )
    : Json faa ( json_arr_new )
    : Json e1 ( json_obj_new ) : b _e1 ( json_obj_set e1 `sha` ( json_str_lit shared ) ) : b _p1 ( json_arr_push faa e1 )
    : Json e2 ( json_obj_new ) : b _e2 ( json_obj_set e2 `sha` ( json_str_lit uniqA ) ) : b _p2 ( json_arr_push faa e2 )
    : b _jaf ( json_obj_set ja `files` faa )
    : String ta ( json_stringify ja )
    : String mpA ( hub_manifest_path root `A` ) ( write_file ( string_data mpA ) ( string_data ta ) )

    : Json jb ( json_obj_new )
    : b _jb1 ( json_obj_set jb `name` ( json_str_lit `B` ) )
    : Json fbb ( json_arr_new )
    : Json e3 ( json_obj_new ) : b _e3 ( json_obj_set e3 `sha` ( json_str_lit shared ) ) : b _p3 ( json_arr_push fbb e3 )
    : Json e4 ( json_obj_new ) : b _e4 ( json_obj_set e4 `sha` ( json_str_lit uniqB ) ) : b _p4 ( json_arr_push fbb e4 )
    : b _jbf ( json_obj_set jb `files` fbb )
    : String tb ( json_stringify jb )
    : String mpB ( hub_manifest_path root `B` ) ( write_file ( string_data mpB ) ( string_data tb ) )

    // sharing rule: `shared` is referenced by B (≠A) → shared; uniqA is not
    ( check ( _hub_blob_shared root shared `A` ) `GC: shared blob is seen as shared (kept on A rm)` )
    ( check ! ( _hub_blob_shared root uniqA `A` ) `GC: unique blob is not shared (dropped on A rm)` )

    ( dir_remove_all ( string_data root ) )

    // ---- ranged transfers: chunk layout, staging names, the range record ----
    ( check & == ( _hub_nchunks 10 4 ) 3 == ( _hub_nchunks 8 4 ) 2 `chunks: 10 B in 4 B chunks → 3, 8 B → 2` )
    ( check & == ( _hub_chunk_len 2 10 4 ) 2 == ( _hub_chunk_len 1 10 4 ) 4 `chunks: the last chunk is short, the others whole` )
    ( check & ( _hub_is_ranged 100 10 ) ! ( _hub_is_ranged 10 10 ) `chunks: ranged only above one chunk` )

    : s hexX `0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef`
    : String stA ( hub_stage_name `https://h/o/r/resolve/main/a/config.json` `config.json` hexX )
    ( check ( streq ( string_data stA ) `sha256-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef` ) `stage: a published sha256 is the staging name` )
    : String st1 ( hub_stage_name `https://h/o/r/resolve/main/a/config.json` `config.json` `` )
    : String st2 ( hub_stage_name `https://h/o/r/resolve/main/b/config.json` `config.json` `` )
    ( check & ( string_starts_with st1 `config.json.` ) == ( string_len st1 ) 28 `stage: no sha → <name>.<16 hex of the URL>` )
    ( check ! ( string_eq st1 st2 ) `stage: two files with one basename never share a staging file` )

    : String mroot ( string_from `/tmp/hub-test-ranges` )
    ( dir_remove_all ( string_data mroot ) )
    ?? ( dir_create_all ( string_data mroot ) ) { T _ → {} F _ → {} }
    : String mp ( path_join ( string_data mroot ) `x.part.ranges` )
    : ( Vec i ) fl ( vec_new [i] )
    ( vec_push [i] fl 1 ) ( vec_push [i] fl 1 ) ( vec_push [i] fl 0 )
    : !v String mw ( _hub_map_write ( string_data mp ) 10 4 fl )
    ( check ?? mw { T _ → T F _ → F } `range record: written` )
    ?? ( _hub_map_read ( string_data mp ) 10 4 ) {
        T d → { ( check & & == ( vec_at [i] d 0 ) 1 == ( vec_at [i] d 1 ) 1 == ( vec_at [i] d 2 ) 0 `range record: read back as written` ) }
        F → { ( check F `range record: read back as written` ) }
    }
    // a torn last line (a crash mid-append) is skipped, a real one counts
    ( append_file ( string_data mp ) `2x` )
    ?? ( _hub_map_read ( string_data mp ) 10 4 ) {
        T d → { ( check == ( vec_at [i] d 2 ) 0 `range record: a torn line counts for nothing` ) }
        F → { ( check F `range record: a torn line counts for nothing` ) }
    }
    // another chunk size: a chunk is on disk when every recorded chunk it
    // overlaps is (bytes 0..8 recorded, of 10)
    ?? ( _hub_map_read ( string_data mp ) 10 2 ) {
        T d → { ( check & & == ( vec_len [i] d ) 5 & == ( vec_at [i] d 3 ) 1 == ( vec_at [i] d 0 ) 1 == ( vec_at [i] d 4 ) 0 `range record: read in a smaller chunk size` ) }
        F → { ( check F `range record: read in a smaller chunk size` ) }
    }
    ?? ( _hub_map_read ( string_data mp ) 10 8 ) {
        T d → { ( check & == ( vec_at [i] d 0 ) 1 == ( vec_at [i] d 1 ) 0 `range record: read in a larger chunk size` ) }
        F → { ( check F `range record: read in a larger chunk size` ) }
    }
    // a record of a file of another size vouches for nothing
    ?? ( _hub_map_read ( string_data mp ) 11 4 ) {
        T _ → { ( check F `range record: another file size → none` ) }
        F → { ( check T `range record: another file size → none` ) }
    }
    ( dir_remove_all ( string_data mroot ) )

    // tuning from the environment, out-of-range values ignored
    : !v IoErr ec ( env_set `HUB_CONNS` `3` )
    ?? ec { T _ → {} F _ → {} }
    : !v IoErr ej ( env_set `HUB_JOBS` `0` )
    ?? ej { T _ → {} F _ → {} }
    : HubOpts ho ( hub_opts_default )
    ( check & & == . ho conns 3 == . ho jobs HUB_JOBS_DEFAULT == . ho chunk HUB_CHUNK_DEFAULT `opts: $HUB_CONNS read, a bad $HUB_JOBS ignored` )
    : !v IoErr uc ( env_unset `HUB_CONNS` )
    ?? uc { T _ → {} F _ → {} }
    : !v IoErr uj ( env_unset `HUB_JOBS` )
    ?? uj { T _ → {} F _ → {} }

    : String sum ( string_from `\n` )
    ( string_push_int sum g_pass ) ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail ) ( string_push_str sum ` failed\n` )
    ( nurl_print ( string_data sum ) )
    ^ ? > g_fail 0 1 0
}
