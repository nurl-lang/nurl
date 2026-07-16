// Module for diag_match_arm_recover.nu — its only declaration dies on a
// diagnostic INSIDE a `??` result-match arm, so the multi-error recovery
// frame unwinds out of the open function + arm scopes. Not a test itself.

: Widget {
    i w
}

: | WidgetErr {
    WidgetBoom
}

@ mk_widget → !Widget WidgetErr {
    : Widget wg @ Widget { 1 }
    ^ @ !Widget WidgetErr { T wg }
}

@ broken → v {
    ?? ( mk_widget ) {
        T wg → {
            // `pub` is a reserved keyword — this let dies mid-arm, leaving
            // `__matchtmp…__res_nurl_T = Widget` in the open scopes.
            : i pub 5
        }
        F _ → {}
    }
}
