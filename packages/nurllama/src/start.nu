// packages/nurllama/src/start.nu — the `nurllama start` wizard.
//
// Interactive setup: pick a model from the models directory (and the
// pull store), choose whether the server binds to localhost only or is
// reachable from the network, whether a network server is open or gated
// by a bearer token, and the port. The answers are written to
// $NURLLAMA_HOME/config.json (see config.nu) and the server starts.
//
// A second `nurllama start` finds the config and offers to reuse it;
// `nurllama start -y` reuses it without asking.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/uuid.nu`
$ `src/config.nu`
$ `src/store.nu`
$ `src/api.nu`
$ `src/convert.nu`

: ModelEntry {
    String value
    String label
}

// A prompt printed without a trailing newline, then a trimmed line of
// input. Empty input (bare Enter) returns "".
@ __st_ask s prompt → String {
    ( nurl_print prompt )
    ( flush )
    : String raw ( read_line )
    : String t ( __st_trim raw )
    ( string_free raw )
    ^ t
}

@ __st_trim String s → String {
    : i n ( string_len s )
    : ~ i a 0
    : ~ i b n
    ~ & < a b ( __st_ws ( nurl_str_get ( string_data s ) a ) ) { = a + a 1 }
    ~ & > b a ( __st_ws ( nurl_str_get ( string_data s ) - b 1 ) ) { = b - b 1 }
    ^ ( string_substr s a - b a )
}

@ __st_ws i c → b { ^ | | | == c 32 == c 9 == c 10 == c 13 }

// A directory exists iff it can be listed.
@ __st_is_dir s path → b {
    ?? ( dir_list path ) {
        T v → {
            ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
            ^ T
        }
        F _ → { ^ F }
    }
}

// A yes/no prompt. `def_yes` decides the answer to a bare Enter.
@ __st_yesno s prompt b def_yes → b {
    : String a ( __st_ask prompt )
    : i n ( string_len a )
    : ~ b r def_yes
    ? > n 0 {
        : i c0 ( __st_lower ( nurl_str_get ( string_data a ) 0 ) )
        ? == c0 121 { = r T } {}
        ? == c0 110 { = r F } {}
    } {}
    ( string_free a )
    ^ r
}

@ __st_lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

@ __st_free_entries ( Vec ModelEntry ) v → v {
    ( vec_free_with [ModelEntry] v \ ModelEntry e → v {
        ( string_free . e value )
        ( string_free . e label )
    } )
}

