// packages/f5tts/src/ui.nu — the page the server answers GET / with.
//
// One file, no build step, no CDN: the markup, the style and the script are a
// string in the binary, so a machine that has just installed f5tts and has no
// network still gets a working interface. It talks to the same endpoints as
// any other client — /voices, /models, /tts, /dialogue, /voices/add — so
// anything visible here is reachable with curl, and anything that works with
// curl shows up here.
//
// Nothing here names a model or a language. The model list is whatever the
// machine has, the voices are whatever somebody recorded, and the text box
// starts empty: a prefilled sentence in one language is a default for that
// language and a nuisance in every other.

$ `stdlib/core/string.nu`

@ f5_ui_html → s {
    ^ `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>f5tts</title>
<style>
:root{
  --bg:#fbfaf8; --panel:#fff; --ink:#1a1a18; --dim:#6b6a66; --line:#e6e3dd;
  --accent:#8a3324; --accent-ink:#fff; --field:#fff;
}
@media (prefers-color-scheme:dark){
  :root{ --bg:#16161a; --panel:#1e1e24; --ink:#eceaf0; --dim:#9a97a4;
         --line:#31313a; --accent:#d4644a; --accent-ink:#1a1a18; --field:#15151a; }
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header{padding:22px 20px 6px;max-width:940px;margin:0 auto}
h1{font-size:19px;margin:0;letter-spacing:-.01em}
h1 small{color:var(--dim);font-weight:400;font-size:13px;margin-left:10px}
main{max-width:940px;margin:0 auto;padding:12px 20px 60px;
  display:grid;gap:16px;grid-template-columns:1fr}
@media(min-width:820px){main{grid-template-columns:1fr 300px}}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px}
label{display:block;font-size:12px;color:var(--dim);margin:0 0 4px;
  text-transform:uppercase;letter-spacing:.06em}
textarea,input,select{width:100%;font:inherit;color:var(--ink);background:var(--field);
  border:1px solid var(--line);border-radius:7px;padding:9px 10px}
textarea{min-height:130px;resize:vertical;line-height:1.5}
.row{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));margin-top:12px}
button{font:inherit;font-weight:560;border:0;border-radius:7px;padding:10px 16px;cursor:pointer;
  background:var(--accent);color:var(--accent-ink)}
button.ghost{background:transparent;color:var(--ink);border:1px solid var(--line);font-weight:450}
button[disabled]{opacity:.5;cursor:default}
.bar{display:flex;gap:10px;align-items:center;margin-top:14px;flex-wrap:wrap}
.note{color:var(--dim);font-size:13px}
audio{width:100%;margin-top:14px}
.vlist{display:flex;flex-direction:column;gap:2px;max-height:250px;overflow:auto;margin-top:6px}
.vrow{display:flex;align-items:center;gap:8px;padding:5px 7px;border-radius:6px;cursor:pointer}
.vrow:hover{background:var(--bg)}
.vrow.on{background:var(--accent);color:var(--accent-ink)}
.vrow span{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.vrow button{padding:2px 7px;font-size:12px;background:transparent;color:inherit;opacity:.65}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--dim);margin:0 0 8px}
details{margin-top:14px}
summary{cursor:pointer;font-size:13px;color:var(--dim)}
.err{color:var(--accent);font-size:13px;margin-top:10px;white-space:pre-wrap}
fieldset{border:0;padding:0;margin:14px 0 0}
</style>
</head>
<body>
<header><h1>f5tts <small>speech synthesis, pure NURL</small></h1></header>
<main>
  <section class="card">
    <label for="text">Text</label>
    <textarea id="text" placeholder="Type what the voice should say."></textarea>
    <div class="row">
      <div><label for="model">Model</label><select id="model"></select></div>
      <div><label for="fmt">Format</label><select id="fmt">
        <option value="wav">wav</option><option value="mp3">mp3</option>
        <option value="pcm">pcm</option></select></div>
      <div><label for="steps">Steps</label><input id="steps" type="number" value="32" min="4" max="128"></div>
      <div><label for="seed">Seed</label><input id="seed" type="number" value="-1"></div>
    </div>
    <details>
      <summary>Advanced</summary>
      <div class="row">
        <div><label for="cfg">Guidance</label><input id="cfg" type="number" step="0.1" value="2"></div>
        <div><label for="sway">Sway</label><input id="sway" type="number" step="0.1" value="-1"></div>
        <div><label for="speed">Speed</label><input id="speed" type="number" step="0.05" value="1"></div>
        <div><label for="fade">Cross-fade</label><input id="fade" type="number" step="0.05" value="0.15"></div>
        <div><label for="rms">Target RMS</label><input id="rms" type="number" step="0.01" value="0.1"></div>
        <div><label for="retry">Retries</label><input id="retry" type="number" value="1" min="1" max="10"></div>
        <div><label for="wer">Max WER</label><input id="wer" type="number" step="0.05" value="0.15"></div>
      </div>
    </details>
    <div class="bar">
      <button id="go">Speak</button>
      <button id="dl" class="ghost" disabled>Download</button>
      <span class="note" id="status"></span>
    </div>
    <audio id="player" controls></audio>
    <div class="err" id="err"></div>
  </section>

  <aside class="card">
    <h2>Voices</h2>
    <div class="vlist" id="voices"></div>
    <fieldset>
      <h2>Add a voice</h2>
      <label for="nid">Id</label><input id="nid" placeholder="narrator">
      <label for="ntext" style="margin-top:8px">What the recording says</label>
      <textarea id="ntext" style="min-height:70px" placeholder="The exact words spoken in the recording."></textarea>
      <label for="nfile" style="margin-top:8px">Recording (wav)</label>
      <input id="nfile" type="file" accept="audio/wav,.wav">
      <div class="bar"><button id="add" class="ghost">Save voice</button></div>
    </fieldset>
  </aside>
</main>
<script>
const $ = s => document.querySelector(s);
const state = { voice: null, blob: null };
const tok = new URLSearchParams(location.search).get("token") || "";
const hdr = () => tok ? { "authorization": "Bearer " + tok } : {};

function say(m){ $("#status").textContent = m || ""; }
function oops(m){ $("#err").textContent = m || ""; }

async function loadVoices(){
  try{
    const r = await fetch("/voices", { headers: hdr() });
    const vs = await r.json();
    const box = $("#voices"); box.innerHTML = "";
    if(!vs.length) box.innerHTML = '<div class="note">No voices yet. Add one below.</div>';
    for(const v of vs){
      const row = document.createElement("div");
      row.className = "vrow" + (v.voice_id === state.voice ? " on" : "");
      const nm = document.createElement("span"); nm.textContent = v.voice_id;
      row.appendChild(nm);
      const play = document.createElement("button");
      play.textContent = "play"; play.title = "the reference recording";
      play.onclick = e => { e.stopPropagation();
        $("#player").src = "/voices/" + encodeURIComponent(v.voice_id) + "/sample"
          + (tok ? "?token=" + encodeURIComponent(tok) : ""); $("#player").play(); };
      row.appendChild(play);
      const del = document.createElement("button");
      del.textContent = "delete";
      del.onclick = async e => { e.stopPropagation();
        if(!confirm("Delete " + v.voice_id + "?")) return;
        await fetch("/voices/" + encodeURIComponent(v.voice_id), { method:"DELETE", headers: hdr() });
        if(state.voice === v.voice_id) state.voice = null;
        loadVoices(); };
      row.appendChild(del);
      row.onclick = () => { state.voice = v.voice_id; loadVoices(); };
      box.appendChild(row);
    }
    if(!state.voice && vs.length){ state.voice = vs[0].voice_id; loadVoices(); }
  }catch(e){ oops("Could not load the voices: " + e.message); }
}

async function loadModels(){
  try{
    const r = await fetch("/models", { headers: hdr() });
    const ms = await r.json();
    const sel = $("#model"); sel.innerHTML = "";
    for(const m of ms){
      const o = document.createElement("option");
      o.value = m.model_id;
      o.textContent = m.model_id + (m.on_this_machine ? "" : " (will be fetched)");
      if(m.current) o.selected = true;
      sel.appendChild(o);
    }
  }catch(e){ oops("Could not load the models: " + e.message); }
}

$("#go").onclick = async () => {
  oops("");
  if(!state.voice){ oops("Pick a voice first."); return; }
  const body = {
    voice_id: state.voice,
    text: $("#text").value,
    model_id: $("#model").value,
    output_format: $("#fmt").value,
    nfe_steps: +$("#steps").value,
    seed: +$("#seed").value,
    cfg_strength: +$("#cfg").value,
    sway_sampling_coef: +$("#sway").value,
    speed: +$("#speed").value,
    cross_fade_duration: +$("#fade").value,
    target_rms: +$("#rms").value,
    whisper_retry: +$("#retry").value,
    max_wer: +$("#wer").value
  };
  $("#go").disabled = true; $("#dl").disabled = true;
  const t0 = performance.now(); say("speaking…");
  try{
    const r = await fetch("/tts", { method:"POST",
      headers: Object.assign({ "content-type":"application/json" }, hdr()),
      body: JSON.stringify(body) });
    if(!r.ok){ const j = await r.json().catch(()=>({error:r.statusText})); throw new Error(j.error||r.statusText); }
    state.blob = await r.blob();
    $("#player").src = URL.createObjectURL(state.blob);
    $("#player").play();
    say(((performance.now()-t0)/1000).toFixed(1) + " s");
    $("#dl").disabled = false;
  }catch(e){ oops(e.message); say(""); }
  $("#go").disabled = false;
};

$("#dl").onclick = () => {
  if(!state.blob) return;
  const a = document.createElement("a");
  a.href = URL.createObjectURL(state.blob);
  a.download = (state.voice||"speech") + "." + $("#fmt").value;
  a.click();
};

$("#add").onclick = async () => {
  oops("");
  const f = $("#nfile").files[0];
  if(!$("#nid").value || !f){ oops("An id and a wav file are both required."); return; }
  const fd = new FormData();
  fd.append("voice_id", $("#nid").value);
  fd.append("ref_text", $("#ntext").value);
  fd.append("file", f);
  $("#add").disabled = true; say("saving…");
  try{
    const r = await fetch("/voices/add", { method:"POST", headers: hdr(), body: fd });
    if(!r.ok){ const j = await r.json().catch(()=>({error:r.statusText})); throw new Error(j.error||r.statusText); }
    $("#nid").value = ""; $("#ntext").value = ""; $("#nfile").value = "";
    say("saved"); loadVoices();
  }catch(e){ oops(e.message); say(""); }
  $("#add").disabled = false;
};

loadVoices(); loadModels();
</script>
</body>
</html>
`
}
