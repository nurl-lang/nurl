// enum_binding_given_a_new_value_in_its_own_arm_scalar_payload_runs_clean: the payload is an `i`, a copy: reading it after the enum binding is given a new value is safe.
// Control for agora #364.
// map: §2.10 | A2 | runs-clean | - | agora #364: the payload is an `i`, a copy: reading it after the enum binding is given a new value is safe
$ `stdlib/core/string.nu`

: | Num { NNone NSome i }

@ run i k → i {
    : ~ Num o @ Num { NSome 41 }
    : ~ i got 0
    ?? o {
        NSome n → {
            ? == k 1 { = o @ Num { NSome 7 } } {}
            = got + n 1
        }
        NNone → {}
    }
    ^ got
}

@ main → i { ( nurl_print_int ( run 1 ) ) ( nurl_print `\n` ) ^ 0 }
