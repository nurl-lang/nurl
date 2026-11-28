import C.Elab

/-! C.Elab's witnesses: IRs written out, the terms `elabIR` builds from
them, checked (steps 2 to 10, and the conditional stubs of AGORA-1036).
Apart from `C/Elab.lean` so that a certificate, whose Elab.lean imports
`C.Elab`, loads no witness program (AGORA-1013); the names stay in
`C.Elab`. -/

namespace C.Elab
open A2


/-! ### Witnesses (step 2) -/

/-- The witnesses write their IRs as text, read as the reader reads the
    words (`strs`), or, for the named theorems, as numbers (`encIR`), the
    printer's form, so that reading them back is checked too. -/
abbrev SIR := List (List String)

def elabS (l : SIR) : Option (Prog × Stmt) := elabL (strs l)


/-- `tools/ncore/certify/while_loop_summing.nu`'s core IR, as
    `nurl-cert words` prints it (its `ty` line left out). -/
def irWhile : SIR := [
  ["fn", "main", "i64", "0", "1", "tools/ncore/certify/while_loop_summing.nu", "0", ""],
  ["v", "0", "1", "1", "1", "2", "-1", "n", "i64"],
  ["v", "1", "1", "1", "1", "3", "-1", "acc", "i64"],
  ["scope"], ["line", "2"], ["let", "0", "use", "c"], ["line", "3"], ["let", "1", "use", "c"],
  ["line", "4"], ["loop"], ["eval", "scalar", "2", "v0", "c"], ["loopcond", "c"],
  ["scope"], ["line", "5"], ["eval", "scalar", "2", "v1", "v0"], ["assign", "v1", "use", "c"],
  ["line", "6"], ["eval", "scalar", "2", "v0", "c"], ["assign", "v0", "use", "c"],
  ["end"], ["end"], ["line", "8"], ["ret", "v1"], ["end"], ["endfn"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The term `nurl-cert translate` prints for it, written out: `n` is 1,
    `acc` 2 (after the result slot 0); the loop's body is translated before
    its condition, so the condition's temporary is the last made (5). -/
def pWhile : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := (.block (.seq (.letv 1 (.expr .any) (.letv 2 (.expr .any) (.seq (.block (.loop
      (.letv 5 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 1)) .any) (.lit 0))))
        (.ite .any (.block (.letv 4 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 2)) (.var 1)) (.lit 0))))
          (.seq (.assign 2 (.expr .any)) (.letv 3 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 1)) .any) (.lit 0))))
            (.assign 1 (.expr .any)))))) (.exit 0)))))
      (.assign 0 (.expr (.var 2)))))) (.exit 0))),
    nvars := 7 }]

