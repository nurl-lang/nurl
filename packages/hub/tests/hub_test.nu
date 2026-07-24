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
$ `src/hf.nu`
$ `src/store.nu`

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
    ( hub_ref_free r )
}

@ main → i {
    ( nurl_print `hub — offline gates\n` )

    // ---- ref parsing ----
    ( __ref_ck `org/repo` `org/repo` `main` `` `ref: bare org/repo → whole repo, main` )
    ( __ref_ck `org/repo/a/b.gguf` `org/repo` `main` `a/b.gguf` `ref: org/repo/path → single file` )
    ( __ref_ck `org/repo@dev` `org/repo` `dev` `` `ref: @rev on a repo` )
    ( __ref_ck `org/repo@dev/sub/x.bin` `org/repo` `dev` `sub/x.bin` `ref: @rev then subpath` )
    ( __ref_ck `hf.co/org/repo/f.gguf` `org/repo` `main` `f.gguf` `ref: hf.co/ prefix stripped` )

    : HubRef ru ( hub_ref_parse `https://example.com/x.bin` )
    ( check . ru is_url `ref: http(s):// → is_url` )
    : String uu ( hub_resolve_url ru )
    ( check ( streq ( string_data uu ) `https://example.com/x.bin` ) `resolve: URL passes through unchanged` )
    ( string_free uu )
    ( hub_ref_free ru )

    // resolve an HF file ref to the /resolve/ URL
    : HubRef rf ( hub_ref_parse `TheOrg/TheRepo@main/model.gguf` )
    : String ur ( hub_resolve_url rf )
    ( check ( streq ( string_data ur ) `https://huggingface.co/TheOrg/TheRepo/resolve/main/model.gguf` ) `resolve: HF file ref → /resolve/ URL` )
    ( string_free ur )
    ( hub_ref_free rf )

    // ---- name safety ----
    : String sn ( _hub_safe_name `org/repo@main/a b.gguf` )
    ( check ( streq ( string_data sn ) `org_repo_main_a_b.gguf` ) `safe_name: only [A-Za-z0-9._-] survive` )
    ( string_free sn )

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
    : String bpS ( hub_blob_path root shared ) ( write_file ( string_data bpS ) `x` ) ( string_free bpS )
    : String bpA ( hub_blob_path root uniqA ) ( write_file ( string_data bpA ) `x` ) ( string_free bpA )
    : String bpB ( hub_blob_path root uniqB ) ( write_file ( string_data bpB ) `x` ) ( string_free bpB )

    // manifest A references {shared, uniqA}; B references {shared, uniqB}
    : Json ja ( json_obj_new )
    : b _ja1 ( json_obj_set ja `name` ( json_str_lit `A` ) )
    : Json faa ( json_arr_new )
    : Json e1 ( json_obj_new ) : b _e1 ( json_obj_set e1 `sha` ( json_str_lit shared ) ) : b _p1 ( json_arr_push faa e1 )
    : Json e2 ( json_obj_new ) : b _e2 ( json_obj_set e2 `sha` ( json_str_lit uniqA ) ) : b _p2 ( json_arr_push faa e2 )
    : b _jaf ( json_obj_set ja `files` faa )
    : String ta ( json_stringify ja ) ( json_free ja )
    : String mpA ( hub_manifest_path root `A` ) ( write_file ( string_data mpA ) ( string_data ta ) ) ( string_free mpA )
    ( string_free ta )

    : Json jb ( json_obj_new )
    : b _jb1 ( json_obj_set jb `name` ( json_str_lit `B` ) )
    : Json fbb ( json_arr_new )
    : Json e3 ( json_obj_new ) : b _e3 ( json_obj_set e3 `sha` ( json_str_lit shared ) ) : b _p3 ( json_arr_push fbb e3 )
    : Json e4 ( json_obj_new ) : b _e4 ( json_obj_set e4 `sha` ( json_str_lit uniqB ) ) : b _p4 ( json_arr_push fbb e4 )
    : b _jbf ( json_obj_set jb `files` fbb )
    : String tb ( json_stringify jb ) ( json_free jb )
    : String mpB ( hub_manifest_path root `B` ) ( write_file ( string_data mpB ) ( string_data tb ) ) ( string_free mpB )
    ( string_free tb )

    // sharing rule: `shared` is referenced by B (≠A) → shared; uniqA is not
    ( check ( _hub_blob_shared root shared `A` ) `GC: shared blob is seen as shared (kept on A rm)` )
    ( check ! ( _hub_blob_shared root uniqA `A` ) `GC: unique blob is not shared (dropped on A rm)` )

    ( dir_remove_all ( string_data root ) )
    ( string_free root )

    : String sum ( string_from `\n` )
    ( string_push_int sum g_pass ) ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail ) ( string_push_str sum ` failed\n` )
    ( nurl_print ( string_data sum ) )
    ( string_free sum )
    ^ ? > g_fail 0 1 0
}
