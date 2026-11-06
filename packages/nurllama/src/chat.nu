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
//   CHAT_CHATML_NT  ChatML whose template thinks only when asked
//                 (Qwen3.5, Qwen3.8: `enable_thinking is defined and
//                 enable_thinking is true`): by default its generation
//                 prompt closes an empty <think></think> block, so the
//                 model answers instead of reasoning aloud.
//   CHAT_PHI3     <|user|>\n…<|end|>\n<|assistant|>\n  (phi-3/3.5/4)
//   CHAT_GEMMA    <start_of_turn>user\n…<end_of_turn>  (gemma; the
//                 assistant's role is spelled "model", and gemma has NO
//                 system role — the system prompt folds into the first
//                 user turn, which is what its own template does)
//   CHAT_GLM5     [gMASK]<sop><|system|>…<|user|>…<|assistant|>…  (GLM-5,
//                 GLM-5.1: no newlines between turns; an earlier assistant
//                 turn is `</think>` + its answer, the last one keeps its
//                 <think>reasoning</think>; the generation prompt opens
//                 <think>)
//   CHAT_GLM53    GLM-5.2 / GLM-5.3: the same turns, opened by the
//                 template's `<|system|>Reasoning Effort: Max` (its default
//                 effort), and an assistant turn always carries its
//                 <think>…</think> block, empty when it has none
//   CHAT_PLAIN    no template — the messages are concatenated; a base
//                 (non-chat) model gets its raw prompt, which is the
//                 honest thing to do rather than inventing turns.
//
// A ChatMsg's role is one of `system` / `user` / `assistant`. An assistant
// message may carry its reasoning separately (OpenAI's `reasoning_content`,
// ollama's `thinking`) — a template that reads m.reasoning_content gets it.
//
// ChatOpts are the template's own switches, rendered as the template
// renders them: `effort` (GLM-5.3's reasoning_effort: low | high, any other
// value Max, its default) and `thinking` (GLM-5's enable_thinking: 0 = off
// — the generation prompt closes the think block at once —, 1 = on, -1 =
// not given).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/gguf/src/gguf.nu`

: i CHAT_PLAIN 0
: i CHAT_LLAMA2 1
: i CHAT_LLAMA3 2
: i CHAT_CHATML 3
: i CHAT_GEMMA 4
: i CHAT_PHI3 5
: i CHAT_BAILING 6
: i CHAT_CHATML_NT 7
: i CHAT_GLM5 8
: i CHAT_GLM53 9

: ChatMsg {
    String role
    String content
    b has_reasoning
    String reasoning
}

@ chat_msg s role s content → ChatMsg {
    ^ @ ChatMsg { ( string_from role ) ( string_from content ) F ( string_new ) }
}

// An assistant message with its reasoning given apart from its text.
@ chat_msg_r s role s content s reasoning → ChatMsg {
    ^ @ ChatMsg { ( string_from role ) ( string_from content ) T ( string_from reasoning ) }
}

: ChatOpts {
    String effort
    i thinking
}

@ chat_opts_none → ChatOpts { ^ @ ChatOpts { ( string_new ) -1 } }

// Pick the style from the model's own chat template (substring match on
// the marker tokens each dialect must contain), falling back to PLAIN
// when the model ships no template — a base model, honestly served.
@ chat_style_of Gguf g → i {
    : s tpl ( gguf_kv_str_or g `tokenizer.chat_template` `` )
    ? > ( nurl_str_len tpl ) 0 {
        // GLM before the other `<|assistant|>` dialects: its turn tags are
        // phi3's, its format is not
        ? >= ( nurl_str_find tpl `[gMASK]<sop>` ) 0 {
            ? >= ( nurl_str_find tpl `Reasoning Effort` ) 0 { ^ CHAT_GLM53 } {}
            ^ CHAT_GLM5
        } {}
        ? >= ( nurl_str_find tpl `<|im_start|>` ) 0 {
            ? >= ( nurl_str_find tpl `enable_thinking is defined and enable_thinking is true` ) 0 { ^ CHAT_CHATML_NT } {}
            ^ CHAT_CHATML
        } {}
        ? >= ( nurl_str_find tpl `<|start_header_id|>` ) 0 { ^ CHAT_LLAMA3 } {}
        ? >= ( nurl_str_find tpl `[INST]` ) 0 { ^ CHAT_LLAMA2 } {}
        ? >= ( nurl_str_find tpl `<start_of_turn>` ) 0 { ^ CHAT_GEMMA } {}
        ? >= ( nurl_str_find tpl `<|assistant|>` ) 0 { ^ CHAT_PHI3 } {}
        ? >= ( nurl_str_find tpl `<role>HUMAN</role>` ) 0 { ^ CHAT_BAILING } {}
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

@ __chat_chatml ( Vec ChatMsg ) msgs b nothink → String {
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
    ? nothink { ( string_push_str out `<think>\n\n</think>\n\n` ) } {}
    ^ out
}

// phi-3: <|ROLE|>\n … <|end|>\n per turn, system included, then the open
// <|assistant|> tag the model completes.
@ __chat_phi3 ( Vec ChatMsg ) msgs → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ( string_push_str out `<|` )
                ( string_push_str out ( __chat_role m ) )
                ( string_push_str out `|>\n` )
                ( string_push_str out ( __chat_text m ) )
                ( string_push_str out `<|end|>\n` )
            }
            F → {}
        }
        = k + k 1
    }
    ( string_push_str out `<|assistant|>\n` )
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

