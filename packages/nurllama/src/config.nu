// packages/nurllama/src/config.nu — the `nurllama start` config file.
//
// A small JSON file at $NURLLAMA_HOME/config.json (default
// ~/.nurllama/config.json) that remembers the wizard's choices so a
// second `nurllama start` can reuse them:
//
//   { "model":      "<path or store name>",
//     "host":       "127.0.0.1" | "0.0.0.0",
//     "port":       11434,
//     "auth":       "open" | "token",
//     "token":      "<bearer token, when auth=token>",
//     "models_dir": "<directory the wizard scans for *.gguf>" }
//
//   ( cfg_path root )        → String   the config file path (owned)
//   ( cfg_exists root )      → b
//   ( cfg_load root )        → ?NlConfig
//   ( cfg_save root cfg )    → b

$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/json.nu`

: NlConfig {
    String model
    String host
    i port
    String auth
    String token
    String models_dir
}

@ cfg_path String root → String {
    ^ ( path_join ( string_data root ) `config.json` )
}

@ cfg_exists String root → b {
    : String p ( cfg_path root )
    : b e ( file_exists ( string_data p ) )
    ^ e
}

@ __cfg_str Json j s key s def → String {
    ?? ( json_obj_get j key ) {
        T v → { ^ ( string_from ( json_str_data v ) ) }
        F → { ^ ( string_from def ) }
    }
}

@ __cfg_int Json j s key i def → i {
    ?? ( json_obj_get j key ) {
        T v → { ?? ( json_num_as_i v ) { T n → { ^ n } F → {} } }
        F → {}
    }
    ^ def
}

// Load the config, or None when it is absent or unparseable.
@ cfg_load String root → ?NlConfig {
    : String p ( cfg_path root )
    ?? ( read_file ( string_data p ) ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T j → {
                    ^ @ ?NlConfig { T @ NlConfig {
                            ( __cfg_str j `model` `` )
                            ( __cfg_str j `host` `127.0.0.1` )
                            ( __cfg_int j `port` 11434 )
                            ( __cfg_str j `auth` `open` )
                            ( __cfg_str j `token` `` )
                            ( __cfg_str j `models_dir` `` )
                        } }
                }
                F _e → {}
            }
        }
        F _ → {}
    }
    ^ @ ?NlConfig { F }
}

// Serialise + write. Returns T on success. Creates $NURLLAMA_HOME if
// it does not exist (the store already does, but a fresh box may not).
@ cfg_save String root NlConfig c → b {
    ?? ( dir_create_all ( string_data root ) ) { T _ → {} F _ → {} }
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `model` ( json_str_lit ( string_data . c model ) ) )
    : b _2 ( json_obj_set j `host` ( json_str_lit ( string_data . c host ) ) )
    : b _3 ( json_obj_set j `port` ( json_int . c port ) )
    : b _4 ( json_obj_set j `auth` ( json_str_lit ( string_data . c auth ) ) )
    : b _5 ( json_obj_set j `token` ( json_str_lit ( string_data . c token ) ) )
    : b _6 ( json_obj_set j `models_dir` ( json_str_lit ( string_data . c models_dir ) ) )
    : String txt ( json_pretty j )
    ( string_push_char txt 10 )
    : String p ( cfg_path root )
    : b ok ?? ( write_file ( string_data p ) ( string_data txt ) ) { T _ → { T } F _ → { F } }
    ^ ok
}
