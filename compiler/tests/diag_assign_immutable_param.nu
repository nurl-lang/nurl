// diag_assign_immutable_param.nu — writing to a parameter. Parameters
// are immutable bindings; the cure is a ': ~' local copy or an 'inout'
// parameter, and the message must name both because they differ in
// whether the caller sees the write.
//
// This message was rewritten in ecc058c after a probe found it named
// neither cure — and then shipped with nothing exercising it. That is
// the gap check_diag_coverage.sh exists to make visible.
@ f i p → i {
    = p + p 1
    ^ p
}

@ main → i { ^ ( f 1 ) }
