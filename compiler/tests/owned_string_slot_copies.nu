// owned_string_slot_copies.nu — a string binding that owns its value takes
// its own copy of what it is given, so it holds no view of where the value
// came from. Assigned a view (a match arm's payload, a String of a block
// that ends first), it reads its copy after the source ended. A join whose
// arm is an owned local hands the join a copy of it. A mutable string born
// from a call that hands nothing over owns what later assignments give it
// (a copy of an owned local), and releases each. The sanitizer corpus runs
// this with leak detection.
$ `stdlib/core/string.nu`

: ~ s g_name ``

@ get_copy b some → ?String {
    ? some { ^ @ ?String { T ( string_from `Bearer abc` ) } } {}
    ^ @ ?String { F }
}

// A match arm's payload, viewed into a binding that outlives the arm.
@ from_arm b some → i {
    : ~ s got ``
    ?? ( get_copy some ) { T h → { = got ( string_data h ) } F → {} }
    ^ ( nurl_str_len got )
}

// A String of a block that ends first.
@ from_block → i {
    : ~ s got ``
    {
        : String t ( string_from `scoped` )
        = got ( string_data t )
    }
    ^ ( nurl_str_len got )
}

// A mutable copy of an owned local; the local replaced after.
@ copy_then_replace → i {
    : ~ s x ( nurl_str_cat `ab` `cd` )
    : ~ s y x
    = x ( nurl_str_cat `ef` `gh!` )
    ^ + ( nurl_str_len y ) ( nurl_str_len x )
}

// An owned local assigned to another owned binding, then replaced.
@ assign_then_replace → i {
    : ~ s x ( nurl_str_cat `ab` `cd` )
    : ~ s y ``
    = y x
    = x ( nurl_str_cat `ef` `gh!` )
    ^ + ( nurl_str_len y ) ( nurl_str_len x )
}

// A binding off a mutable string global (copied); the global replaced.
@ off_global → i {
    = g_name ( nurl_str_cat `ab` `cd` )
    : s saved g_name
    = g_name ( nurl_str_cat `ef` `gh!` )
    ^ ( nurl_str_len saved )
}

// A join of an owned local and a fresh value, handed back.
@ join_back s a b c → s {
    : s xv ( nurl_str_cat a `x` )
    : s norm ? c xv ( nurl_str_cat a `yy` )
    ^ norm
}

// A join of an owned local and a fresh value, kept in a global.
@ note s pos s name → v {
    : s rec ( nurl_str_cat3 pos ` ` name )
    = g_name ? == 0 ( nurl_str_len g_name ) rec ( nurl_str_cat3 g_name `|` rec )
}

// A mutable string born from a view, given owned locals in a loop and in
// a block: each copy is the binding's, released when the next arrives.
@ view_born_owns → i {
    : String base ( string_from `base` )
    : ~ s y ( string_data base )
    : ~ i k 0
    ~ < k 3 {
        : s x ( nurl_str_cat `ab` ( nurl_str_int k ) )
        = y x
        = k + k 1
    }
    {
        : s z ( nurl_str_cat `last` `!` )
        = y z
    }
    ^ ( nurl_str_len y )
}

@ main → i {
    ( nurl_print_int ( from_arm T ) ) ( nurl_print ` ` ) ( nurl_print_int ( from_arm F ) ) ( nurl_print `\n` )
    ( nurl_print_int ( from_block ) ) ( nurl_print `\n` )
    ( nurl_print_int ( copy_then_replace ) ) ( nurl_print ` ` ) ( nurl_print_int ( assign_then_replace ) ) ( nurl_print `\n` )
    ( nurl_print_int ( off_global ) ) ( nurl_print `\n` )
    : s p ( join_back `ab` T )
    : s q ( join_back `cd` F )
    ( nurl_print p ) ( nurl_print ` ` ) ( nurl_print q ) ( nurl_print `\n` )
    = g_name ``
    ( note `a.nu:1` `f` ) ( note `b.nu:2` `g` )
    ( nurl_print g_name ) ( nurl_print `\n` )
    ( nurl_print_int ( view_born_owns ) ) ( nurl_print `\n` )
    ^ 0
}
