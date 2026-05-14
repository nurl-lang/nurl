// rule30.nu — Wolfram's Rule 30 cellular automaton in NURL
//
// From a single live cell at the top, Rule 30 produces aperiodic
// chaotic patterns that never settle into a cycle. Stephen Wolfram
// famously used it as Mathematica's built-in RNG for years, and the
// same rule turns up in the pigmentation of the textile-cone snail
// Conus textile. Simple rule → endless complexity.
//
// The rule: for each cell,  new = left XOR (center OR right)
// (bit pattern 00011110₂ = 30 over the 8 possible LCR triples.)
//
// NURL features on display:
//   - Heap allocation: `malloc` + pointer cast `# *i`
//   - Pointer subscripting `. ptr idx`
//   - Bitwise `&` / `|` on i64 (dispatched by operand type)
//   - Inline ternary `? cond then else` inside expressions
//   - Nested prefix arithmetic without parens

// a XOR b  =  (a | b) - (a & b)   when a,b ∈ {0,1}
@ xor i a i b → i { ^ - | a b & a b }

@ render * i row i w → v {
    : ~ i x 0
    ~ < x w {
        ? == . row x 1
        ( nurl_print `█` )
        ( nurl_print ` ` )
        = x + x 1
    }
    ( nurl_print `\n` )
}

@ step * i cur * i nxt i w → v {
    : ~ i j 0
    ~ < j w {
        // Toroidal edges: index -1 wraps to w-1, index w wraps to 0.
        : i L . cur ? > j 0 - j 1 - w 1
        : i C . cur j
        : i R . cur ? < j - w 1 + j 1 0
        = . nxt j ( xor L | C R )
        = j + j 1
    }
}

@ copy * i src * i dst i w → v {
    : ~ i k 0
    ~ < k w {
        = . dst k . src k
        = k + k 1
    }
}

@ main → i {
    : i width 79
    : i gens 40

    : *i cur # *i ( malloc * width 8 )
    : *i nxt # *i ( malloc * width 8 )

    // Zero both buffers, then plant a single live cell in the centre.
    : ~ i i 0
    ~ < i width {
        = . cur i 0
        = . nxt i 0
        = i + i 1
    }
    = . cur / width 2 1

    ( nurl_print `\nRule 30 — Wolfram's chaotic cellular automaton\n\n` )

    : ~ i g 0
    ~ < g gens {
        ( render cur width )
        ( step cur nxt width )
        ( copy nxt cur width )
        = g + g 1
    }

    ( nurl_print `\nFrom a single seed cell: pure chaos — yet 100% deterministic.\n` )
    ^ 0
}