// The index of the last user turn, -1 when there is none.
@ __chat_last_user ( Vec ChatMsg ) msgs → i {
    : ~ i last -1
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ? ( __chat_is ( vec_at [ChatMsg] msgs k ) `user` ) { = last k } {}
        = k + k 1
    }
    ^ last
}

// Python's str.split(sep)[0] and [-1]: the text before the FIRST `sep`,
// and after the LAST (the whole text when there is none).
@ __chat_before_first String t s sep → String {
    : i at ( nurl_str_find ( string_data t ) sep )
    ? < at 0 { ^ ( string_clone t ) } {}
    ^ ( string_substr t 0 at )
}

@ __chat_after_last String t s sep → String {
    : i sl ( nurl_str_len sep )
    : ~ String rest ( string_clone t )
    : ~ i at ( nurl_str_find ( string_data rest ) sep )
    ~ >= at 0 {
        = rest ( string_substr rest + at sl - - ( string_len rest ) at sl )
        = at ( nurl_str_find ( string_data rest ) sep )
    }
    ^ rest
}

// Strip only newlines at one end (Python's rstrip('\n') / lstrip('\n')).
@ __chat_rstrip_nl String t → String {
    : ~ i n ( string_len t )
    ~ & > n 0 == ( string_get t - n 1 ) 10 { = n - n 1 }
    ^ ( string_substr t 0 n )
}

@ __chat_lstrip_nl String t → String {
    : i n ( string_len t )
    : ~ i k 0
    ~ & < k n == ( string_get t k ) 10 { = k + k 1 }
    ^ ( string_substr t k - n k )
}

// GLM-5.x, turn by turn, as its template renders text messages: no
// separator between turns; a system or user turn is its tag and its text.
// An assistant turn's reasoning is the part of its text before `</think>`
// (after any `<think>`), its answer the part after the last `</think>`.
//   glm53  GLM-5.2 / 5.3: the prompt opens with the template's default
//          `<|system|>Reasoning Effort: Max`; every assistant turn writes
//          <think>reasoning</think> (empty when it has none) and its
//          stripped answer
//   glm5   GLM-5 / 5.1: reasoning and answer lose their newlines at the
//          seam; only an assistant turn after the last user turn keeps
//          <think>reasoning</think> (and only a non-empty one), an earlier
//          one writes `</think>`
// The generation prompt is `<|assistant|><think>`: both templates reason
// by default.
@ __chat_glm ( Vec ChatMsg ) msgs b glm53 ChatOpts o → String {
    : String out ( string_from `[gMASK]<sop>` )
    ? glm53 {
        // `reasoning_effort if … in ['low', 'high'] else 'max'`, capitalised
        : s eff ( string_data . o effort )
        ( string_push_str out `<|system|>Reasoning Effort: ` )
        ( string_push_str out ? ( nurl_str_eq eff `low` ) `Low` ? ( nurl_str_eq eff `high` ) `High` `Max` )
    } {}
    : i last_user ( __chat_last_user msgs )
    : ~ i k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        : ChatMsg m ( vec_at [ChatMsg] msgs k )
        ? ( __chat_is m `system` ) {
            ( string_push_str out `<|system|>` )
            ( string_push_str out ( __chat_text m ) )
        } {}
        ? ( __chat_is m `user` ) {
            ( string_push_str out `<|user|>` )
            ( string_push_str out ( __chat_text m ) )
        } {}
        ? ( __chat_is m `assistant` ) {
            ( string_push_str out `<|assistant|>` )
            : ~ String answer ( string_clone . m content )
            : ~ String reasoning ( string_new )
            // reasoning given apart (m.reasoning_content) is taken as it is,
            // and the text is then all answer; otherwise it is cut out of
            // the text at `</think>`
            : b has_think | . m has_reasoning >= ( nurl_str_find ( __chat_text m ) `</think>` ) 0
            ? . m has_reasoning { = reasoning ( string_clone . m reasoning ) } {}
            ? & has_think ! . m has_reasoning {
                : String head ( __chat_before_first . m content `</think>` )
                ? glm53 {
                    = reasoning ( __chat_after_last head `<think>` )
                    = answer ( __chat_after_last . m content `</think>` )
                } {
                    = reasoning ( __chat_lstrip_nl ( __chat_after_last ( __chat_rstrip_nl head ) `<think>` ) )
                    = answer ( __chat_lstrip_nl ( __chat_after_last . m content `</think>` ) )
                }
            } {}
            ? glm53 {
                ( string_push_str out `<think>` )
                ? has_think { ( string_push_str out ( string_data reasoning ) ) } {}
                ( string_push_str out `</think>` )
            } {
                // (non-empty BEFORE the strip, as the template tests it)
                : String rs ( string_trim reasoning )
                ? & > k last_user > ( string_len reasoning ) 0 {
                    ( string_push_str out `<think>` )
                    ( string_push_str out ( string_data rs ) )
                    ( string_push_str out `</think>` )
                } { ( string_push_str out `</think>` ) }
            }
            : String ans ( string_trim answer )
            ( string_push_str out ( string_data ans ) )
        } {}
        = k + k 1
    }
    // GLM-5's `'</think>' if (enable_thinking is defined and not
    // enable_thinking) else '<think>'` (GLM-5.3's template has no switch)
    ? & ! glm53 == . o thinking 0 { ( string_push_str out `<|assistant|></think>` ) } { ( string_push_str out `<|assistant|><think>` ) }
    ^ out
}

