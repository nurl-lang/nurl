// tools/repl/main.nu — `nurl repl`: an interactive read-eval-print loop.
//
// Compiled-language REPL on a process-per-eval model (critic C1). Top-
// level definitions (`@` functions, `&` FFI, `$` imports, and `:` types
// / enums / globals) accumulate into a persistent session; every other
// line is spliced into a fresh `main`, compiled with `./nurl.sh`, and
// run — its stdout is echoed back. Definitions are validated by a fast
// frontend check (`build/nurlc`) before they join the session, so a
// typo never poisons later evaluations.
//
// Line editing + history come from std/term.nu (the B10 work); when
// stdin is not a tty (a pipe or the smoke test) it falls back to plain
// buffered reads. All REPL chrome — prompts, acks, errors, help — goes
// to stderr, so stdout carries only the evaluated program's output and
// stays clean for scripting.
//
//   nurl> @ sq i x → i { ^ * x x }
//   nurl> ( nurl_print ( nurl_str_int ( sq 9 ) ) )
//   81
//
// Meta-commands (':' immediately followed by a letter):
//   :help :h     show this help            :quit :q   leave
//   :defs        list the session defs      :reset    forget all defs
//   :save FILE   write the session to FILE
//
// Run from the repo root (it shells out to ./nurl.sh and build/nurlc).
// Note: process-per-eval means a `:` global is RE-INITIALISED on every
// evaluation — definitions and pure functions persist, but mutation
// does not accumulate across lines.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/term.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/fs.nu`

// strcmp / strncmp are compiler-provided libc builtins (used throughout
// stdlib/core/string.nu) — no FFI declaration needed.

// ── small string utilities ───────────────────────────────────────────

@ __seq s a s b → b { ^ == ( strcmp a b ) 0 }

@ __prefix s str s pre → b {
    : i n ( nurl_str_len pre )
    ^ == ( strncmp str pre n ) 0
}

@ __char_at String s i idx → i {
    ? & >= idx 0 < idx ( string_len s ) { ^ ( string_get s idx ) } {}
    ^ -1
}

@ __is_space i c → b { ^ | | == c 32 == c 9 | == c 13 == c 10 }

@ __trim s raw → String {
    : i n ( nurl_str_len raw )
    : ~ i a 0
    ~ & < a n ( __is_space ( nurl_str_get raw a ) ) { = a + a 1 }
    : ~ i b n
    ~ & > b a ( __is_space ( nurl_str_get raw - b 1 ) ) { = b - b 1 }
    : String out ( string_with_cap + - b a 1 )
    : ~ i k a
    ~ < k b { ( string_push_char out ( nurl_str_get raw k ) ) = k + k 1 }
    ^ out
}

@ __clone_str String s → String {
    : String out ( string_with_cap + ( string_len s ) 1 )
    ( string_push_str out ( string_data s ) )
    ^ out
}

// Net bracket depth, ignoring anything inside a backtick string.
@ __repl_balance s code → i {
    : i n ( nurl_str_len code )
    : ~ i depth 0
    : ~ i instr 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get code k )
        ? == c 96 { = instr ? == instr 0 1 0 } {
        ? == instr 0 {
            ? | == c 123 | == c 40 == c 91 { = depth + depth 1 } {}
            ? | == c 125 | == c 41 == c 93 { = depth - depth 1 } {}
        } {} }
        = k + k 1
    }
    ^ depth
}

// ── stderr chrome ─────────────────────────────────────────────────────