// Is `dir` a Hugging Face checkpoint — a directory carrying config.json
// and at least one *.safetensors? Such a directory is not servable as
// is (a .safetensors file holds only tensors — no hyperparameters, no
// tokenizer), but it CAN be converted to a GGUF, which is what the
// wizard offers. A single loose *.safetensors is deliberately NOT
// listed: on its own it cannot be loaded.
@ __st_is_checkpoint s dir → b {
    : String cfg ( path_join dir `config.json` )
    : b has_cfg ( file_exists ( string_data cfg ) )
    ( string_free cfg )
    ? has_cfg {} { ^ F }
    : ~ b has_st F
    ?? ( dir_list dir ) {
        T names → {
            : ~ i k 0
            ~ & ! has_st < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → { ? != 0 ( nurl_str_ends ( string_data nm ) `.safetensors` ) { = has_st T } {} }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    ^ has_st
}

// Collect selectable models: every *.gguf in `models_dir` (as a full
// path), every immediate subdirectory that is a Hugging Face checkpoint
// (offered for conversion, value prefixed `convert:`), and every
// pull-store manifest name (resolved at serve time).
@ __st_collect s models_dir String root → ( Vec ModelEntry ) {
    : ( Vec ModelEntry ) out ( vec_new [ModelEntry] )
    ?? ( dir_list models_dir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? != 0 ( nurl_str_ends ( string_data nm ) `.gguf` ) {
                            : String full ( path_join models_dir ( string_data nm ) )
                            : String label ( string_from ( string_data nm ) )
                            ( string_push_str label `   (` )
                            ?? ( file_size ( string_data full ) ) {
                                T sz → {
                                    : String hs ( __st_human sz )
                                    ( string_push_str label ( string_data hs ) )
                                    ( string_free hs )
                                }
                                F _ → { ( string_push_str label `?` ) }
                            }
                            ( string_push_str label `)` )
                            ( vec_push [ModelEntry] out @ ModelEntry { full label } )
                        } {
                            // a subdirectory that is an HF checkpoint → convert
                            : String sub ( path_join models_dir ( string_data nm ) )
                            ? & ( __st_is_dir ( string_data sub ) ) ( __st_is_checkpoint ( string_data sub ) ) {
                                : String value ( string_from `convert:` )
                                ( string_push_str value ( string_data sub ) )
                                : String label ( string_from ( string_data nm ) )
                                ( string_push_str label `/   (HF checkpoint → convert to GGUF)` )
                                ( vec_push [ModelEntry] out @ ModelEntry { value label } )
                            } {}
                            ( string_free sub )
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    // pull-store manifests
    : String mdir ( path_join ( string_data root ) `manifests` )
    ?? ( dir_list ( string_data mdir ) ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String value ( string_from ( string_data nm ) )
                        : String label ( string_from ( string_data nm ) )
                        ( string_push_str label `   (pulled)` )
                        ( vec_push [ModelEntry] out @ ModelEntry { value label } )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    ( string_free mdir )
    ^ out
}

@ __st_human i bytes → String {
    : String s ( string_new )
    ? >= bytes 1073741824 {
        ( string_push_int s / bytes 1073741824 )
        ( string_push_str s `.` )
        ( string_push_int s % / * bytes 10 1073741824 10 )
        ( string_push_str s ` GB` )
    } {
        ( string_push_int s / bytes 1048576 )
        ( string_push_str s ` MB` )
    }
    ^ s
}

// The last path segment of String `p` (its basename), without a
// trailing '/'. String-in / String-out, so ownership is clean.
@ __st_basename String p → String {
    : i n ( string_len p )
    : ~ i end n
    ~ & > end 0 == ( nurl_str_get ( string_data p ) - end 1 ) 47 { = end - end 1 }
    : ~ i start end
    ~ & > start 0 != ( nurl_str_get ( string_data p ) - start 1 ) 47 { = start - start 1 }
    ^ ( string_substr p start - end start )
}

// Convert the HF checkpoint named by a `convert:<dir>` value to a Q8_0
// GGUF beside it in `models_dir`, and return the GGUF path (empty on
// failure). An already-converted GGUF is reused after confirmation.
@ __st_convert_checkpoint s models_dir s value → String {
    : String valS ( string_from value )
    : String dirS ( string_substr valS 8 - ( string_len valS ) 8 )
    ( string_free valS )
    : s dir ( string_data dirS )
    : String base ( __st_basename dirS )
    : String out ( path_join models_dir ( string_data base ) )
    ( string_push_str out `-q8_0.gguf` )
    ( string_free base )
    // result: the servable GGUF path, or "" on decline / failure
    : ~ String result ( string_new )
    : ~ b resolved F
    ? ( file_exists ( string_data out ) ) {
        : String q ( string_from `Found ` )
        ( string_push_str q ( string_data out ) )
        ( string_push_str q ` — reuse it (skip conversion)? [Y/n]: ` )
        : b reuse ( __st_yesno ( string_data q ) T )
        ( string_free q )
        ? reuse {
            ( string_free result )
            = result ( string_from ( string_data out ) )
            = resolved T
        } {}
    } {}
    ? resolved {} {
        : String q2 ( string_from `\nConvert ` )
        ( string_push_str q2 dir )
        ( string_push_str q2 ` to Q8_0 GGUF? This can take a few minutes. [Y/n]: ` )
        : b go ( __st_yesno ( string_data q2 ) T )
        ( string_free q2 )
        ? go {
            ( nurl_print `\nConverting — see progress below.\n` )
            : i rc ( nurllama_convert dir ( string_data out ) `q8_0` )
            ? == rc 0 {
                : String done ( string_from `Converted → ` )
                ( string_push_str done ( string_data out ) )
                ( string_push_char done 10 )
                ( nurl_print ( string_data done ) )
                ( string_free done )
                ( string_free result )
                = result ( string_from ( string_data out ) )
            } {
                ( nurl_eprintln `nurllama: conversion failed — pick another model or convert manually` )
            }
        } {}
    }
    ( string_free out )
    ( string_free dirS )
    ^ result
}

// Prompt for an integer with a default (bare Enter → def).
@ __st_ask_int s prompt i def → i {
    : String a ( __st_ask prompt )
    : ~ i v def
    ? > ( string_len a ) 0 {
        ?? ( string_to_int a ) { T x → { = v x } F _ → {} }
    } {}
    ( string_free a )
    ^ v
}

// Run the full wizard, seeded with `prev` (an existing config or a
// fresh default). Returns an owned NlConfig the caller saves + serves.
@ __st_wizard String root NlConfig prev → NlConfig {
    ( nurl_print `\n── nurllama setup ──\n\n` )

    // 1. models directory (owned — def_dir must outlive the temporaries
    // it is derived from, so it is a String, not a borrowed pointer)
    : ~ String def_dir ( string_from ( string_data . prev models_dir ) )
    ? == 0 ( string_len def_dir ) {
        : String home ( env_var_or `HOME` `.` )
        : String md ( path_join ( string_data home ) `models` )
        ( string_free def_dir )
        = def_dir ? ( __st_is_dir ( string_data md ) ) ( string_from ( string_data md ) ) ( string_from ( string_data root ) )
        ( string_free md )
        ( string_free home )
    } {}
    : String dprompt ( string_from `Models directory [` )
    ( string_push_str dprompt ( string_data def_dir ) )
    ( string_push_str dprompt `]: ` )
    : String md_in ( __st_ask ( string_data dprompt ) )
    ( string_free dprompt )
    : String models_dir ? > ( string_len md_in ) 0 ( string_from ( string_data md_in ) ) ( string_from ( string_data def_dir ) )
    ( string_free md_in )
    ( string_free def_dir )

    // 2. model selection
    : ( Vec ModelEntry ) models ( __st_collect ( string_data models_dir ) root )
    : i nm ( vec_len [ModelEntry] models )
    : ~ String model ( string_from ( string_data . prev model ) )
    ? == nm 0 {
        ( nurl_print `\nNo .gguf models found there and no pulled models.\n` )
        : String mprompt ( string_from `Model path or store name: ` )
        : String m_in ( __st_ask ( string_data mprompt ) )
        ( string_free mprompt )
        ? > ( string_len m_in ) 0 {
            ( string_free model )
            = model m_in
        } { ( string_free m_in ) }
    } {
        ( nurl_print `\nModels:\n` )
        : ~ i k 0
        ~ < k nm {
            ?? ( vec_get [ModelEntry] models k ) {
                T e → {
                    : String line ( string_new )
                    ( string_push_str line `  ` )
                    ( string_push_int line + k 1 )
                    ( string_push_str line `) ` )
                    ( string_push_str line ( string_data . e label ) )
                    ( string_push_char line 10 )
                    ( nurl_print ( string_data line ) )
                    ( string_free line )
                }
                F → {}
            }
            = k + k 1
        }
        : i pick ( __st_ask_int `\nChoose a model [1]: ` 1 )
        : i idx ? & >= pick 1 <= pick nm - pick 1 0
        ?? ( vec_get [ModelEntry] models idx ) {
            T e → {
                ( string_free model )
                = model ( string_from ( string_data . e value ) )
            }
            F → {}
        }
    }
    ( __st_free_entries models )

    // 2b. a chosen HF checkpoint is converted to a GGUF here
    ? != 0 ( nurl_str_starts ( string_data model ) `convert:` ) {
        : String conv ( __st_convert_checkpoint ( string_data models_dir ) ( string_data model ) )
        ( string_free model )
        = model conv
    } {}

    // 3. bind scope
    ( nurl_print `\nNetwork:\n  1) localhost only (127.0.0.1)\n  2) reachable from the network (0.0.0.0)\n` )
    : i net ( __st_ask_int `Choose [1]: ` 1 )
    : String host ? == net 2 ( string_from `0.0.0.0` ) ( string_from `127.0.0.1` )

    // 4. auth (only meaningful for a network server)
    : ~ String auth ( string_from `open` )
    : ~ String token ( string_new )
    ? == net 2 {
        ( nurl_print `\nAccess:\n  1) require a bearer token\n  2) open (anyone who can reach the port)\n` )
        : i am ( __st_ask_int `Choose [1]: ` 1 )
        ? != am 2 {
            ( string_free auth )
            = auth ( string_from `token` )
            : String tprompt ( string_from `Token [Enter = generate]: ` )
            : String t_in ( __st_ask ( string_data tprompt ) )
            ( string_free tprompt )
            ( string_free token )
            = token ? > ( string_len t_in ) 0 ( string_from ( string_data t_in ) ) ( uuid_v4 )
            ( string_free t_in )
        } {}
    } {}

    // 5. port
    : i port ( __st_ask_int `\nPort [11434]: ` ? > . prev port 0 . prev port 11434 )

    ^ @ NlConfig { model host port auth token models_dir }
}

// Print a summary of the config being served.
@ __st_summary NlConfig c → v {
    ( nurl_print `\n── serving ──\n` )
    ( nurl_print `  model : ` ) ( nurl_print ( string_data . c model ) ) ( nurl_print `\n` )
    ( nurl_print `  bind  : ` ) ( nurl_print ( string_data . c host ) )
    ( nurl_print `:` ) ( nurl_print ( nurl_str_int . c port ) ) ( nurl_print `\n` )
    ( nurl_print `  access: ` )
    ? ( nurl_str_eq ( string_data . c auth ) `token` ) {
        ( nurl_print `token — ` )
        ( nurl_print ( string_data . c token ) )
        ( nurl_print `\n` )
    } { ( nurl_print `open\n` ) }
    : String url ( string_from `  web   : http://` )
    ( string_push_str url ? ( nurl_str_eq ( string_data . c host ) `0.0.0.0` ) `<this-host>` ( string_data . c host ) )
    ( string_push_char url 58 )
    ( string_push_int url . c port )
    ( string_push_char url 10 )
    ( nurl_print ( string_data url ) )
    ( string_free url )
    ( nurl_print `\n` )
}

// `nurllama start [-y]`. Returns the server's exit code.
@ nurllama_start ArgParser p → i {
    : String root ( nl_store_root )
    : b assume_yes ( args_present p `yes` )

    : ~ b have_cfg F
    : ~ NlConfig cfg @ NlConfig {
        ( string_new ) ( string_from `127.0.0.1` ) 11434
        ( string_from `open` ) ( string_new ) ( string_new )
    }

    ? ( cfg_exists root ) {
        : ~ b reuse assume_yes
        ? assume_yes {} {
            : String cp ( cfg_path root )
            : String q ( string_from `Found a config at ` )
            ( string_push_str q ( string_data cp ) )
            ( string_push_str q `. Use it? [Y/n]: ` )
            ( string_free cp )
            = reuse ( __st_yesno ( string_data q ) T )
            ( string_free q )
        }
        ? reuse {
            ?? ( cfg_load root ) {
                T lc → {
                    ( cfg_free cfg )
                    = cfg lc
                    = have_cfg T
                }
                F → {}
            }
        } {}
    } {}

    ? have_cfg {} {
        // wizard, seeded with whatever cfg holds (loaded prev or default)
        : ~ NlConfig prev @ NlConfig {
            ( string_new ) ( string_from `127.0.0.1` ) 11434
            ( string_from `open` ) ( string_new ) ( string_new )
        }
        // seed from an existing (but declined) config if present
        ? ( cfg_exists root ) {
            ?? ( cfg_load root ) {
                T lc → {
                    ( cfg_free prev )
                    = prev lc
                }
                F → {}
            }
        } {}
        : NlConfig nc ( __st_wizard root prev )
        ( cfg_free prev )
        ( cfg_free cfg )
        = cfg nc
        ? ( cfg_save root cfg ) {
            : String cp ( cfg_path root )
            : String msg ( string_from `\nSaved config → ` )
            ( string_push_str msg ( string_data cp ) )
            ( string_push_char msg 10 )
            ( nurl_print ( string_data msg ) )
            ( string_free msg )
            ( string_free cp )
        } {
            ( nurl_eprintln `nurllama: could not write the config file` )
        }
    }

    ( __st_summary cfg )
    : i rc ( api_serve_cfg root cfg )
    ( cfg_free cfg )
    ( string_free root )
    ^ rc
}
