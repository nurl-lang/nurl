// packages/nurllama/src/chat.nu — chat templates.
//
// Turns a message list into the exact prompt string a chat-tuned model
// was trained on. The template is chosen from the model's own GGUF
// metadata: `tokenizer.chat_template` is matched against the shapes we
// know, and the architecture/BOS conventions fill the rest — so a model
// carries its own dialect and the caller never guesses.
//
//   ( chat_style_of g )              → i           CHAT_* below
//   ( chat_render style msgs )       → String      prompt for generation
//   ( chat_stop_matches style piece ) → b          stop-token text guard
//
// Styles:
//   CHAT_LLAMA2   [INST] <<SYS>>…<</SYS>> user [/INST] assistant </s>
//   CHAT_LLAMA3   <|start_header_id|>role<|end_header_id|>…<|eot_id|>
//   CHAT_CHATML   <|im_start|>role\n…<|im_end|>   (qwen, many finetunes)
//   CHAT_GEMMA    <start_of_turn>user\n…<end_of_turn>  (gemma; the
//                 assistant's role is spelled "model", and gemma has NO
//                 system role — the system prompt folds into the first
//                 user turn, which is what its own template does)
//   CHAT_PLAIN    no template — the messages are concatenated; a base
//                 (non-chat) model gets its raw prompt, which is the
//                 honest thing to do rather than inventing turns.
//
// A ChatMsg's role is one of `system` / `user` / `assistant`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/gguf/src/gguf.nu`

: i CHAT_PLAIN 0
: i CHAT_LLAMA2 1
: i CHAT_LLAMA3 2
: i CHAT_CHATML 3
: i CHAT_GEMMA 4

: ChatMsg {
    String role
    String content
}

@ chat_msg s role s content → ChatMsg {
    ^ @ ChatMsg { ( string_from role ) ( string_from content ) }
}

@ chat_msg_free ChatMsg m → v {
    ( string_free . m role )
    ( string_free . m content )
}

@ chat_msgs_free ( Vec ChatMsg ) v → v {
    ( vec_free_with [ChatMsg] v \ ChatMsg m → v { ( chat_msg_free m ) } )
}

// Pick the style from the model's own chat template (substring match on
// the marker tokens each dialect must contain), falling back to PLAIN
// when the model ships no template — a base model, honestly served.
@ chat_style_of * Gguf g → i {
    : s tpl ( gguf_kv_str_or g `tokenizer.chat_template` `` )
    ? > ( nurl_str_len tpl ) 0 {
        ? >= ( nurl_str_find tpl `<|im_start|>` ) 0 { ^ CHAT_CHATML } {}
        ? >= ( nurl_str_find tpl `<|start_header_id|>` ) 0 { ^ CHAT_LLAMA3 } {}
        ? >= ( nurl_str_find tpl `[INST]` ) 0 { ^ CHAT_LLAMA2 } {}
        ? >= ( nurl_str_find tpl `<start_of_turn>` ) 0 { ^ CHAT_GEMMA } {}
    } {}
    ^ CHAT_PLAIN
}

@ __chat_role ChatMsg m → s { ^ ( string_data . m role ) }

@ __chat_text ChatMsg m → s { ^ ( string_data . m content ) }

@ __chat_is ChatMsg m s want → b { ^ ? ( nurl_str_eq ( __chat_role m ) want ) T F }

