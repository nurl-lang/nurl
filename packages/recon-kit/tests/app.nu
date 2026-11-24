// packages/recon-kit/tests/app.nu — `recon-test`, a model that is not one:
// the smallest executable that answers recon-kit's contract, so the
// service can be tested without a GPU or a checkpoint.
//
//   recon-test serve ...                     rk_serve with this app
//   recon-test mesh <scene> -o <glb> ...     the real ms_main
//   recon-test <input> -o <ply> --scene <s> [options]
//                                            fails, like a model whose
//                                            input does not decode

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `src/mesh.nu`
$ `src/serve.nu`

@ __rt_opts Json j → String {
    : String o ( string_from `--max-views ` )
    ( string_push_int o ( rk_jint j `max_views` 0 2000 24 ) )
    ( string_push_str o ` --window ` )
    ( string_push_int o ( rk_jint j `window` 4 64 24 ) )
    ( rk_push_voxel o ( rk_jint j `voxel_mm` -1 999 -1 ) )
    ^ o
}

@ main → i {
    : i argc ( nurl_argc )
    ? & > argc 1 == 0 ( nurl_str_cmp ( nurl_argv 1 ) `serve` ) {
        ^ ( rk_serve @ RkApp {
            ( string_from `recon-test` )
            ( string_from `a test app` )
            ( string_from `recon-kit's test app.` )
            8899
            ( string_from `.recon-test` )
            ( string_from `RECON_TEST_PASSWORD` )
            ( string_from `<div><label for="o-win">window</label><input id="o-win" type="number" value="24"></div>` )
            ( string_from `function modelOptions() { return { window: num("o-win", 4, 64, 24) }; }
function modelHint(n, isVid, picked) { return ""; }` )
            24
            120
            \ Json j → String { ^ ( __rt_opts j ) }
        } )
    } {}
    ? & > argc 1 == 0 ( nurl_str_cmp ( nurl_argv 1 ) `mesh` ) { ^ ( ms_main `recon-test` ) } {}
    ( nurl_println `recon-test: cannot decode the input (a test app reconstructs nothing)` )
    ^ 1
}