/-- The kernel builds the translator's term from the words itself. -/
theorem elab_while : elabIR (encIR irWhile) = some (pWhile, .letcall 0 0 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- Outside the subset, `none`: a `Vec` of strings; a call of a library
    function outside it; a statement block left open. -/
example : (elabS [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["v", "0", "1", "1", "1", "2", "-1", "v", "%Vec__String"],
    ["scope"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by decide +kernel
example : (elabS [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["eval", "call", "vec_pop__i64", "1", "c"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by
  decide +kernel
example : (elabS [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["loop"], ["loopcond", "c"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by decide +kernel

/-- Refused as the translator refuses it, though the translation itself
    would skip it: a miscounted scalar stored to a `void` (the translator's
    `__wellformed` checks every statement's count first); a `ty` line
    without its fields (the reader refuses it); and a function of the
    program named like an intrinsic, even one no one calls. -/
def irRet (extra : SIR) (pre : SIR) : SIR :=
  pre ++ [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["v", "0", "2", "1", "0", "2", "-1", "", "void"],
    ["scope"]] ++ extra ++ [["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irRet [["let", "0", "none"], ["assign", "v0", "scalar", "2", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irRet [] [] ++ [["ty", "%X", "struct", "", ""]])).isNone := by decide +kernel
example : (elabS ([["fn", "nurl_println_int", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++ irRet [] [])).isNone := by decide +kernel

/-- …while their well-formed neighbours are in the subset: the store to a
    `void` with its count right, and a struct `ty` line no one uses. -/
example : (elabS (irRet [["let", "0", "none"], ["assign", "v0", "scalar", "1", "c"]] [])).isSome := by
  decide +kernel
example : (elabS (irRet [] [] ++
    [["ty", "%X", "1", "0-----", "", "A", "0", "F", "2", "a", "i64", "b", "i64", "V", "0"]])).isSome := by
  decide +kernel

/-! ### Witnesses (step 4: buffers) -/

/-- A `main` of variables `vs` and statements `body`, then the lines
    `extra` (other functions, `sum` lines). -/
def irM (vs body extra : SIR) : SIR :=
  [["fn", "main", "i64", "0", "1", "a.nu", "0", ""]] ++ vs ++ [["scope"]] ++ body ++
    [["end"], ["endfn"]] ++ extra

/-- A Vec made, moved into its binding and its temporary dropped (`v0`, a
    temporary; `v1`, a `: ~` binding). -/
def vsVec : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%Vec__i64"],
  ["v", "1", "1", "1", "4097", "1", "-1", "v", "%Vec__i64"]]
def bodyVec : SIR := [["let", "0", "call", "vec_new__i64", "0"], ["let", "1", "use", "v0"], ["drop", "0"]]

/-- The kernel's term for it: the push's untracked number a temporary of its
    own (bound around it), the length read into a fresh one. -/
def pPush : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 4 (.expr .any)
      (.seq (.push 2 4) (.letv 3 (.expr (.len 2)) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 6 }]
example : elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_push__i64", "2", "v1", "c"],
    ["eval", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]]) []) = some (pPush, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)

/-- A buffer's `drop` is the end of its scope only if no line after it names
    it (`__views_of`): the temporary read after its drop is refused, its
    binding read there is not. -/
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_len__i64", "1", "v0"], ["ret", "c"]])
    [])).isNone := by decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
/-- …every word of every line after it counts, cut at its `/`s (here a
    `line` the translation passes over), and only the text `v<k>`. -/
example : (elabS (irM vsVec (bodyVec ++ [["line", "x/v0/y"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["line", "x/v00/v01/w0"], ["ret", "c"]]) [])).isSome := by
  decide +kernel

/-- …and so for variables past `maskB`, which the check reads line by line. -/
def vsBig : SIR := [["v", "5000", "2", "1", "0", "1", "-1", "", "%Vec__i64"],
  ["v", "5001", "1", "1", "4097", "1", "-1", "v", "%Vec__i64"]]
def bodyBig : SIR := [["let", "5000", "call", "vec_new__i64", "0"], ["let", "5001", "use", "v5000"], ["drop", "5000"]]
example : (elabS (irM vsBig (bodyBig ++ [["eval", "call", "vec_len__i64", "1", "v5000"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsBig (bodyBig ++ [["eval", "call", "vec_len__i64", "1", "v5001"], ["ret", "c"]]) [])).isSome := by
  decide +kernel

/-- A call whose result may view an argument (its summary: `ret_unowned=1`)
    is refused (`letCallOk`), its owned neighbour (`ret_owned`) is not; so
    is a call of a function named like one the translator takes for a view
    (`slice_at__…`), even of the program's own. -/
def bodyLen : SIR := bodyVec ++ [["let", "2", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]]
def vsLen : SIR := vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "i64"]]
example : (elabS (irM vsLen bodyLen [["sum", "vec_len__i64", "1", "ret_unowned=1"]])).isNone := by
  decide +kernel
example : (elabS (irM vsLen bodyLen [["sum", "vec_len__i64", "1", "ret_unowned=1", "ret_owned=1"]])).isSome := by
  decide +kernel
def fnRead (name : String) : SIR := [["fn", name, "i64", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "v", "%Vec__i64"], ["scope"], ["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irM vsLen (bodyVec ++ [["let", "2", "call", "slice_at__x", "1", "v1"], ["ret", "c"]])
    (fnRead "slice_at__x"))).isNone := by decide +kernel
example : (elabS (irM vsLen (bodyVec ++ [["let", "2", "call", "slice_atx", "1", "v1"], ["ret", "c"]])
    (fnRead "slice_atx"))).isSome := by decide +kernel

/-- A buffer's drop ends the elements read out of it too (`vec_at`,
    `__views_of`): the element of the temporary read after the temporary's
    drop is refused, the element of its binding is not. -/
example : (elabS (irM vsLen [["let", "0", "call", "vec_new__i64", "0"],
    ["let", "2", "call", "vec_at__i64", "2", "v0", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
    ["eval", "scalar", "1", "v2"], ["ret", "c"]] [])).isNone := by decide +kernel
example : (elabS (irM vsLen (bodyVec ++ [["let", "2", "call", "vec_at__i64", "2", "v1", "c"],
    ["drop", "0"], ["eval", "scalar", "1", "v2"], ["ret", "c"]]) [])).isSome := by decide +kernel

/-- An owned result aliasing a parameter (`ret_alias`) is refused; without
    the key the Vec handed back is the result, owned. -/
def fnMake (extra : SIR) : SIR := [["fn", "make", "%Vec__i64", "0", "1", "a.nu", "0", ""]] ++ vsVec ++
  [["scope"]] ++ bodyVec ++ [["ret", "v1"], ["end"], ["endfn"]] ++ extra
example : (elabS (irM [] [["ret", "c"]] (fnMake [["sum", "make", "0", "ret_alias=0"]]))).isNone := by
  decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnMake []))).isSome := by decide +kernel

/-- Stores the translator refuses: a borrowed parameter's value given to an
    owner (a `sink` one's is not); raw text assigned from another binding (a
    `String` is not). -/
def fnStore (pflags : String) : SIR := [["fn", "f", "void", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", pflags, "1", "-1", "a", "%Vec__i64"],
  ["v", "1", "1", "1", "1", "1", "-1", "b", "%Vec__i64"],
  ["scope"], ["let", "1", "call", "vec_new__i64", "0"], ["assign", "v1", "use", "v0"], ["end"], ["endfn"]]
example : (elabS (irM [] [["ret", "c"]] (fnStore "0"))).isNone := by decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnStore "4"))).isSome := by decide +kernel
def vsText (t : String) : SIR := [["v", "0", "1", "1", "1", "1", "-1", "a", t],
  ["v", "1", "1", "1", "1", "1", "-1", "b", t]]
def bodyText : SIR := [["let", "0", "use", "c"], ["let", "1", "use", "c"], ["assign", "v1", "use", "v0"],
  ["ret", "c"]]
example : (elabS (irM (vsText "i8*") bodyText [])).isNone := by decide +kernel
example : (elabS (irM (vsText "%String") bodyText [])).isSome := by decide +kernel

/-- Outside the subset: a `Vec` of `Vec`s, and a `let` of a `vec_push` (the
    translator lowers it by falling through to a call). -/
example : (elabS (irM [["v", "0", "1", "1", "1", "1", "-1", "v", "%Vec__Vec__i64"]] [["ret", "c"]]
    [])).isNone := by decide +kernel
example : (elabS (irM (vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyVec ++ [["let", "2", "call", "vec_push__i64", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by
  decide +kernel


/-! ### Witnesses (step 5: views, slices and changes through a borrow) -/

/-- A `String` made, viewed (`string_data`, a temporary `v2`), the view
    bound (`v3`) and read: raw text that holds a view is a slice, read by
    its length (`.slen`). -/
def vsStr : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
  ["v", "1", "1", "1", "4096", "1", "-1", "t", "%String"],
  ["v", "2", "2", "1", "0", "1", "-1", "", "i8*"], ["v", "3", "1", "1", "0", "1", "-1", "v", "i8*"]]
def bodyStr : SIR := [["let", "0", "call", "string_from", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["let", "2", "call", "string_data", "1", "v1"], ["let", "3", "use", "v2"], ["drop", "2"]]

/-- The translator's term for it (`nurl-cert translate`), written out. -/
def pView : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 3 (.view 2) (.letv 4 (.var 3)
      (.letv 5 (.expr (.slen 4)) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 7 }]
example : elabS (irM vsStr (bodyStr ++ [["eval", "call", "nurl_str_len", "1", "v3"], ["ret", "c"]]) []) =
    some (pView, .letcall 0 0 [] .skip) := elabLIs_sound _ _ _ (by decide +kernel)
/-- …and so is `nurl_println` of the view; `string_data` is taken though its
    summary says it lends its result (`ret_unowned=1`, as nurlc prints it). -/
example : elabS (irM vsStr (bodyStr ++ [["eval", "call", "nurl_println", "1", "v3"], ["ret", "c"]])
    [["sum", "string_data", "1", "ret_unowned=1"]]) = some (pView, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)
/-- A `let x` of `nurl_println` is refused: the translator lowers it by
    falling through to a call, which drops `x` (stricter). -/
example : (elabS (irM (vsStr ++ [["v", "4", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyStr ++ [["let", "4", "call", "nurl_println", "1", "v3"], ["ret", "c"]]) [])).isNone := by
  decide +kernel

/-- A drop ends the views copied out of a view into a temporary
    (`__views_of`'s `use` case): the String's temporary `v0` is viewed (`v2`),
    the view copied into the temporary `v3`, and `v3` read after `v0`'s drop
    is refused; copied into a binding instead, it is not followed (the
    translator's rule), and the program is in the subset. -/
def vsChain (k3 : String) : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
  ["v", "1", "1", "1", "4096", "1", "-1", "t", "%String"], ["v", "2", "2", "1", "0", "1", "-1", "", "i8*"],
  ["v", "3", k3, "1", "0", "1", "-1", "", "i8*"]]
def bodyChain : SIR := [["let", "0", "call", "string_from", "1", "c"], ["let", "2", "call", "string_data", "1", "v0"],
  ["let", "3", "use", "v2"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["eval", "call", "nurl_str_len", "1", "v3"], ["ret", "c"]]
example : (elabS (irM (vsChain "2") bodyChain [])).isNone := by decide +kernel
example : (elabS (irM (vsChain "1") bodyChain [])).isSome := by decide +kernel

/-- A slice of a Vec of numbers (`.view`) and its length (`.slen`); a
    `slice_from_vec` whose summary says it lends its result is refused
    (stricter: the translator takes it), and so is a slice of a Vec of
    views (the translator refuses it). -/
def vsSl : SIR := vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "%Slice__i64"]]
def bodySl : SIR := bodyVec ++ [["let", "2", "call", "slice_from_vec__i64", "1", "v1"],
  ["eval", "call", "slice_len__i64", "1", "v2"], ["ret", "c"]]
def pSlice : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 3 (.view 2)
      (.letv 4 (.expr (.slen 3)) (.assign 0 (.expr .any)))))) (.exit 0)),
    nvars := 6 }]
example : elabS (irM vsSl bodySl []) = some (pSlice, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)
example : (elabS (irM vsSl bodySl [["sum", "slice_from_vec__i64", "1", "rviews=0"]])).isNone := by
  decide +kernel
def vsVecS : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%Vec__str"],
  ["v", "1", "1", "1", "4097", "1", "-1", "v", "%Vec__str"]]
def bodyVecS : SIR := [["let", "0", "call", "vec_new__str", "0"], ["let", "1", "use", "v0"], ["drop", "0"]]
example : (elabS (irM (vsVecS ++ [["v", "2", "2", "1", "0", "1", "-1", "", "%Slice__str"]])
    (bodyVecS ++ [["let", "2", "call", "slice_from_vec__str", "1", "v1"], ["ret", "c"]]) [])).isNone := by
  decide +kernel

/-- Raw text pushed into a `Vec` of raw strings is viewed first (the Vec
    holds a view of it); a literal is refused, as the translator refuses it. -/
def vsNames : SIR := vsVecS ++ [["v", "2", "1", "1", "0", "1", "-1", "a", "i8*"]]
def pNames : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new (.slice .int)) (.letv 2 (.var 1) (.letv 3 (.new .int)
      (.letv 4 (.view 3) (.seq (.push 2 4) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 6 }]
example : elabS (irM vsNames (bodyVecS ++ [["let", "2", "use", "c"],
    ["eval", "call", "vec_push__str", "2", "v1", "v2"], ["ret", "c"]]) []) = some (pNames, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)
example : (elabS (irM vsNames (bodyVecS ++ [["let", "2", "use", "c"],
    ["eval", "call", "vec_push__str", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by decide +kernel

/-- `foreach x v` over a Vec of numbers: a view of the Vec held for the
    loop, each element lent through it (`.sat`), the index stepped first. -/
def vsEach : SIR := vsVec ++ [["v", "2", "1", "1", "0", "1", "-1", "x", "i64"]]
def bodyEach (over : String) (inner : SIR) : SIR :=
  bodyVec ++ [["foreach", "2", over], ["scope"]] ++ inner ++ [["end"], ["end"], ["ret", "c"]]
def pEach : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.seq (.block (.letv 4 (.expr (.lit 0))
      (.letv 5 (.view 2) (.loop (.ite (.lt (.var 4) (.slen 5)) (.block (.letv 3 (.sat 5 (.var 4))
        (.seq (.assign 4 (.expr (.add (.var 4) (.lit 1)))) (.letv 6 (.expr (.add .any (.lt (.add (.lit 0)
          (.var 3)) (.lit 0)))) .skip)))) (.exit 0))))))
      (.assign 0 (.expr .any))))) (.exit 0)),
    nvars := 8 }]
example : elabS (irM vsEach (bodyEach "v1" [["eval", "scalar", "1", "v2"]]) []) =
    some (pEach, .letcall 0 0 [] .skip) := elabLIs_sound _ _ _ (by decide +kernel)
/-- Refused as the translator refuses them: a `foreach` over a Vec of views,
    and over a `String`. -/
example : (elabS (irM (vsVecS ++ [["v", "2", "1", "1", "0", "1", "-1", "x", "i8*"]])
    (bodyVecS ++ [["foreach", "2", "v1"], ["scope"], ["end"], ["end"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
    ["v", "1", "1", "1", "4097", "1", "-1", "s", "%String"], ["v", "2", "1", "1", "0", "1", "-1", "x", "i64"]]
    [["let", "0", "call", "string_from", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
     ["foreach", "2", "v1"], ["scope"], ["end"], ["end"], ["ret", "c"]] [])).isNone := by decide +kernel
/-- A change of the loop's element in place is refused (stricter: the
    translator changes it through itself, `__edit_through`); a change of
    the Vec is a change through a borrow of it. -/
example : (elabS (irM vsEach (bodyEach "v1" [["eval", "call", "vec_clear__i64", "1", "v2"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsEach (bodyEach "v1" [["eval", "call", "vec_clear__i64", "1", "v1"]]) [])).isSome := by
  decide +kernel

/-- `vec_reserve`: a push through a borrow (its untracked number a temporary
    of its own) and a cut back to the length read before it. -/
def pReserve : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 4 (.expr .any)
      (.seq (.letv 3 (.borrow 2) (.letv 5 (.expr (.len 3))
        (.seq (.edit true 3 (.push 4)) (.edit true 3 (.trunc (.var 5))))))
        (.assign 0 (.expr .any)))))) (.exit 0)),
    nvars := 7 }]
example : elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_reserve__i64", "2", "v1", "c"], ["ret", "c"]])
    []) = some (pReserve, .letcall 0 0 [] .skip) := elabLIs_sound _ _ _ (by decide +kernel)
/-- …a `let x` of it is refused (stricter: the translator falls through to a
    call that drops `x`), and so is one of a Vec of views (the translator
    refuses it). -/
example : (elabS (irM (vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyVec ++ [["let", "2", "call", "vec_reserve__i64", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsVecS (bodyVecS ++ [["eval", "call", "vec_reserve__str", "2", "v1", "c"], ["ret", "c"]])
    [])).isNone := by decide +kernel

/-- `vec_clear` and `vec_truncate` of the counts the translator lowers; a
    `vec_clear` of two operands falls through to a call of a function the
    program does not have, and is refused. -/
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_clear__i64", "1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_truncate__i64", "2", "v1", "c"], ["ret", "c"]])
    [])).isSome := by decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_clear__i64", "2", "v1", "c"], ["ret", "c"]])
    [])).isNone := by decide +kernel

/-- `string_push_str` of text (here the String itself) reads its length
    after the push; of a number it is refused, as the translator refuses it. -/
def vsPs : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
  ["v", "1", "1", "1", "4097", "1", "-1", "s", "%String"], ["v", "2", "1", "1", "1", "1", "-1", "n", "i64"]]
def bodyPs : SIR := [["let", "0", "call", "string_from", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["let", "2", "use", "c"]]
example : (elabS (irM vsPs (bodyPs ++ [["eval", "call", "string_push_str", "2", "v1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
example : (elabS (irM vsPs (bodyPs ++ [["eval", "call", "string_push_str", "2", "v1", "v2"], ["ret", "c"]])
    [])).isNone := by decide +kernel

/-- A slice parameter is in the subset; a slice handed back is not
    (stricter: the translator takes it as an owned result). -/
def fnSl (ret : String) (body : SIR) : SIR := [["fn", "f", ret, "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "s", "%Slice__i64"], ["scope"]] ++ body ++ [["end"], ["endfn"]]
example : (elabS (irM [] [["ret", "c"]] (fnSl "i64" [["eval", "call", "slice_len__i64", "1", "v0"],
    ["ret", "c"]]))).isSome := by decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnSl "%Slice__i64" [["ret", "v0"]]))).isNone := by decide +kernel

/-- A borrowed parameter assigned to an `inout` one is copied when it is a
    Vec (here of raw strings: `.new (.slice .int)`); a slice is not, as the
    translator refuses it. -/
def fnCopy (t : String) : SIR := [["fn", "f", "void", "2", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "a", t], ["v", "1", "0", "0", "2", "1", "-1", "b", t],
  ["scope"], ["assign", "v1", "use", "v0"], ["end"], ["endfn"]]
example : (elabS (irM [] [["ret", "c"]] (fnCopy "%Vec__str"))).isSome := by decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnCopy "%Slice__i64"))).isNone := by decide +kernel

/-! ### Witnesses (step 6: closures) -/

def cloTyW : String := "{ i64 (i8*, i64)*, i8* }"

/-- A closure's code `cn` of a capture `c` (type `ct`, flags `cf`) and a
    parameter `x` (flags `pf`), body `cb`; then `main`: `v0` the capture's
    binding (type `ct`, made by `mk`), the literal `lit` into the temporary
    `v1` (type `cty`), moved into `f` (`v2`), its other variables `mvs`,
    then `body`; then the lines `extra`. -/
def irCloW (cn ct cf pf cty : String) (cb mk lit body mvs extra : SIR) : SIR :=
  [["fn", cn, "i64", "1", "1", "a.nu", "0", ""], ["v", "0", "3", "0", cf, "1", "-1", "c", ct],
   ["v", "1", "0", "1", pf, "0", "-1", "x", "i64"], ["scope"]] ++ cb ++ [["ret", "c"], ["end"], ["endfn"],
   ["fn", "main", "i64", "0", "1", "a.nu", "0", ""], ["v", "0", "1", "1", "0", "1", "-1", "c", ct],
   ["v", "1", "2", "1", "0", "1", "-1", "", cty], ["v", "2", "1", "1", "0", "1", "-1", "f", cty]] ++ mvs ++
  [["scope"]] ++ mk ++ lit ++ [["let", "2", "use", "v1"], ["drop", "1"]] ++ body ++ [["ret", "c"], ["end"], ["endfn"]] ++
  extra

def litW : SIR := [["let", "1", "closure", "__closure_1", "1", "v0"]]
def callW : SIR := [["eval", "callind", "2", "v2", "c"]]
/-- A number captured by value and the closure called. -/
def irNumW (cb lit body mvs extra : SIR) : SIR :=
  irCloW "__closure_1" "i64" "0" "0" cloTyW cb [["let", "0", "use", "c"]] lit body mvs extra
def cbW : SIR := [["eval", "scalar", "2", "v1", "v0"]]

/-- The translator's term for it (`nurl-cert translate`), written out: the
    code reads its capture out of the environment (`v0`) at the top; the
    literal packs the code (function 0) with the environment, the number,
    at the interface of its type (function 2, after the program's two);
    the call is `callc` of that interface's method 0. -/
def pCloW : Prog := [
  { params := [(.inp, .int), (.inp, .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.letv 3 (.expr (.var 0)) (.seq (.letv 5 (.expr (.add .any (.lt (.add (.add
      (.lit 0) (.var 1)) (.var 3)) (.lit 0)))) (.assign 2 (.expr .any))) (.exit 0))), nvars := 7 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 1 (.expr .any) (.letv 2 (.pack [0] .int [2] 1 []) (.letv 3 (.var 2)
      (.letv 4 (.expr .any) (.callc 5 3 0 2 [4] (.assign 0 (.expr .any))))))) (.exit 0)), nvars := 7 },
  { params := [(.inp, .fn [2] .any), (.inp, .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.assign 2 (.expr (.lit 0))) (.exit 0)), nvars := 3 }]
theorem elab_clo : elabIR (encIR (irNumW cbW litW callW [] [])) = some (pCloW, .letcall 0 1 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- Refused as the translator refuses them: a capture that is not a
    variable; a literal of fewer captures than its code has; a call through
    a number; a closure bound from another binding (`v3`), or given another
    value. -/
example : (elabS (irNumW cbW [["let", "1", "closure", "__closure_1", "1", "c"]] callW [] [])).isNone := by
  decide +kernel
example : (elabS (irNumW cbW [["let", "1", "closure", "__closure_1", "0"]] callW [] [])).isNone := by
  decide +kernel
example : (elabS (irNumW cbW litW [["eval", "callind", "1", "v0"]] [] [])).isNone := by decide +kernel
def v3W : SIR := [["v", "3", "1", "1", "0", "1", "-1", "g", cloTyW]]
example : (elabS (irNumW cbW litW [["let", "3", "use", "v2"], ["eval", "callind", "2", "v3", "c"]] v3W [])).isNone := by
  decide +kernel
example : (elabS (irNumW cbW litW [["assign", "v2", "use", "v2"]] [] [])).isNone := by decide +kernel
/-- …and where the copy's value is handed back at once (stricter: the
    translator checks the copy only past that case). -/
example : (elabS (irNumW cbW litW [["let", "3", "use", "v2"], ["ret", "v3"]] v3W [])).isNone := by decide +kernel

/-- A closure handed to a `sink` parameter is refused (nurlc copies it there,
    unseen in the core IR), to a read-only one it is not. -/
def fnTakesW (fl : String) : SIR := [["fn", "g", "i64", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", fl, "1", "-1", "h", cloTyW], ["scope"], ["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irNumW cbW litW [["eval", "call", "g", "1", "v2"]] [] (fnTakesW "4"))).isNone := by decide +kernel
example : (elabS (irNumW cbW litW [["eval", "call", "g", "1", "v2"]] [] (fnTakesW "0"))).isSome := by decide +kernel

/-- A capture the code takes by pointer (flag 8) is refused for a number,
    and is `inout` for a Vec; a capture of a Vec of raw strings is refused
    (the translator follows numbers and buffers of numbers only); a closure
    parameter taken `inout` is refused. -/
def irVecW (ct cf : String) (body : SIR) : SIR :=
  irCloW "__closure_1" ct cf "0" cloTyW [] [["let", "0", "call", "vec_new__" ++ (if ct == "%Vec__str" then "str" else "i64"), "0"]]
    litW body [] []
example : (elabS (irCloW "__closure_1" "i64" "8" "0" cloTyW cbW [["let", "0", "use", "c"]] litW callW [] [])).isNone := by
  decide +kernel
example : (elabS (irVecW "%Vec__i64" "8" callW)).isSome := by decide +kernel
example : (elabS (irVecW "%Vec__str" "0" callW)).isNone := by decide +kernel
example : (elabS (irCloW "__closure_1" "i64" "0" "2" cloTyW cbW [["let", "0", "use", "c"]] litW callW [] [])).isNone := by
  decide +kernel

/-- A Vec captured by a literal that moves it in (the binding named no more
    after it) is the environment's (the code: the environment, `x`); named
    after the literal, it is a capture by name (the code: the environment,
    `x`, the Vec). -/
example : ((elabS (irVecW "%Vec__i64" "0" callW)).map fun r => r.1.head?.map (·.params.length)) =
    some (some 2) := by decide +kernel
example : ((elabS (irVecW "%Vec__i64" "0" (callW ++ [["eval", "call", "vec_len__i64", "1", "v0"]]))).map fun r =>
    r.1.head?.map (·.params.length)) = some (some 3) := by decide +kernel

/-- An interface whose result is a slice is refused (the translator makes
    no such result); one whose result is a Vec is not (an empty one). -/
example : (elabS (irCloW "__closure_1" "i64" "0" "0" "{ %Slice__i64 (i8*, i64)*, i8* }" cbW [["let", "0", "use", "c"]]
    litW callW [] [])).isNone := by decide +kernel
example : (elabS (irCloW "__closure_1" "i64" "0" "0" "{ %Vec__i64 (i8*, i64)*, i8* }" cbW [["let", "0", "use", "c"]]
    litW callW [] [])).isSome := by decide +kernel

/-- Stricter than the translator: a literal of a function not named as a
    closure's code; a closure's code naming a variable it does not declare,
    where the translation passes over it (a `line`; where it is read the
    translator stops too); variables not in id order; a `let x` of
    `nurl_println_int` (whose `eval` is in the subset). -/
example : (elabS (irCloW "clo1" "i64" "0" "0" cloTyW cbW [["let", "0", "use", "c"]]
    [["let", "1", "closure", "clo1", "1", "v0"]] callW [] [])).isNone := by decide +kernel
example : (elabS (irNumW [["line", "v7"]] litW callW [] [])).isNone := by decide +kernel
example : (elabS (irNumW [["eval", "scalar", "1", "v7"]] litW callW [] [])).isNone := by decide +kernel
example : (elabS (irNumW [["line", "7"]] litW callW [] [])).isSome := by decide +kernel
example : (elabS ([["fn", "main", "i64", "0", "1", "a.nu", "0", ""], ["v", "1", "1", "1", "0", "1", "-1", "a", "i64"],
    ["v", "0", "1", "1", "0", "1", "-1", "f", cloTyW], ["scope"], ["ret", "c"], ["end"], ["endfn"]])).isNone := by
  decide +kernel
example : (elabS ([["fn", "main", "i64", "0", "1", "a.nu", "0", ""], ["v", "0", "1", "1", "0", "1", "-1", "f", cloTyW],
    ["v", "1", "1", "1", "0", "1", "-1", "a", "i64"], ["scope"], ["ret", "c"], ["end"], ["endfn"]])).isSome := by
  decide +kernel
example : (elabS (irNumW cbW litW [["let", "3", "call", "nurl_println_int", "1", "c"]]
    [["v", "3", "1", "1", "0", "1", "-1", "r", "i64"]] [])).isNone := by decide +kernel
example : (elabS (irNumW cbW litW [["eval", "call", "nurl_println_int", "1", "v0"]] [] [])).isSome := by
  decide +kernel
/-- …and a closure's code in a program with no closure type, which no literal
    can pack. -/
example : (elabS ([["fn", "__closure_1", "i64", "0", "1", "a.nu", "0", ""], ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++
    irM [] [["ret", "c"]] [])).isNone := by decide +kernel
example : (elabS ([["fn", "f1", "i64", "0", "1", "a.nu", "0", ""], ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++
    irM [] [["ret", "c"]] [])).isSome := by decide +kernel

/-- A closure's code reading `changes` (`__changes`): its first `call` of a
    changer whose first argument is the capture's text. -/
example : changesB (strs [["eval", "call", "vec_push__i64", "2", "v0", "v1"]]) 0 = true ∧
    changesB (strs [["eval", "call", "vec_len__i64", "1", "v0"]]) 0 = false ∧
    changesB (strs [["eval", "call", "vec_push__i64", "2", "v00", "v1"]]) 0 = false := by decide +kernel

/-! ### Witnesses (step 7: structs and options) -/

/-- `tools/ncore/certify/struct_fields_read.nu`'s core IR (its `sum` lines
    and the program's `ty` lines; the file `a.nu`). -/
def irStruct : SIR := [
  ["fn", "sum", "i64", "1", "3", "a.nu", "0", ""], ["v", "0", "0", "0", "0", "3", "-1", "p", "%P"],
  ["scope"], ["line", "3"], ["eval", "scalar", "2", "v0/x", "v0/y"], ["ret", "c"], ["end"], ["endfn"],
  ["fn", "main", "i64", "0", "5", "a.nu", "0", ""], ["v", "0", "2", "1", "0", "6", "-1", "", "%P"],
  ["v", "1", "1", "1", "0", "6", "-1", "p", "%P"],
  ["scope"], ["line", "6"], ["let", "0", "agg", "-", "2", "c", "c", "%P"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["line", "7"], ["eval", "call", "sum", "1", "v1"], ["ret", "c"], ["end"], ["endfn"],
  ["ty", "%P", "1", "0-----", "P", "A", "0", "F", "2", "x", "i64", "y", "i64", "V", "0"],
  ["ty", "i64", "1", "0-----", "", "A", "0", "F", "0", "V", "0"],
  ["sum", "sum", "1", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The term `nurl-cert translate` prints for it, written out: the struct is
    a pair of its numbers (`.prod .int .int`), its literal the pair of two
    temporaries, each field read through the pair into a temporary (`.fst`,
    `.snd`) before the statement that reads it. -/
def pStruct : Prog := [
  { params := [(.inp, .prod .int .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 3 (.fst 0) (.letv 4 (.snd 0) (.letv 2 (.expr (.add .any (.lt
      (.add (.add (.lit 0) (.var 3)) (.var 4)) (.lit 0)))) (.assign 1 (.expr .any))))) (.exit 0)), nvars := 6 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 4 (.expr .any) (.letv 5 (.expr .any) (.letv 1 (.pair 4 5)
      (.letv 2 (.var 1) (.letcall 3 0 [2] (.assign 0 (.expr .any))))))) (.exit 0)), nvars := 7 }]

theorem elab_struct : elabIR (encIR irStruct) = some (pStruct, .letcall 0 1 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- `tools/ncore/certify/option_built_and_matched.nu`'s core IR. -/
def irOpt : SIR := [
  ["fn", "pick", "{ i1, i64 }", "1", "1", "a.nu", "0", ""], ["v", "0", "0", "0", "0", "1", "-1", "k", "i64"],
  ["v", "1", "2", "1", "0", "1", "-1", "", "void"], ["v", "2", "2", "2", "0", "1", "-1", "", "{ i1, i64 }"],
  ["v", "3", "2", "1", "0", "1", "-1", "", "{ i1, i64 }"],
  ["scope"], ["line", "1"], ["eval", "scalar", "2", "v0", "c"], ["let", "1", "none"], ["if", "c"], ["scope"],
  ["let", "2", "agg", "F", "0", "{", "i1,", "i64", "}"], ["ret", "v2"], ["drop", "2"], ["end"], ["else"], ["scope"],
  ["end"], ["end"], ["drop", "1"], ["let", "3", "agg", "T", "1", "v0", "{", "i1,", "i64", "}"], ["ret", "v3"],
  ["drop", "3"], ["end"], ["endfn"],
  ["fn", "main", "i64", "0", "3", "a.nu", "0", ""], ["v", "0", "2", "1", "0", "4", "-1", "", "{ i1, i64 }"],
  ["v", "1", "1", "1", "0", "4", "-1", "o", "{ i1, i64 }"], ["v", "2", "2", "1", "0", "5", "-1", "", "void"],
  ["v", "3", "1", "2", "0", "5", "-1", "x", "i64"],
  ["scope"], ["line", "4"], ["let", "0", "call", "pick", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["line", "5"], ["let", "2", "none"], ["match", "v1"], ["arm", "T"], ["scope"], ["let", "3", "payload", "v1", "T", "0"],
  ["ret", "v3"], ["end"], ["arm", "F"], ["scope"], ["ret", "c"], ["end"], ["end"], ["drop", "2"], ["end"], ["endfn"],
  ["ty", "{ i1, i64 }", "1", "0c----", "", "A", "0", "F", "2", "", "i1", "", "i64", "V", "0"],
  ["sum", "pick", "1", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The translator's term for it, written out: the option is `.sum .int
    .int`, `None` its first variant (`.inl` of a temporary), `Some k` its
    second (`.inr`); the match tests the tag (`.isl`), the `None` arm first,
    and the `T` arm lends the payload (`.getr`). -/
def pOpt : Prog := [
  { params := [(.inp, .int)], resTy := .sum .int .int, resOwn := true, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 6 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 0)) .any)
      (.lit 0)))) (.letv 2 (.expr .any) (.seq (.ite .any (.seq (.letv 5 (.expr .any) (.letv 3 (.inl 5 .int)
      (.assign 1 (.var 3)))) (.exit 0)) .skip) (.letv 4 (.inr .int 0) (.assign 1 (.var 4)))))) (.exit 0)),
    nvars := 8 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.letv 5 (.expr .any) (.letcall 1 0 [5] (.letv 2 (.var 1) (.letv 3 (.expr .any)
      (.ite (.isl 2) (.seq (.assign 0 (.expr .any)) (.exit 0))
        (.seq (.letv 4 (.getr 2) (.assign 0 (.expr (.var 4)))) (.exit 0))))))), nvars := 7 }]

theorem elab_opt : elabIR (encIR irOpt) = some (pOpt, .letcall 0 1 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- A `main` with a struct `%S` (fields `a` of type `ta`, `b` of type `tb`):
    its literal of two untracked numbers into `v0`, moved into `v1`, a
    number `v2`, then `body`. -/
def tyS2 (ta tb : String) : SIR := [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "2", "a", ta, "b", tb, "V", "0"]]
def vsS : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%S"], ["v", "1", "1", "1", "0", "1", "-1", "s", "%S"],
  ["v", "2", "1", "1", "0", "1", "-1", "n", "i64"]]
def irS (tyl body : SIR) : SIR :=
  irM vsS ([["let", "0", "agg", "-", "2", "c", "c", "%S"], ["let", "1", "use", "v0"], ["drop", "0"]] ++ body ++
    [["ret", "c"]]) tyl

/-- A number field's value read into a variable is in the subset; an
    owning field's (a `Vec`) is refused, as the translator refuses it (it
    would move out of its struct); so is a nested path, and a field the
    struct does not have. -/
example : (elabS (irS (tyS2 "%Vec__i64" "i64") [["let", "2", "use", "v1/b"]])).isSome := by decide +kernel
example : (elabS (irS (tyS2 "%Vec__i64" "i64") [["let", "2", "use", "v1/a"]])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "i64" "i64") [["let", "2", "use", "v1/b/a"]])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "i64" "i64") [["let", "2", "use", "v1/z"]])).isNone := by decide +kernel

/-- Struct types, as the translator takes them: a field of raw text is
    refused (a `String` is not); so is a closure in a field, and a struct
    inside itself (through an option field; an option of a number is
    not). Stricter: two fields of one name. -/
example : (elabS (irS (tyS2 "i8*" "i64") [])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "%String" "i64") [])).isSome := by decide +kernel
example : (elabS (irS (tyS2 "{ i64 (i8*)*, i8* }" "i64") [])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "{ i1, %S }" "i64") [])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "{ i1, i64 }" "i64") [])).isSome := by decide +kernel
example : (elabS (irS [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "a", "i64", "V", "0"]] [])).isNone := by
  decide +kernel

/-- A struct of no fields, and one with no `ty` line, are refused. Stricter:
    a name the translator reads as a number behind its `%` (`%i64`) is
    refused though a `ty` line gives it fields. A channel's name
    (`%Channel__…`) is never read as a struct's, as the translator reads it:
    a channel of a struct is refused though a `ty` line gives the name
    fields, and a channel of numbers is a channel (step 9). -/
def irTy (t : String) (tyl : SIR) : SIR := irM [["v", "0", "1", "1", "0", "1", "-1", "x", t]] [["ret", "c"]] tyl
example : (elabS (irTy "%S" [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "0", "V", "0"]])).isNone := by decide +kernel
example : (elabS (irTy "%S" [])).isNone := by decide +kernel
example : (elabS (irTy "%i64" [["ty", "%i64", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "b", "i64", "V", "0"]])).isNone := by
  decide +kernel
example : (elabS (irTy "%Channel__S" [["ty", "%Channel__S", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "b", "i64",
    "V", "0"], ["ty", "%S", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "b", "i64", "V", "0"]])).isNone := by decide +kernel
example : (elabS (irTy "%Channel__i64" [["ty", "%Channel__i64", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "b", "i64",
    "V", "0"]])).isSome := by decide +kernel
/-- …and an option of a closure (the translator: a closure inside a value). -/
example : (elabS (irTy "{ i1, { i64 (i8*)*, i8* } }" [])).isNone := by decide +kernel
example : (elabS (irTy "{ i1, %String }" [])).isSome := by decide +kernel

/-- A field read by a library call goes through the pairs (`rdF`); a field
    of a type that is no struct of the subset (a `Vec`'s handle `ctl`) is
    refused (stricter: the translator reads any type's `ty` line), and so is
    a field of a struct of one field named other than its field (stricter:
    the translator does not read the name). -/
def vsV : SIR := [["v", "0", "1", "1", "0", "1", "-1", "v", "%Vec__i64"]]
example : (elabS (irM vsV [["let", "0", "call", "vec_new__i64", "0"], ["eval", "call", "vec_len__i64", "1", "v0/ctl"],
    ["ret", "c"]] [["ty", "%Vec__i64", "0", "1c----", "Vec", "A", "1", "i64", "F", "1", "ctl", "i8*", "V", "0"]])).isNone := by
  decide +kernel
example : (elabS (irM vsV [["let", "0", "call", "vec_new__i64", "0"], ["eval", "call", "vec_len__i64", "1", "v0"],
    ["ret", "c"]] [["ty", "%Vec__i64", "0", "1c----", "Vec", "A", "1", "i64", "F", "1", "ctl", "i8*", "V", "0"]])).isSome := by
  decide +kernel
def irW (fld : String) : SIR := irM [["v", "0", "1", "1", "0", "1", "-1", "k", "i64"], ["v", "1", "1", "1", "0", "1", "-1", "w", "%W"]]
  [["let", "0", "use", "c"], ["let", "1", "agg", "-", "1", "v0", "%W"], ["eval", "scalar", "1", fld], ["ret", "c"]]
  [["ty", "%W", "1", "0-----", "W", "A", "0", "F", "1", "n", "i64", "V", "0"]]
example : (elabS (irW "v1/n")).isSome := by decide +kernel
example : (elabS (irW "v1/m")).isNone := by decide +kernel

/-- Literals: an option's only into a variable of an option type, and given
    a variable (an `eval` of one is refused, as the translator refuses it);
    a struct's of two operands at least, or of one. -/
def vsO (t : String) : SIR := [["v", "0", "1", "1", "0", "1", "-1", "o", t]]
example : (elabS (irM (vsO "{ i1, i64 }") [["let", "0", "agg", "F", "0", "{", "i1,", "i64", "}"], ["ret", "c"]] [])).isSome := by
  decide +kernel
example : (elabS (irM (vsO "i64") [["let", "0", "agg", "F", "0", "{", "i1,", "i64", "}"], ["ret", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irM (vsO "{ i1, i64 }") [["eval", "agg", "T", "1", "c", "{", "i1,", "i64", "}"], ["ret", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irS (tyS2 "i64" "i64") [["let", "2", "agg", "-", "0", "%S"]])).isNone := by decide +kernel

/-- An option's payload is read where its `T` arm matched (`payload v T 0`,
    `.getr`); any other payload is refused (the translator reads a result's
    error, `F`, only in a program that spawns, which is outside the
    subset). -/
def irM2 (arms : SIR) : SIR := irM [["v", "0", "1", "1", "0", "1", "-1", "o", "{ i1, i64 }"],
  ["v", "1", "1", "2", "0", "1", "-1", "x", "i64"]]
  ([["let", "0", "agg", "T", "1", "c", "{", "i1,", "i64", "}"], ["match", "v0"]] ++ arms ++ [["end"], ["ret", "c"]]) []
def armT (pl : SIR) : SIR := [["arm", "T"], ["scope"]] ++ pl ++ [["end"]]
def armF : SIR := [["arm", "F"], ["scope"], ["end"]]
example : (elabS (irM2 (armT [["let", "1", "payload", "v0", "T", "0"]] ++ armF))).isSome := by decide +kernel
example : (elabS (irM2 (armT [["let", "1", "payload", "v0", "F", "0"]] ++ armF))).isNone := by decide +kernel
/-- A match's arms are `T` and `F`, in either order; one name twice is
    refused, as the translator refuses it, and so are three arms (stricter:
    the translator takes the last block of a repeated name). -/
example : (elabS (irM2 (armF ++ armT []))).isSome := by decide +kernel
example : (elabS (irM2 (armT [] ++ armT []))).isNone := by decide +kernel
example : (elabS (irM2 (armT [] ++ armF ++ armT []))).isNone := by decide +kernel

/-! ### Witnesses (step 8: destructor frames) -/

/-- `tools/ncore/certify/destructor_frame_left_by_an_early_return.nu`'s core
    IR (its program's `ty` line and `sum` lines; the file `a.nu`). -/
def irDtor : SIR := [
  ["fn", "drop__W", "void", "1", "5", "a.nu", "0", ""], ["v", "0", "0", "0", "0", "5", "-1", "self", "%W"],
  ["scope"], ["line", "5"], ["eval", "call", "nurl_println", "1", "v0/v"], ["end"], ["endfn"],
  ["fn", "pick", "i64", "1", "7", "a.nu", "0", ""], ["v", "0", "0", "0", "0", "7", "-1", "k", "i64"],
  ["v", "1", "2", "1", "0", "8", "-1", "", "%String"], ["v", "2", "1", "1", "4096", "8", "-1", "s", "%String"],
  ["v", "3", "2", "1", "0", "9", "-1", "", "i8*"], ["v", "4", "2", "1", "0", "9", "-1", "", "%W"],
  ["v", "5", "1", "1", "0", "9", "-1", "w", "%W"], ["v", "6", "2", "1", "0", "10", "-1", "", "void"],
  ["scope"], ["line", "8"], ["let", "1", "call", "string_from", "1", "c"], ["let", "2", "use", "v1"], ["drop", "1"],
  ["line", "9"], ["let", "3", "call", "string_data", "1", "v2"], ["let", "4", "agg", "-", "1", "v3", "%W"],
  ["let", "5", "use", "v4"], ["drop", "4"], ["drop", "3"], ["line", "10"], ["eval", "scalar", "2", "v0", "c"],
  ["let", "6", "none"], ["if", "c"], ["scope"], ["ret", "c"], ["end"], ["else"], ["scope"], ["end"], ["end"],
  ["drop", "6"], ["line", "11"], ["ret", "c"], ["end"], ["endfn"],
  ["fn", "main", "i64", "0", "14", "a.nu", "0", ""], ["scope"], ["line", "14"], ["eval", "call", "pick", "1", "c"],
  ["ret", "c"], ["end"], ["endfn"],
  ["ty", "%W", "3", "1-d---", "W", "A", "0", "F", "1", "v", "i8*", "V", "0"],
  ["sum", "drop__W", "1", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"],
  ["sum", "pick", "1", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The term `nurl-cert translate` prints for it, written out: `%W` is A2's
    `.dtor 0 u`, `0` its destructor `drop__W`, `u` its one field of raw text
    (a view, `.slice .int`) padded with a number; the destructor reads its
    field through the pair (`.fst`); `w`'s literal is the pair of the view
    and a temporary, bound by `.letd`, and so is `w` itself, whose frame the
    early return leaves. -/
def pDtor : Prog := [
  { params := [(.inp, .dtor 0 (.prod (.slice .int) .int))], resTy := .int, resOwn := false, lends := [],
    rholds := [], outHolds := [], body := .block (.seq (.letv 2 (.fst 0) (.letv 3 (.expr (.slen 2)) .skip))
      (.assign 1 (.expr (.lit 0)))), nvars := 5 },
  { params := [(.inp, .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 2 (.new .int) (.letv 3 (.var 2) (.letv 4 (.view 3)
      (.letv 9 (.expr .any) (.letd 5 0 (.pair 4 9) (.letd 6 0 (.var 5)
        (.letv 8 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 0)) .any) (.lit 0))))
          (.letv 7 (.expr .any) (.seq (.ite .any (.seq (.assign 1 (.expr .any)) (.exit 0)) .skip)
            (.assign 1 (.expr .any))))))))))) (.exit 0)), nvars := 11 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 1 (.expr .any) (.letcall 2 1 [1] (.assign 0 (.expr .any))))
      (.exit 0)), nvars := 4 }]

theorem elab_dtor : elabIR (encIR irDtor) = some (pDtor, .letcall 0 2 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- A program of the destructor type `%W` (one field `v` of type `ft`, its
    `ty` line's drops `dr`) and a destructor named `dn`, then `main`: `v0` a
    literal of `%W` moved into `w` (`v1`), its other variables `vs` and
    statements `body`, then the lines `extra`. -/
def tyW (dr ft : String) : SIR := [["ty", "%W", "3", dr, "W", "A", "0", "F", "1", "v", ft, "V", "0"]]
def fnDropW (dn : String) : SIR := [["fn", dn, "void", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "self", "%W"], ["scope"], ["end"], ["endfn"]]
def irDW (dn dr ft : String) (vs body extra : SIR) : SIR :=
  fnDropW dn ++ irM ([["v", "0", "2", "1", "0", "1", "-1", "", "%W"], ["v", "1", "1", "1", "0", "1", "-1", "w", "%W"]] ++ vs)
    ([["let", "0", "agg", "-", "1", "c", "%W"], ["let", "1", "use", "v0"], ["drop", "0"]] ++ body ++ [["ret", "c"]])
    (tyW dr ft ++ extra)
def dW : String := "1-d---"

/-- The program's destructors: `drop__X` is `%X`'s, a struct of the
    program's. Refused, stricter (the translator takes any name): one for a
    number type (`drop__i64`, which the translator would take for every
    `i64`'s, since it asks `%t` too), one of no type (`drop__`), one whose
    type is spelled with a `%`. And a `ty` line whose drops say `d` for a
    type with no `drop__` of the program's (a destructor the translation
    does not see), as the translator refuses a value of it; with its own,
    or without the `d`, it is in the subset. -/
example : (elabS (irDW "drop__W" dW "i64" [] [] [])).isSome := by decide +kernel
example : (elabS (irDW "drop__i64" "1-----" "i64" [] [] [])).isNone := by decide +kernel
example : (elabS (irDW "drop__" "1-----" "i64" [] [] [])).isNone := by decide +kernel
example : (elabS (irDW "drop__%W" "1-----" "i64" [] [] [])).isNone := by decide +kernel
example : (elabS (irDW "drop__V" dW "i64" [] [] [])).isNone := by decide +kernel
example : (elabS (irDW "drop__V" "1-----" "i64" [] [] [])).isSome := by decide +kernel

/-- (step 9) A `ty` line whose drops say `d` for a type no value of the
    program has (a library's, as `stdlib/std/channel.nu` brings) leaves the
    program in the subset; a value of that type is refused, as the
    translator refuses it, a variable's or a struct's field; a `d` on a type
    named like a number behind its `%` refuses the program (stricter). -/
def tyRaw (nm : String) : SIR := [["ty", nm, "3", dW, "RawBlock", "A", "0", "F", "2", "ptr", "i64", "size", "i64", "V", "0"]]
example : (elabS (irDW "drop__W" dW "i64" [] [] (tyRaw "%RawBlock"))).isSome := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" [["v", "2", "1", "1", "0", "1", "-1", "r", "%RawBlock"]] []
    (tyRaw "%RawBlock"))).isNone := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" [["v", "2", "1", "1", "0", "1", "-1", "t", "%S"]] []
    (tyRaw "%RawBlock" ++ tyS2 "%RawBlock" "i64"))).isNone := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" [] [] (tyRaw "%i64"))).isNone := by decide +kernel

/-- The binding is a `letd` of the destructor, a struct of one number field
    padded with a number (`.prod .int .int`), its literal the pair of two
    temporaries; a value of a destructor type is never returned at once
    (the translator's rule: here `w` is handed back as a number). -/
def pDW : Prog := [
  { params := [(.inp, .dtor 0 (.prod .int .int))], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq .skip (.assign 1 (.expr (.lit 0)))), nvars := 3 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 2 (.expr .any) (.letv 3 (.expr .any) (.letd 1 0 (.pair 2 3)
      (.assign 0 (.var 1))))) (.exit 0)), nvars := 5 }]
example : elabS (fnDropW "drop__W" ++ irM [["v", "0", "1", "1", "0", "1", "-1", "w", "%W"]]
    [["let", "0", "agg", "-", "1", "c", "%W"], ["ret", "v0"]] (tyW dW "i64")) = some (pDW, .letcall 0 1 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)

/-- A destructor struct's fields: raw text is a view (the translator's
    rule; a struct of the subset refuses it), a `String` a buffer. Refused as
    the translator refuses them: a struct of no fields, and a destructor
    type with no `ty` line. Stricter: a closure in its field (the
    translator takes one in a struct of one field), and a destructor type
    inside another type (a struct's field, an option's payload), which the
    translator takes there. -/
example : (elabS (irDW "drop__W" dW "i8*" [] [] [])).isSome := by decide +kernel
example : (elabS (irDW "drop__W" dW "%String" [] [] [])).isSome := by decide +kernel
example : (elabS (fnDropW "drop__W" ++ irM [["v", "0", "1", "1", "0", "1", "-1", "w", "%W"]] [["ret", "c"]]
    [["ty", "%W", "3", dW, "W", "A", "0", "F", "0", "V", "0"]])).isNone := by decide +kernel
example : (elabS (fnDropW "drop__W" ++ irM [["v", "0", "1", "1", "0", "1", "-1", "w", "%W"]] [["ret", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irDW "drop__W" dW "{ i64 (i8*)*, i8* }" [] [] [])).isNone := by decide +kernel
def vsT (t : String) : SIR := [["v", "2", "1", "1", "0", "1", "-1", "t", t]]
example : (elabS (irDW "drop__W" dW "i64" (vsT "%S") [] (tyS2 "%W" "i64"))).isNone := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" (vsT "%S") [] (tyS2 "i64" "i64"))).isSome := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" (vsT "{ i1, %W }") [] [])).isNone := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" (vsT "{ i1, i64 }") [] [])).isSome := by decide +kernel

/-- Refused as the translator refuses them: a destructor value a call hands
    back (here the library's `string_from`; a `String` there is not), a
    destructor binding assigned (a plain struct's is not), a destructor
    value handed back, and a destructor parameter `sink`, by its flags or by
    the walk's summary (read only, it is not). -/
example : (elabS (irDW "drop__W" dW "i64" (vsT "%W") [["let", "2", "call", "string_from", "1", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irDW "drop__W" dW "i64" (vsT "%String") [["let", "2", "call", "string_from", "1", "c"]] [])).isSome := by
  decide +kernel
def bodyAsg : SIR := [["let", "2", "agg", "-", "1", "c", "%W"], ["assign", "v1", "use", "v2"]]
def vsAsg : SIR := [["v", "2", "2", "1", "0", "1", "-1", "", "%W"]]
example : (elabS (irDW "drop__W" dW "i64" vsAsg bodyAsg [])).isNone := by decide +kernel
example : (elabS (irDW "drop__V" "1-----" "i64" vsAsg bodyAsg [])).isSome := by decide +kernel
def fnMkW : SIR := [["fn", "mk", "%W", "0", "1", "a.nu", "0", ""], ["v", "0", "1", "1", "0", "1", "-1", "w", "%W"],
  ["scope"], ["let", "0", "agg", "-", "1", "c", "%W"], ["ret", "v0"], ["end"], ["endfn"]]
example : (elabS (irDW "drop__W" dW "i64" [] [] fnMkW)).isNone := by decide +kernel
example : (elabS (irDW "drop__V" "1-----" "i64" [] [] fnMkW)).isSome := by decide +kernel
def fnEatW (fl : String) : SIR := [["fn", "eat", "i64", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", fl, "1", "-1", "w", "%W"], ["scope"], ["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irDW "drop__W" dW "i64" [] [] (fnEatW "4"))).isNone := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" [] [] (fnEatW "2"))).isNone := by decide +kernel
example : (elabS (irDW "drop__W" dW "i64" [] [] (fnEatW "0" ++ [["sum", "eat", "1", "sink=0"]]))).isNone := by
  decide +kernel
example : (elabS (irDW "drop__W" dW "i64" [] [] (fnEatW "0"))).isSome := by decide +kernel

/-- Stricter (the translator takes them): a destructor value bound from a
    call through a closure, and a closure's code with a variable of a
    destructor type; of a number, both are in the subset. -/
example : (elabS (irNumW cbW litW [["let", "3", "callind", "2", "v2", "c"]]
    [["v", "3", "1", "1", "0", "1", "-1", "r", "%W"]] (fnDropW "drop__W" ++ tyW dW "i64"))).isNone := by decide +kernel
example : (elabS (irNumW cbW litW [["let", "3", "callind", "2", "v2", "c"]]
    [["v", "3", "1", "1", "0", "1", "-1", "r", "i64"]] (fnDropW "drop__W" ++ tyW dW "i64"))).isSome := by decide +kernel
example : (elabS (irNumW (cbW ++ [["v", "2", "1", "1", "0", "1", "-1", "u", "%W"], ["let", "2", "agg", "-", "1", "c", "%W"]])
    litW callW [] (fnDropW "drop__W" ++ tyW dW "i64"))).isNone := by decide +kernel
example : (elabS (irNumW (cbW ++ [["v", "2", "1", "1", "0", "1", "-1", "u", "i64"], ["let", "2", "use", "c"]])
    litW callW [] (fnDropW "drop__W" ++ tyW dW "i64"))).isSome := by decide +kernel

/-! ### Witnesses (step 9: channels) -/

/-- `tools/ncore/certify/chan_int_sent_and_received.nu`'s core IR (its
    program's function, a library type with a destructor, as
    `stdlib/std/channel.nu` brings, and its `sum` line; the file `a.nu`). -/
def irChan : SIR := [
  ["fn", "main", "i64", "0", "3", "a.nu", "0", ""],
  ["v", "0", "2", "1", "0", "4", "-1", "", "%Channel__i64"], ["v", "1", "1", "1", "4096", "4", "-1", "ch", "%Channel__i64"],
  ["v", "2", "2", "1", "0", "6", "-1", "", "{ i1, i64 }"], ["v", "3", "1", "1", "4096", "6", "-1", "got", "{ i1, i64 }"],
  ["v", "4", "2", "1", "0", "7", "-1", "", "i64"], ["v", "5", "1", "2", "0", "7", "-1", "v", "i64"],
  ["v", "6", "1", "1", "0", "7", "-1", "r", "i64"],
  ["scope"], ["line", "4"], ["let", "0", "call", "chan_new__i64", "0"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["line", "5"], ["eval", "call", "chan_send__i64", "2", "v1", "c"],
  ["line", "6"], ["let", "2", "call", "chan_recv__i64", "1", "v1"], ["let", "3", "use", "v2"], ["drop", "2"],
  ["line", "7"], ["let", "4", "none"], ["match", "v3"], ["arm", "T"], ["scope"], ["let", "5", "payload", "v3", "T", "0"],
  ["assign", "v4", "use", "v5"], ["end"], ["arm", "F"], ["scope"], ["end"], ["end"], ["let", "6", "use", "c"], ["drop", "4"],
  ["line", "8"], ["eval", "call", "chan_close__i64", "1", "v1"],
  ["line", "9"], ["eval", "scalar", "2", "v6", "c"], ["ret", "c"], ["end"], ["endfn"],
  ["ty", "%MutexImpl", "3", "1-d---", "MutexImpl", "A", "0", "F", "1", "blk", "%RawBlock", "V", "0"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The term `nurl-cert translate` prints for it, written out: the channel
    a `lockNew` of a fresh queue and a 0 flag, moved into `ch`; the send a
    `chanSend` of a temporary; the receive an owned option (`chanRecv
    true`), matched; the close a `chanClose`. -/
def pChan : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 12 (.new .int) (.letv 13 (.expr (.lit 0)) (.letv 14 (.pair 12 13)
      (.letv 1 (.lockNew (.prod (.vec .int) .int) 14) (.letv 2 (.var 1) (.letv 10 (.expr .any)
      (.letv 11 (.chanSend 2 10) (.letv 3 (.chanRecv true 2) (.letv 4 (.var 3) (.letv 5 (.expr .any)
      (.seq (.ite (.isl 4) .skip (.letv 6 (.getr 4) (.assign 5 (.expr (.var 6)))))
        (.letv 7 (.expr .any) (.letv 9 (.chanClose 2)
          (.letv 8 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 7)) .any) (.lit 0))))
            (.assign 0 (.expr .any)))))))))))))))) (.exit 0)), nvars := 16 }]

theorem elab_chan : elabIR (encIR irChan) = some (pChan, .letcall 0 0 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- A program of one channel `ch` (`v0`, of type `%Channel__<el>`, made by
    `chan_new__<el>`), then the statements `body`. -/
def irCh (el : String) (body : SIR) : SIR :=
  irM [["v", "0", "1", "1", "0", "1", "-1", "ch", "%Channel__" ++ el]]
    ([["let", "0", "call", "chan_new__" ++ el, "0"]] ++ body ++ [["ret", "c"]]) []

/-- Refused as the translator refuses them: a channel of raw text or of a
    struct (`__chan_elem`), a channel call on a literal (its rule needs a
    variable, and no other takes the call), a `chan_new` given an argument;
    their neighbours are in the subset: a channel of `String`s or of `Vec`s
    of numbers, each call on the channel, a share of it, a receive that
    does not wait. -/
example : (elabS (irCh "i64" [])).isSome := by decide +kernel
example : (elabS (irCh "String" [])).isSome := by decide +kernel
example : (elabS (irCh "Vec__i64" [])).isSome := by decide +kernel
example : (elabS (irCh "str" [])).isNone := by decide +kernel
example : (elabS (irCh "W" [])).isNone := by decide +kernel
example : (elabS (irCh "i64" [["eval", "call", "chan_send__i64", "2", "v0", "c"],
    ["eval", "call", "chan_try_recv__i64", "1", "v0"], ["eval", "call", "chan_close__i64", "1", "v0"]])).isSome := by
  decide +kernel
example : (elabS (irCh "i64" [["eval", "call", "chan_send__i64", "2", "c", "c"]])).isNone := by decide +kernel
example : (elabS (irCh "i64" [["eval", "call", "chan_close__i64", "1", "c"]])).isNone := by decide +kernel
example : (elabS (irCh "i64" [["eval", "call", "chan_new__i64", "1", "c"]])).isNone := by decide +kernel
example : (elabS (irCh "i64" [["eval", "call", "chan_send__str", "2", "v0", "c"]])).isNone := by decide +kernel
example : (elabS (irM [["v", "0", "1", "1", "0", "1", "-1", "a", "%Channel__i64"],
    ["v", "1", "1", "1", "0", "1", "-1", "b", "%Channel__i64"]]
    [["let", "0", "call", "chan_new__i64", "0"], ["let", "1", "call", "Channel_share__i64", "1", "v0"], ["ret", "c"]] [])).isSome := by
  decide +kernel

/-! ### Witnesses (step 10: threads) -/

/-- `tools/ncore/certify/thread_spawned_with_a_number_capture.nu`'s core IR
    (its program's functions, `%ThreadErr`'s `ty` line; the file `a.nu`). -/
def thrCode : SIR := [
  ["fn", "__closure_1", "void", "0", "6", "a.nu", "0", ""],
  ["v", "0", "3", "0", "0", "6", "-1", "n", "i64"], ["v", "1", "1", "2", "0", "5", "-1", "m", "i64"],
  ["scope"], ["scope"], ["eval", "scalar", "2", "v0", "c"], ["let", "1", "use", "c"], ["end"], ["end"], ["endfn"]]
def thrVs : SIR := [
  ["v", "0", "1", "1", "0", "4", "-1", "n", "i64"], ["v", "1", "2", "1", "0", "5", "-1", "", "{ void (i8*)*, i8* }"],
  ["v", "2", "1", "1", "0", "5", "-1", "body", "{ void (i8*)*, i8* }"],
  ["v", "3", "2", "1", "0", "6", "-1", "", "{ i1, %Thread, %ThreadErr }"],
  ["v", "4", "1", "1", "4096", "6", "-1", "r", "{ i1, %Thread, %ThreadErr }"],
  ["v", "5", "2", "1", "0", "7", "-1", "", "i64"], ["v", "6", "1", "2", "0", "7", "-1", "t", "%Thread"],
  ["v", "7", "1", "2", "0", "7", "-1", "_", "%ThreadErr"]]
def thrSpawn : SIR := [
  ["let", "0", "use", "c"], ["let", "1", "closure", "__closure_1", "1", "v0"], ["let", "2", "use", "v1"], ["drop", "1"],
  ["let", "3", "call", "thread_spawn_owned", "1", "v2"], ["let", "4", "use", "v3"], ["drop", "3"]]
def thrMatch : SIR := [
  ["let", "5", "none"], ["match", "v4"], ["arm", "T"], ["scope"], ["let", "6", "payload", "v4", "T", "0"],
  ["eval", "call", "thread_join", "1", "v6"], ["end"], ["arm", "F"], ["scope"], ["let", "7", "payload", "v4", "F", "0"],
  ["end"], ["end"], ["ret", "c"], ["drop", "5"]]
def thrErrTy : SIR := [["ty", "%ThreadErr", "1", "0-----", "ThreadErr", "A", "0", "F", "0", "V", "2", "ThreadCreate", "0",
  "ThreadOther", "0"]]
/-- The program: the closure code, then `main` with variables `vs`, the
    statements `body`, then the lines `extra`. -/
def irThrW (vs body extra : SIR) : SIR :=
  thrCode ++ [["fn", "main", "i64", "0", "3", "a.nu", "0", ""]] ++ vs ++ [["scope"]] ++ body ++ [["end"], ["endfn"]] ++ extra
def irThr : SIR := irThrW thrVs (thrSpawn ++ thrMatch) thrErrTy

/-- The term `nurl-cert translate` prints for it, written out: the closure
    code (its number capture read out of its environment), `main` (the
    literal packed at the spawned closure's interface, of class `send`;
    the spawn a call of the wrapper, its result the ok variant around a
    handle; the match on `isl`, the error arm first, `getl` its payload),
    the closure type's interface at class `any` and at class `send`, and
    the spawn wrapper, which takes the closure over and calls it. -/
def pThr : Prog := [
  { params := [(.inp, .int)], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.letv 2 (.expr (.var 0)) (.seq (.letv 5 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 2)) .any)
      (.lit 0)))) (.letv 3 (.expr .any) .skip)) (.assign 1 (.expr (.lit 0))))), nvars := 7 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.expr .any) (.letv 2 (.pack [0] .int [3] 1 []) (.letv 3 (.var 2)
      (.letcall 10 4 [3] (.letv 11 (.expr (.lit 0)) (.letv 4 (.inr .int 11) (.letv 5 (.var 4) (.letv 6 (.expr .any)
      (.seq (.ite (.isl 5) (.letv 8 (.getl 5) .skip) (.letv 7 (.getr 5) (.letv 9 (.expr (.var 7)) .skip)))
        (.assign 0 (.expr .any))))))))))) (.exit 0)), nvars := 13 },
  { params := [(.inp, .fn [2] .any)], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.assign 1 (.expr (.lit 0))) (.exit 0)), nvars := 2 },
  { params := [(.inp, .fn [3] .send)], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.assign 1 (.expr (.lit 0))) (.exit 0)), nvars := 2 },
  { params := [(.sink, .fn [3] .send)], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.callc 2 0 0 3 [] .skip) (.seq (.assign 1 (.expr (.lit 0))) (.exit 0))), nvars := 3 }]

theorem elab_thread : elabIR3 (encIR irThr) = some (pThr, [4], .letcall 0 1 [] .skip) :=
  elabIs3_sound _ _ _ _ (by decide +kernel)

/-- A program that spawns is A3's: `elabIR` (A2's) answers none for it. -/
example : elabL (strs irThr) = none := by decide +kernel

def elabS3 (l : SIR) : Option (Prog × List Nat × Stmt) := elabL3 (strs l)

/-- Refused as the translator refuses them: a spawned closure used again
    after its spawn (here spawned twice), a `%ThreadErr` whose variants
    carry more than numbers, a result's literal; stricter: a function's
    spawned closures of two closure types. Their neighbours are in the
    subset. -/
example : (elabS3 irThr).isSome := by decide +kernel
example : (elabS3 (irThrW thrVs (thrSpawn ++ [["eval", "call", "thread_spawn_owned", "1", "v2"]] ++ thrMatch)
    thrErrTy)).isNone := by decide +kernel
example : (elabS3 (irThrW thrVs (thrSpawn ++ thrMatch) [["ty", "%ThreadErr", "1", "0-----", "ThreadErr", "A", "0",
    "F", "0", "V", "2", "ThreadCreate", "1", "%String", "ThreadOther", "0"]])).isNone := by decide +kernel
example : (elabS3 (irThrW (thrVs ++ [["v", "8", "1", "1", "0", "7", "-1", "e", "{ i1, %Thread, %ThreadErr }"]])
    (thrSpawn ++ [["let", "8", "agg", "F", "1", "c"]] ++ thrMatch) thrErrTy)).isNone := by decide +kernel
example : (elabS3 (irThrW (thrVs ++ [["v", "8", "1", "1", "0", "7", "-1", "e", "{ i1, i64 }"]])
    (thrSpawn ++ [["let", "8", "agg", "F", "1", "c"]] ++ thrMatch) thrErrTy)).isSome := by decide +kernel
/-- …and a result type where the program spawns no thread (A2's
    translation reads it as an option of two members, which it is not). -/
example : (elabL (strs (irM [["v", "0", "1", "1", "0", "1", "-1", "r", "{ i1, i64, i64 }"]] [["ret", "c"]] []))).isNone := by
  decide +kernel

/-! ### Conditional stub elaboration witness (AGORA-1036) -/

def irCondW : SIR := [
  ["fn", "log_msg", "void", "0", "1", "a.nu", "0", ""],
  ["eval", "call", "nurl_print", "1", "c"],
  ["endfn"],
  ["fn", "main", "i64", "0", "2", "a.nu", "0", ""],
  ["eval", "call", "log_msg", "0"],
  ["ret", "c"],
  ["endfn"]
]

def pCondW : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .seq .skip .panic, nvars := 0 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letcall 1 0 [] (.assign 0 (.expr .any))) (.exit 0)), nvars := 3 }
]

theorem elab_cond : elabIRCond (encIR irCondW) [0] = some (pCondW, .letcall 0 1 [] .skip) :=
  elabIsCond_sound _ _ _ _ (by decide +kernel)

/-- Without `0` assumed, `nurl_print` is outside the subset and `elabIR` answers none. -/
example : elabIR (encIR irCondW) = none := by decide +kernel

/-- An out-of-range assumed index is refused. -/
example : elabIRCond (encIR irCondW) [2] = none := by decide +kernel

end C.Elab
