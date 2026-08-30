// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// ============================================================
//  tests/dashboard_test.js — the model manager's generated metadata editor.
//
//  The Advanced box in the model drawer used to hard-code the editable half
//  of the metadata as `{schedule, versions}`. When `max_data_points` became
//  patchable through the API it stayed invisible in the one editor that
//  exists to reach it. It is now generated: the top-level keys come from the
//  `editable_fields` list the service publishes, and every field below them
//  is walked out of the metadata's own shape.
//
//  That makes the editor a piece of logic with no server behind it, so it
//  gets a test. The pure functions are lifted out of the page and driven
//  against a realistic metadata object; the DOM is stubbed, since what is
//  under test is the path/type bookkeeping, not the rendering.
//
//  Run:  node tests/dashboard_test.js [static/modelmanager.html]
//  Skipped by the suite when node is not installed.
// ============================================================
const fs = require('fs');
const page = process.argv[2] || (__dirname + '/../static/modelmanager.html');
const src = fs.readFileSync(page, 'utf8');
// Only the pure pieces of the dashboard are under test; give the rest stubs.
const shim = `
  const esc = (x) => String(x).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  let DOMVALUES = [];
  const document = { querySelectorAll: () => DOMVALUES };
  const toast = (...a) => { LASTTOAST = a; };
  let LASTTOAST = null;
  const $ = () => ({ style:{}, classList:{ toggle(){}, add(){}, remove(){} }, value:"" });
`;
const body = src.match(/let ADV_LEAVES[\s\S]*?\n\/\/ Revert:[\s\S]*?\n}\n/)[0];
const fn = new Function(shim + body + `
  return { editableSlice, advForm, advCollect, get leaves(){ return ADV_LEAVES; },
           setDom(v){ DOMVALUES = v; } };
`);
const M = fn();

const meta = {
  model_name: "t", column_types: { temp: "numeric" }, feature_names: ["temp"],
  n_points_seen: 60, max_data_points: 150000,
  schedule: { below_max: 50, at_max: 1000 },
  versions: {
    daily:      { window_minutes: 1440, n_estimators: 300, contamination: "auto",
                  decision_margin: 0.06, enabled: true },
    timevector: { window_size: 8, step_size: 1, contamination: 0.05,
                  decision_margin: 0.02, enabled: false },
  },
  editable_fields: ["schedule", "max_data_points", "versions"],
};

let pass = 0, fail = 0;
const ck = (c, l) => { if (c) { pass++; console.log("ok   " + l); } else { fail++; console.log("FAIL " + l); } };

// 1. The slice follows editable_fields, not a hard-coded list.
const sl = M.editableSlice(meta);
ck(JSON.stringify(Object.keys(sl)) === '["schedule","max_data_points","versions"]',
   "slice takes exactly the keys the service published");
ck(sl.column_types === undefined && sl.feature_names === undefined,
   "the learned half is not in the slice");
ck(M.editableSlice({ schedule: {}, versions: {} }).max_data_points === undefined,
   "a service without editable_fields falls back to schedule+versions");

// 2. Every leaf of the editable half becomes one input.
const html = M.advForm(meta);
const leaves = M.leaves.map(l => l.path.join("."));
ck(leaves.includes("max_data_points"), "a scalar top-level key gets a field");
ck(leaves.includes("schedule.below_max") && leaves.includes("schedule.at_max"),
   "a nested object is walked");
ck(leaves.includes("versions.daily.n_estimators") &&
   leaves.includes("versions.timevector.step_size"),
   "every version's every field is reachable — including the ones no hand-written form shows");
ck(M.leaves.filter(l => l.bool).length === 2, "booleans are the only checkboxes");
ck(/data-adv="0"/.test(html) && html.includes("max_data_points"), "the markup carries the indices");

// 3. Untouched form → the patch it rebuilds is the slice it came from.
const asDom = (vals) => M.leaves.map((l, i) => {
  const cur = l.path.reduce((o, k) => o[k], meta);
  const v = vals && i in vals ? vals[i] : cur;
  return { dataset: { adv: String(i) }, checked: !!v, value: String(v) };
});
M.setDom(asDom(null));
const round = M.advCollect();
ck(JSON.stringify(round) === JSON.stringify(sl), "an untouched form round-trips to the same JSON");

// 4. Coercion: numbers stay numbers, "auto" stays a word, empty is omitted.
const iMax = M.leaves.findIndex(l => l.path.join(".") === "max_data_points");
const iCont = M.leaves.findIndex(l => l.path.join(".") === "versions.daily.contamination");
const iStep = M.leaves.findIndex(l => l.path.join(".") === "versions.timevector.step_size");
M.setDom(asDom({ [iMax]: "500", [iCont]: "0.05", [iStep]: "" }));
const p2 = M.advCollect();
ck(p2.max_data_points === 500, "a typed number is sent as a number");
ck(p2.versions.daily.contamination === 0.05, "'auto' overwritten with a float is sent as a float");
ck(p2.versions.timevector.step_size === undefined, "an emptied box is an omitted field");
M.setDom(asDom({ [iCont]: "auto" }));
ck(M.advCollect().versions.daily.contamination === "auto", "a word stays a word");

// 5. A field the service adds later needs no dashboard change.
const future = Object.assign({}, meta, { warmup_hours: 12,
  editable_fields: ["schedule", "max_data_points", "versions", "warmup_hours"] });
M.advForm(future);
ck(M.leaves.some(l => l.path.join(".") === "warmup_hours"),
   "an unknown new editable key appears by itself");

console.log("dashboard_test: " + pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
