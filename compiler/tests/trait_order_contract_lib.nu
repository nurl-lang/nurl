// fixture: module
% Reading [T] {
    type Elem
    @ read T self → Elem
    @ twice T self → Elem { ^ + ( read self ) ( read self ) }
}
