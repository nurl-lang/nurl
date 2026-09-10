// Signatures use %Scored before its declaration; this '%' is a type,
// not a declaration. Both the default and inherited method enter the vtable.
: Reading { i value }

@ announce %Scored item → i { ^ + ( score item ) ( read item ) }

@ main → i {
    : Reading item @ Reading { 14 }
    : %Scored obj ( dyn Scored item )
    ( nurl_println_int ( announce obj ) )
    ^ 0
}

% Scored Reading {}

% Readable Reading { @ read Reading self → i { ^ . self value } }

% Scored [T] : Readable { @ score T self → i { ^ * ( read self ) 2 } }

% Readable [T] { @ read T self → i }
