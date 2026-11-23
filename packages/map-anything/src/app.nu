// packages/map-anything/src/app.nu — what `map-anything serve` is, for the
// recon-kit service: the name and defaults, the option fields the page
// shows for this model, and how the start request becomes this CLI's
// options line. Everything else (jobs, uploads, the page, the viewer, 3-D
// objects) is recon-kit's.

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `deps/recon-kit/src/serve.nu`

@ __ma_opts_html → s {
    ^ `    <div><label for="o-stride">take every Nth input</label><input id="o-stride" type="number" min="1" max="100" value="1"></div>
    <div><label for="o-px">pixel stride</label><input id="o-px" type="number" min="1" max="16" value="1">
      <div class="hint">2 = &frac14; of the points, a lighter cloud</div></div>
    <div><label for="o-conf">drop least confident %</label><input id="o-conf" type="number" min="0" max="95" value="0"></div>
    <div><label for="o-win">attention window</label><input id="o-win" type="number" min="4" max="64" value="24">
      <div class="hint">views per window; lower if the GPU runs out</div></div>
    <div><label for="o-align">align views (sweeps)</label><input id="o-align" type="number" min="0" max="10" value="3">
      <div class="hint">merges the double copies of walls; 0 = off</div></div>
    <div><label for="o-mv">views that must agree</label><input id="o-mv" type="number" min="0" max="4" value="1">
      <div class="hint">drops floaters only one view sees; 0 = off</div></div>
    <div><label for="o-vox">voxel size (mm)</label><input id="o-vox" type="text" value="auto">
      <div class="hint">auto, off, or millimetres: one averaged point per cell</div></div>
    <div class="chk"><input id="o-sky" type="checkbox"><label for="o-sky" style="margin:0;color:inherit;font-size:13px">mask sky (outdoor)</label></div>`
}

@ __ma_opts_js → s {
    ^ `function voxelMm() {
  var t = $("o-vox").value.trim().toLowerCase();
  if (t === "" || t === "auto") return -1;
  if (t === "off" || t === "0") return 0;
  var v = parseInt(t, 10);
  return isNaN(v) ? -1 : Math.min(999, Math.max(1, v));
}
function modelOptions() {
  return {
    stride: num("o-stride", 1, 100, 1), pixel_stride: num("o-px", 1, 16, 1),
    conf_pct: num("o-conf", 0, 95, 0), window: num("o-win", 4, 64, 24),
    mask_sky: $("o-sky").checked, align: num("o-align", 0, 10, 3), mv_check: num("o-mv", 0, 4, 1),
    voxel_mm: voxelMm()
  };
}
function modelHint(n, isVid, picked) {
  return n > num("o-win", 4, 64, 24) ? "more than one window: stitched" : "";
}
document.addEventListener("DOMContentLoaded", function () { $("o-win").addEventListener("input", viewsHint); });`
}

// The start request → `map-anything` options, every number clamped.
@ __ma_opts Json j → String {
    : i maxv ( rk_jint j `max_views` 0 2000 24 )
    : i stride ( rk_jint j `stride` 1 100 1 )
    : i pstride ( rk_jint j `pixel_stride` 1 16 1 )
    : i conf ( rk_jint j `conf_pct` 0 95 0 )
    : i win ( rk_jint j `window` 4 64 24 )
    : b sky ( rk_jbool j `mask_sky` )
    : i align ( rk_jint j `align` 0 10 3 )
    : i mvneed ( rk_jint j `mv_check` 0 4 1 )
    : i voxmm ( rk_jint j `voxel_mm` -1 999 -1 )  // -1 auto, 0 off, else millimetres
    : String opts ( string_from `--max-views ` )
    ( string_push_int opts maxv )
    // a video is sampled across its whole length (the CLI's default with a
    // view budget); "every frame" keeps the old fixed rate
    ? == maxv 0 { ( string_push_str opts ` --fps 2` ) } {}
    ( string_push_str opts ` --stride ` ) ( string_push_int opts stride )
    ( string_push_str opts ` --pixel-stride ` ) ( string_push_int opts pstride )
    ( string_push_str opts ` --window ` ) ( string_push_int opts win )
    ? > conf 0 { ( string_push_str opts ` --conf-pct ` ) ( string_push_int opts conf ) } {}
    ? sky { ( string_push_str opts ` --mask-sky` ) } {}
    ? > align 0 { ( string_push_str opts ` --align ` ) ( string_push_int opts align ) } {}
    ? > mvneed 0 { ( string_push_str opts ` --mv-check ` ) ( string_push_int opts mvneed ) } {}
    ( rk_push_voxel opts voxmm )
    ^ opts
}

@ ma_app → RkApp {
    ^ @ RkApp {
        ( string_from `map-anything` )
        ( string_from `photos or a video in &rarr; a metric 3-D point cloud out` )
        ( string_from `A NURL port of Meta's <a href="https://github.com/facebookresearch/map-anything">MapAnything</a> (facebook/map-anything-apache).` )
        8807
        ( string_from `.map-anything` )
        ( string_from `MAP_ANYTHING_PASSWORD` )
        ( string_from ( __ma_opts_html ) )
        ( string_from ( __ma_opts_js ) )
        24
        120
        \ Json j → String { ^ ( __ma_opts j ) }
    }
}