@ eput s msg → v {
    : i _w ( write 2 # *u msg ( nurl_str_len msg ) )
}

// ── input ─────────────────────────────────────────────────────────────

@ __repl_read s prompt ( Vec String ) hist b tty → ?String {
    ? tty { ^ ( term_read_line prompt hist ) } {}
    ( eput prompt )
    ? ( stdin_eof ) { ^ @ ?String { F } } {}
    : String ln ( read_line )
    ? & == ( string_len ln ) 0 ( stdin_eof ) { ( string_free ln ) ^ @ ?String { F } } {}
    ^ @ ?String { T ln }
}

// Read continuation lines until brackets balance (multi-line defs).
@ __read_full s first ( Vec String ) hist b tty → String {
    : String acc ( string_with_cap 64 )
    ( string_push_str acc first )
    ~ > ( __repl_balance ( string_data acc ) ) 0 {
        : ?String cont ( __repl_read `  ...> ` hist tty )
        ?? cont {
            T c → { ( string_push_char acc 10 ) ( string_push_str acc ( string_data c ) ) ( string_free c ) }
            F _ → { ^ acc }
        }
    }
    ^ acc
}

// ── program assembly ──────────────────────────────────────────────────

@ __join ( Vec String ) v String out → v {
    : ~ i k 0
    ~ < k ( vec_len [String] v ) {
        ?? ( vec_get [String] v k ) {
            T ln → { ( string_push_str out ( string_data ln ) ) ( string_push_char out 10 ) }
            F _ → {}
        }
        = k + k 1
    }
}

// Full program = imports, defs, then `body` wrapped in main (empty body
// for a frontend-only validation pass).
@ __build_program ( Vec String ) imports ( Vec String ) defs s body → String {
    : String out ( string_with_cap 512 )
    ( __join imports out )
    ( __join defs out )
    ( string_push_str out `@ main → i {` ) ( string_push_char out 10 )
    ( string_push_str out body ) ( string_push_char out 10 )
    ( string_push_str out `^ 0 }` ) ( string_push_char out 10 )
    ^ out
}

// ── definitions ───────────────────────────────────────────────────────

// Validate the session after tentatively adding `line`; keep it only if
// the frontend accepts the whole thing.
@ __repl_add_def String line ( Vec String ) imports ( Vec String ) defs → v {
    : i c0 ( __char_at line 0 )
    : b is_import == c0 36   // '$'
    ? is_import { ( vec_push [String] imports ( __clone_str line ) ) } { ( vec_push [String] defs ( __clone_str line ) ) }
    : String prog ( __build_program imports defs `` )
    : !v IoErr _w ( write_file `/tmp/nurl_repl_check.nu` ( string_data prog ) )
    ?? _w { T _ → {} F _ → {} }
    ( string_free prog )
    : b ok ( __frontend_ok `/tmp/nurl_repl_check.nu` )
    ? ok {
        ( eput `defined.\n` )
    } {
        // roll back the bad definition
        ? is_import { ( __pop_free imports ) } { ( __pop_free defs ) }
        ( eput `definition rejected (kept previous session).\n` )
    }
}

@ __pop_free ( Vec String ) v → v {
    ?? ( vec_pop [String] v ) { T s → ( string_free s ) F _ → {} }
}

// Run the frontend only (fast) and surface its diagnostics on stderr.
@ __frontend_ok s path → b {
    : String cmd ( string_with_cap 64 )
    ( string_push_str cmd `build/nurlc ` )
    ( string_push_str cmd path )
    ( string_push_str cmd ` > /dev/null` )
    : ~ b ok F
    ?? ( process_run_shell ( string_data cmd ) ) {
        T out → {
            = ok ( output_success out )
            ? ok {} { ( eput ( output_stderr out ) ) }
            ( output_free out )
        }
        F _ → { ( eput `could not launch the compiler\n` ) }
    }
    ( string_free cmd )
    ^ ok
}

// ── evaluation ────────────────────────────────────────────────────────

@ __repl_eval ( Vec String ) imports ( Vec String ) defs s body → v {
    : String prog ( __build_program imports defs body )
    : !v IoErr _w ( write_file `/tmp/nurl_repl_eval.nu` ( string_data prog ) )
    ?? _w { T _ → {} F e → { ( eput `could not write temp file\n` ) } }
    ( string_free prog )

    // compile
    : ~ b built F
    ?? ( process_run_shell `./nurl.sh -O0 /tmp/nurl_repl_eval.nu /tmp/nurl_repl_eval_bin` ) {
        T out → {
            = built ( output_success out )
            ? built {} {
                ( eput ( output_stderr out ) )
                ( eput ( output_stdout out ) )
            }
            ( output_free out )
        }
        F _ → { ( eput `could not launch the compiler\n` ) }
    }
    // run (only if it compiled)
    ? built {
        ?? ( process_run_shell `/tmp/nurl_repl_eval_bin` ) {
            T out → {
                : i olen ( output_stdout_len out )
                ? > olen 0 {
                    : i _w2 ( write 1 # *u ( output_stdout out ) olen )
                } {}
                : i elen ( output_stderr_len out )
                ? > elen 0 { ( eput ( output_stderr out ) ) } {}
                ( output_free out )
            }
            F _ → { ( eput `could not run the program\n` ) }
        }
    } {}
}

// ── meta-commands ─────────────────────────────────────────────────────

@ __repl_help → v {
    ( eput `NURL REPL\n` )
    ( eput `  <expr/stmt>   evaluate (use nurl_print to see a value)\n` )
    ( eput `  @ / & / $ / : top-level definition (persists in the session)\n` )
    ( eput `  :help :h      this help          :quit :q   leave\n` )
    ( eput `  :defs         list definitions   :reset     forget all defs\n` )
    ( eput `  :save FILE    write session to FILE\n` )
}

@ __repl_show_defs ( Vec String ) imports ( Vec String ) defs → v {
    : i ni ( vec_len [String] imports )
    : i nd ( vec_len [String] defs )
    ? == + ni nd 0 { ( eput `(no definitions yet)\n` ) } {}
    : ~ i k 0
    ~ < k ni {
        ?? ( vec_get [String] imports k ) { T s → { ( eput ( string_data s ) ) ( eput `\n` ) } F _ → {} }
        = k + k 1
    }
    = k 0
    ~ < k nd {
        ?? ( vec_get [String] defs k ) { T s → { ( eput ( string_data s ) ) ( eput `\n` ) } F _ → {} }
        = k + k 1
    }
}

@ __repl_reset ( Vec String ) imports ( Vec String ) defs → v {
    ~ > ( vec_len [String] imports ) 0 { ( __pop_free imports ) }
    ~ > ( vec_len [String] defs ) 0 { ( __pop_free defs ) }
    ( eput `session cleared.\n` )
}

@ __repl_save String full ( Vec String ) imports ( Vec String ) defs → v {
    : String arg ( __after_space full )
    : String path ( __trim ( string_data arg ) )
    ( string_free arg )
    ? == ( string_len path ) 0 {
        ( eput `usage: :save FILE\n` )
    } {
        : String prog ( string_with_cap 256 )
        ( __join imports prog )
        ( __join defs prog )
        : !v IoErr w ( write_file ( string_data path ) ( string_data prog ) )
        ?? w {
            T _ → { ( eput `saved to ` ) ( eput ( string_data path ) ) ( eput `\n` ) }
            F _ → { ( eput `could not write that file\n` ) }
        }
        ( string_free prog )
    }
    ( string_free path )
}

// Substring after the first space (the meta-command argument).
@ __after_space String full → String {
    : i n ( string_len full )
    : ~ i k 0
    ~ & < k n != ( string_get full k ) 32 { = k + k 1 }
    : String out ( string_with_cap + - n k 1 )
    = k + k 1
    ~ < k n { ( string_push_char out ( string_get full k ) ) = k + k 1 }
    ^ out
}

// Returns 9 to quit, 0 otherwise.
@ __repl_dispatch String full ( Vec String ) imports ( Vec String ) defs → i {
    : i c0 ( __char_at full 0 )
    : i c1 ( __char_at full 1 )
    ? & == c0 58 & != c1 32 != c1 -1 {            // ':' + non-space → meta
        ^ ( __repl_meta full imports defs )
    } {}
    ? | | == c0 64 == c0 38 | == c0 36 & == c0 58 == c1 32 {  // @ & $  or ': '
        ( __repl_add_def full imports defs )
        ^ 0
    } {}
    ( __repl_eval imports defs ( string_data full ) )
    ^ 0
}

@ __repl_meta String full ( Vec String ) imports ( Vec String ) defs → i {
    : s p ( string_data full )
    ? | ( __seq p `:quit` ) ( __seq p `:q` ) { ^ 9 } {}
    ? | ( __seq p `:help` ) ( __seq p `:h` ) { ( __repl_help ) ^ 0 } {}
    ? ( __seq p `:defs` ) { ( __repl_show_defs imports defs ) ^ 0 } {}
    ? | ( __seq p `:reset` ) ( __seq p `:clear` ) { ( __repl_reset imports defs ) ^ 0 } {}
    ? ( __prefix p `:save ` ) { ( __repl_save full imports defs ) ^ 0 } {}
    ( eput `unknown command (try :help)\n` )
    ^ 0
}

// ── main loop ─────────────────────────────────────────────────────────

@ main → i {
    : b tty ( term_is_tty 0 )
    : ( Vec String ) imports ( vec_new [String] )
    : ( Vec String ) defs ( vec_new [String] )
    : ( Vec String ) hist ( vec_new [String] )
    ( eput `NURL REPL — :help for commands, :quit to exit\n` )
    : ~ b running T
    ~ running {
        : ?String line ( __repl_read `nurl> ` hist tty )
        ?? line {
            F _ → { = running F }
            T raw → {
                : String inp ( __trim ( string_data raw ) )
                ( string_free raw )
                ? == ( string_len inp ) 0 { ( string_free inp ) } {
                    : String full ( __read_full ( string_data inp ) hist tty )
                    ( string_free inp )
                    ( vec_push [String] hist ( __clone_str full ) )
                    : i act ( __repl_dispatch full imports defs )
                    ( string_free full )
                    ? == act 9 { = running F } {}
                }
            }
        }
    }
    ( eput `bye\n` )
    ^ 0
}