// bailing / Ling 2.0 / LLaDA2: every prompt opens with a SYSTEM turn —
// the (optional) system message, then the template's own literal
// `detailed thinking off` switch — and each turn closes with
// <|role_end|>. The generation prompt is a bare ASSISTANT role tag.
@ __chat_bailing ( Vec ChatMsg ) msgs → String {
    : String out ( string_from `<role>SYSTEM</role>` )
    : ~ i k 0
    : ~ b first_sys T
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? & first_sys ( __chat_is m `system` ) {
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out `\n` )
                } {}
            }
            F → {}
        }
        = first_sys F
        = k + k 1
    }
    ( string_push_str out `detailed thinking off<|role_end|>` )
    = k 0
    ~ < k ( vec_len [ChatMsg] msgs ) {
        ?? ( vec_get [ChatMsg] msgs k ) {
            T m → {
                ? ( __chat_is m `user` ) {
                    ( string_push_str out `<role>HUMAN</role>` )
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out `<|role_end|>` )
                } {}
                ? ( __chat_is m `assistant` ) {
                    ( string_push_str out `<role>ASSISTANT</role>` )
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out `<|role_end|>` )
                } {}
                // messages[0]'s system content is already folded into
                // the opening SYSTEM turn; a later system turn stands
                ? & ( __chat_is m `system` ) > k 0 {
                    ( string_push_str out `<role>SYSTEM</role>` )
                    ( string_push_str out ( __chat_text m ) )
                    ( string_push_str out `<|role_end|>` )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( string_push_str out `<role>ASSISTANT</role>` )
    ^ out
}

@ chat_render i style ( Vec ChatMsg ) msgs → String {
    ^ ( chat_render_opts style msgs ( chat_opts_none ) )
}

// The same, with the template's switches (see ChatOpts); a style without
// such a switch ignores it, as its template does.
@ chat_render_opts i style ( Vec ChatMsg ) msgs ChatOpts o → String {
    ? == style CHAT_LLAMA3 { ^ ( __chat_llama3 msgs ) } {}
    ? == style CHAT_CHATML { ^ ( __chat_chatml msgs F ) } {}
    ? == style CHAT_CHATML_NT { ^ ( __chat_chatml msgs T ) } {}
    ? == style CHAT_LLAMA2 { ^ ( __chat_llama2 msgs ) } {}
    ? == style CHAT_GEMMA { ^ ( __chat_gemma msgs ) } {}
    ? == style CHAT_PHI3 { ^ ( __chat_phi3 msgs ) } {}
    ? == style CHAT_BAILING { ^ ( __chat_bailing msgs ) } {}
    ? == style CHAT_GLM5 { ^ ( __chat_glm msgs F o ) } {}
    ? == style CHAT_GLM53 { ^ ( __chat_glm msgs T o ) } {}
    ^ ( __chat_plain msgs )
}

// Some chat models emit their turn terminator as ordinary text rather
// than the EOS id (a finetune whose eos_token_id was left at the base
// value). Treat the dialect's terminator as a stop sequence too.
@ chat_stop_matches i style s piece → b {
    ? | == style CHAT_CHATML == style CHAT_CHATML_NT { ^ ? >= ( nurl_str_find piece `<|im_end|>` ) 0 T F } {}
    ? == style CHAT_LLAMA3 { ^ ? >= ( nurl_str_find piece `<|eot_id|>` ) 0 T F } {}
    ? == style CHAT_LLAMA2 { ^ ? >= ( nurl_str_find piece `</s>` ) 0 T F } {}
    ? == style CHAT_GEMMA { ^ ? >= ( nurl_str_find piece `<end_of_turn>` ) 0 T F } {}
    ? == style CHAT_PHI3 { ^ ? >= ( nurl_str_find piece `<|end|>` ) 0 T F } {}
    ? == style CHAT_BAILING { ^ ? >= ( nurl_str_find piece `<|role_end|>` ) 0 T F } {}
    // GLM ends its turn by opening the next one
    ? | == style CHAT_GLM5 == style CHAT_GLM53 {
        ^ ? | >= ( nurl_str_find piece `<|user|>` ) 0 >= ( nurl_str_find piece `<|observation|>` ) 0 T F
    } {}
    ^ F
}
