// benchmark-contract: payload-state-machine;events=10000000;lcg=mmix(seed=1);draw=state>>29;sel=r&7(0-2:Add,3:Scale,4:Push,5:Pop,6-7:Probe);max_depth=16;fault=DepthLow(String)|DepthHigh(u64,String);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// payload_state_machine — 10M events of a deterministic stream, each
// decoded from an MMIX LCG draw into a payload-bearing enum
// (`Add v`, `Scale m b`, `Push`, `Pop`, `Probe k`) and fed to a state
// machine whose step returns a result: `T` the next state on the normal
// exit, `F` a `Fault` carrying an OWNED String (built when the fault is
// raised, read and dropped by the handler) on the error exit. `Probe`
// goes through an option-returning lookup. The stack depth is a random
// walk bounded by 0 and 16, so faults are rare enough to stay off the
// critical path but frequent enough (147,458 of the 10M events, 1 in
// 68) that the error exit and its payload's allocation and drop are
// measured too.
//
// What this row adds: enum construction and payload extraction, `??`
// over an enum, an option and a result, and an owned payload moving out
// of a result into a handler — the control-flow shape of a parser or a
// protocol state machine. `collatz` is the nearest row and has no data
// in its branches at all.
//
// C carries the same shapes as tagged structs and a malloc'd message;
// Rust as enums, `Option` and `Result<St, Fault>` with a `String`.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

$ `stdlib/core/string.nu`

: St { u64 acc u64 depth u64 steps }

: | Ev { Add u64 Scale u64 u64 Push Pop Probe u64 }

: | Fault { DepthLow String DepthHigh u64 String }

@ decode u64 r → Ev {
    : u64 sel & r 7
    : u64 rest >> r 3
    ? < sel 3 { ^ @ Ev { Add & rest 65535 } } {}
    ? == sel 3 { ^ @ Ev { Scale + & rest 7 1 & >> rest 3 255 } } {}
    ? == sel 4 { ^ @ Ev { Push } } {}
    ? == sel 5 { ^ @ Ev { Pop } } {}
    ^ @ Ev { Probe rest }
}

@ lookup u64 key → ?u64 {
    ? == & key 3 0 { ^ @ ?u64 { F # u64 0 } } {}
    ^ @ ?u64 { T * key 31 }
}

// The fault's message: a fixed text and one byte chosen by the state.
@ fault_text s base u64 acc u64 c0 → String {
    : String m ( string_from base )
    ( string_push_char m # i + c0 & acc 15 )
    ^ m
}

@ step St s Ev e → !St Fault {
    ?? e {
        Add v → { ^ @ !St Fault { T @ St { + . s acc v . s depth + . s steps 1 } } }
        Scale m b → { ^ @ !St Fault { T @ St { + * . s acc m b . s depth + . s steps 1 } } }
        Push → {
            ? >= . s depth 16 {
                ^ @ !St Fault { F @ Fault { DepthHigh . s depth ( fault_text `stack overflow at ` . s acc 65 ) } }
            } {}
            ^ @ !St Fault { T @ St { . s acc + . s depth 1 + . s steps 1 } }
        }
        Pop → {
            ? == . s depth 0 {
                ^ @ !St Fault { F @ Fault { DepthLow ( fault_text `stack underflow at ` . s acc 97 ) } }
            } {}
            ^ @ !St Fault { T @ St { ^^ . s acc . s depth - . s depth 1 + . s steps 1 } }
        }
        Probe k → {
            ?? ( lookup k ) {
                T v → { ^ @ !St Fault { T @ St { ^^ . s acc v . s depth + . s steps 1 } } }
                F → { ^ @ !St Fault { T @ St { + . s acc 1 . s depth + . s steps 1 } } }
            }
        }
    }
}

@ fnv u64 h u64 v → u64 { ^ * ^^ h v 1099511628211 }

// What a handler takes from a fault's message: its length and last byte.
@ text_sum String m → u64 {
    : i n ( string_len m )
    ^ + # u64 n # u64 ( string_get m - n 1 )
}

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : u64 events * 10000000 BENCH_SCALE

    : ~ St st @ St { 1 0 0 }
    : ~ u64 x 1
    : ~ u64 errh 1469598103934665603
    : ~ u64 faults 0
    : ~ u64 k 0
    ~ < k events {
        = x + * x 6364136223846793005 1442695040888963407
        : Ev ev ( decode >> x 29 )
        : !St Fault res ( step st ev )
        ?? res {
            T ns → { = st ns }
            F f → {
                ?? f {
                    DepthLow m → { = errh ( fnv errh ( text_sum m ) ) }
                    DepthHigh d m → { = errh ( fnv errh + d ( text_sum m ) ) }
                }
                = faults + faults 1
                = st @ St { | >> . st acc 7 << . st acc 57 0 . st steps }
            }
        }
        = k + k 1
    }

    : ~ u64 h 1469598103934665603
    = h ( fnv h . st acc )
    = h ( fnv h . st depth )
    = h ( fnv h . st steps )
    = h ( fnv h errh )
    = h ( fnv h faults )
    ( nurl_println_int # i & h 0x7fffffffffffffff )
    ^ 0
}