// llama-2: one [INST] block per user turn, the system prompt folded
// into the FIRST block, assistant replies closed with </s>.
@ __chat_llama2 ( Vec ChatMsg ) msgs → String {
    : String out ( string_new )
    : ~ String sys ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? ( __chat_is m `system` ) {
                    ( string_free sys )
                    = sys ( string_from ( __chat_text m ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    : ~ b first T
    = k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? ( __chat_is m `user` ) {
                    ( string_push_str out `[INST] ` )
                    ? & first > ( string_len sys ) 0 {
                        ( string_push_str out `<<SYS>>\n` )
                        ( string_push_str out ( string_data sys ) )
                        ( string_push_str out `\n<</SYS>>\n\n` )
                    } {}
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out ` [/INST] ` )
                    = first F
                } {}
                ? ( __chat_is m `assistant` ) {
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out ` </s>` )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( string_free sys )
    ^ out
}

@ __chat_llama3 ( Vec ChatMsg ) msgs → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ( string_push_str out `<|start_header_id|>` )
                ( string_push_str out ( __chat_role m ) )
                ( string_push_str out `<|end_header_id|>\n\n` )
                ( string_push_str out ( __chat_text m ) )
                ( string_push_str out `<|eot_id|>` )
            }
            F → {}
        }
        = k + k 1
    }
    ( string_push_str out `<|start_header_id|>assistant<|end_header_id|>\n\n` )
    ^ out
}

@ __chat_chatml ( Vec ChatMsg ) msgs → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ( string_push_str out `<|im_start|>` )
                ( string_push_str out ( __chat_role m ) )
                ( string_push_char out 10 )
                ( string_push_str out ( __chat_text m ) )
                ( string_push_str out `<|im_end|>\n` )
            }
            F → {}
        }
        = k + k 1
    }
    ( string_push_str out `<|im_start|>assistant\n` )
    ^ out
}

// gemma: <start_of_turn>ROLE\n … <end_of_turn>\n, where the assistant is
// called "model". gemma's own template REJECTS a system role, so a system
// prompt is prepended to the first user turn (two newlines), exactly as the
// upstream template does.
@ __chat_gemma ( Vec ChatMsg ) msgs → String {
    : String out ( string_new )
    : ~ String sys ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? ( __chat_is m `system` ) {
                    ( string_free sys )
                    = sys ( string_from ( __chat_text m ) )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    : ~ b first T
    = k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? ( __chat_is m `system` ) {} {
                    : b usr ( __chat_is m `user` )
                    ( string_push_str out `<start_of_turn>` )
                    ( string_push_str out ? usr `user` `model` )
                    ( string_push_char out 10 )
                    ? & & usr first > ( string_len sys ) 0 {
                        ( string_push_str out ( string_data sys ) )
                        ( string_push_str out `\n\n` )
                    } {}
                    ? usr { = first F } {}
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out `<end_of_turn>\n` )
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( string_push_str out `<start_of_turn>model\n` )
    ( string_free sys )
    ^ out
}

// Base model: no invented turns — system + user text, blank-line
// separated, which is what a completion model actually expects.
@ __chat_plain ( Vec ChatMsg ) msgs → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? ( __chat_is m `assistant` ) {} {
                    ? > ( string_len out ) 0 { ( string_push_str out `\n\n` ) } {}
                    ( string_push_str out ( __chat_text m ) )
                }
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ chat_render i style ( Vec ChatMsg ) msgs → String {
    ? == style CHAT_LLAMA3 { ^ ( __chat_llama3 msgs ) } {}
    ? == style CHAT_CHATML { ^ ( __chat_chatml msgs ) } {}
    ? == style CHAT_LLAMA2 { ^ ( __chat_llama2 msgs ) } {}
    ? == style CHAT_GEMMA { ^ ( __chat_gemma msgs ) } {}
    ^ ( __chat_plain msgs )
}

// Some chat models emit their turn terminator as ordinary text rather
// than the EOS id (a finetune whose eos_token_id was left at the base
// value). Treat the dialect's terminator as a stop sequence too.
@ chat_stop_matches i style s piece → b {
    ? == style CHAT_CHATML { ^ ? >= ( nurl_str_find piece `<|im_end|>` ) 0 T F } {}
    ? == style CHAT_LLAMA3 { ^ ? >= ( nurl_str_find piece `<|eot_id|>` ) 0 T F } {}
    ? == style CHAT_LLAMA2 { ^ ? >= ( nurl_str_find piece `</s>` ) 0 T F } {}
    ? == style CHAT_GEMMA { ^ ? >= ( nurl_str_find piece `<end_of_turn>` ) 0 T F } {}
    ^ F
}
