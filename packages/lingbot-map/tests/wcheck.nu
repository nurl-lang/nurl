// wcheck.nu — open a checkpoint through src/weights.nu and print the
// architecture it describes: layer counts read off the file, the shapes
// the port depends on, and whether every tensor stage 3–5 will ask for
// is present with the right shape.
//
// Run against the real lingbot-map.pt; the expected output is in
// docs/checkpoint.md.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/weights.nu`

@ show * Lw w s name → v {
    ( nurl_print name )
    : i nd ( lw_ndim w name )
    ? == nd 0 { ( nurl_print ` MISSING\n` ) ^ v } {}
    ( nurl_print ` ` )
    : ~ i a 0
    ~ < a nd {
        ? > a 0 { ( nurl_print `x` ) } {}
        ( nurl_print ( nurl_str_int ( lw_dim w name a ) ) )
        = a + a 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    ? < ( nurl_argc ) 2 { ( nurl_print `usage: wcheck <checkpoint.pt>\n` ) ^ 2 } {}
    : !*Lw String o ( lw_open ( nurl_argv 1 ) )
    ?? o {
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) ^ 1 }
        T w → {
            ( nurl_print `tensors ` )
            ( nurl_print ( nurl_str_int ( lw_n_tensors w ) ) ) ( nurl_print `\n` )
            ( nurl_print `dino_blocks ` )
            ( nurl_print ( nurl_str_int ( lw_count_indexed w `aggregator.patch_embed.blocks.` `.norm1.weight` ) ) )
            ( nurl_print `\n` )
            ( nurl_print `frame_blocks ` )
            ( nurl_print ( nurl_str_int ( lw_count_indexed w `aggregator.frame_blocks.` `.norm1.weight` ) ) )
            ( nurl_print `\n` )
            ( nurl_print `global_blocks ` )
            ( nurl_print ( nurl_str_int ( lw_count_indexed w `aggregator.global_blocks.` `.norm1.weight` ) ) )
            ( nurl_print `\n` )
            ( nurl_print `camera_trunk ` )
            ( nurl_print ( nurl_str_int ( lw_count_indexed w `camera_head.trunk.` `.norm1.weight` ) ) )
            ( nurl_print `\n` )
            ( show w `aggregator.patch_embed.pos_embed` )
            ( show w `aggregator.patch_embed.patch_embed.proj.weight` )
            ( show w `aggregator.patch_embed.cls_token` )
            ( show w `aggregator.patch_embed.register_tokens` )
            ( show w `aggregator.camera_token` )
            ( show w `aggregator.register_token` )
            ( show w `aggregator.scale_token` )
            ( show w `aggregator.frame_blocks.0.attn.qkv.weight` )
            ( show w `aggregator.frame_blocks.0.attn.q_norm.weight` )
            ( show w `aggregator.frame_blocks.0.ls1.gamma` )
            ( show w `aggregator.global_blocks.23.mlp.fc2.weight` )
            ( show w `depth_head.projects.0.weight` )
            ( nurl_print `point_head_present ` )
            ( nurl_print ? ( lw_has w `point_head.projects.0.weight` ) `T` `F` )
            ( nurl_print `\n` )

            // shape contract for the pieces stage 3 will build
            : b _a ( lw_require w `aggregator.patch_embed.pos_embed` 1 1370 1024 -1 )
            : b _b ( lw_require w `aggregator.patch_embed.patch_embed.proj.weight` 1024 3 14 14 )
            : b _c ( lw_require w `aggregator.frame_blocks.0.attn.qkv.weight` 3072 1024 -1 -1 )
            : b _d ( lw_require w `aggregator.frame_blocks.0.mlp.fc1.weight` 4096 1024 -1 -1 )
            : b _e ( lw_require w `aggregator.camera_token` 1 2 1 1024 )
            ( nurl_print `shape_contract ` )
            ( nurl_print ? ( lw_ok w ) `OK` ( lw_error w ) )
            ( nurl_print `\n` )

            // a real read, into a buffer sized from the tensor itself
            : i ln ( lw_nelems w `aggregator.frame_blocks.0.ls1.gamma` )
            : *f buf # *f ( nurl_zalloc * 8 ? > ln 0 ln 1 )
            : b rok ( lw_read w `aggregator.frame_blocks.0.ls1.gamma` buf ln )
            ( nurl_print `read_ls1 ` ) ( nurl_print ? rok `OK` `FAIL` )
            ( nurl_print ` n=` ) ( nurl_print ( nurl_str_int ln ) )
            ? rok {
                ( nurl_print ` v0=` ) ( nurl_print ( nurl_str_float . buf 0 ) )
                ( nurl_print ` v1023=` ) ( nurl_print ( nurl_str_float . buf - ln 1 ) )
            } {}
            ( nurl_free # s buf )
            ( nurl_print `\n` )
            ( lw_close w )
            ^ 0
        }
    }
}
