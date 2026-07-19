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
//   ( cfg_free cfg )         → v

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

@ cfg_free NlConfig c → v {
    ( string_free . c model )
    ( string_free . c host )
    ( string_free . c auth )
    ( string_free . c token )
    ( string_free . c models_dir )
}

@ cfg_path String root → String {
    ^ ( path_join ( string_data root ) `config.json` )
}

@ cfg_exists String root → b {
    : String p ( cfg_path root )
    : b e ( file_exists ( string_data p ) )
    ( string_free p )
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

// Load the config, or None when it is absent or unparseable. The
// caller owns the returned NlConfig (cfg_free).
@ cfg_load String root → ?NlConfig {
    : String p ( cfg_path root )
    : ~ i addr 0
    ?? ( read_file ( string_data p ) ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T j → {
                    // Build directly into a heap NlConfig and hand back its
                    // pointer — no placeholder to leak on the success path.
                    : *NlConfig c # *NlConfig ( nurl_alloc Z NlConfig )
                    = . c model ( __cfg_str j `model` `` )
                    = . c host ( __cfg_str j `host` `127.0.0.1` )
                    = . c port ( __cfg_int j `port` 11434 )
                    = . c auth ( __cfg_str j `auth` `open` )
                    = . c token ( __cfg_str j `token` `` )
                    = . c models_dir ( __cfg_str j `models_dir` `` )
                    = addr # i c
                    ( json_free j )
                }
                F e → { ( string_free ( json_format_error e ) ) }
            }
            ( string_free txt )
        }
        F _ → {}
    }
    ( string_free p )
    ? != addr 0 {
        : *NlConfig c # *NlConfig addr
        : NlConfig out @ NlConfig { . c model . c host . c port . c auth . c token . c models_dir }
        ( nurl_free # s c )
        ^ @ ?NlConfig { T out }
    } {}
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
    ( json_free j )
    ( string_push_char txt 10 )
    : String p ( cfg_path root )
    : b ok ?? ( write_file ( string_data p ) ( string_data txt ) ) { T _ → { T } F _ → { F } }
    ( string_free p )
    ( string_free txt )
    ^ ok
}
