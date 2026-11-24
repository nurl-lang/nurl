// packages/lingbot-map/src/app.nu — what `lingbot-map serve` is, for the
// recon-kit service: the name and defaults, the option fields the page
// shows for this model, and how the start request becomes this CLI's
// options line. Everything else (jobs, uploads, the page, the viewer, 3-D
// objects) is recon-kit's.

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `deps/recon-kit/src/serve.nu`

@ __lm_opts_html → s {
    ^ `    <div><label for="o-size">input size (px)</label><input id="o-size" type="text" value="auto">
      <div class="hint">auto = the largest the GPU's free memory takes (518 at most); or a multiple of 14</div></div>
    <div><label for="o-conf">confidence threshold</label><input id="o-conf" type="number" min="1" max="10" step="0.5" value="1.5">
      <div class="hint">1&ndash;10: keep pixels the model is surer of than this; 1.5 is the reference's, 3&ndash;5 cleaner</div></div>
    <div><label for="o-px">pixel stride</label><input id="o-px" type="number" min="1" max="4" value="1">
      <div class="hint">1&ndash;4; 2 = &frac14; of the points, a lighter cloud</div></div>
    <div class="chk"><input id="o-vox" type="checkbox" checked><label for="o-vox" style="margin:0;color:inherit;font-size:13px">fuse on a voxel grid (one averaged point per cell)</label></div>`
}

@ __lm_opts_js → s {
    ^ `function modelOptions() {
  var t = $("o-size").value.trim().toLowerCase(), size = 0;
  if (t !== "" && t !== "auto") { size = parseInt(t, 10); if (isNaN(size)) size = 0; }
  var c = parseFloat($("o-conf").value);
  c = isNaN(c) ? 1.5 : Math.min(10, Math.max(1, c));
  return {
    image_size: size, conf_tenths: Math.round(c * 10),
    pixel_stride: num("o-px", 1, 4, 1), voxel: $("o-vox").checked
  };
}
function modelHint(n, isVid, picked) {
  return isVid ? "in order: the model follows the camera from frame to frame" : "taken in name order: the order is the camera's path";
}`
}

// The start request → `lingbot-map` options, every number clamped. The
// size is rounded down to whole patches; 0 is auto.
@ __lm_opts Json j → String {
    : i maxv ( rk_jint j `max_views` 0 2000 120 )
    : ~ i size ( rk_jint j `image_size` 0 518 0 )
    = size * / size 14 14
    // 1.0 is "the model knows nothing" (confidence is 1 + e^x): below it
    // nothing is dropped, and past 10 little of a scene is left — on the
    // courthouse 10 keeps an eighth of the points, 20 almost none
    : i conf ( rk_jint j `conf_tenths` 10 100 15 )
    : i pstride ( rk_jint j `pixel_stride` 1 4 1 )
    : String opts ( string_from `--max-views ` )
    ( string_push_int opts maxv )
    // every frame: the reference's own rate
    ? == maxv 0 { ( string_push_str opts ` --fps 10` ) } {}
    ( string_push_str opts ` --image-size ` )
    ? < size 224 { ( string_push_str opts `auto` ) } { ( string_push_int opts size ) }
    // tenths as a decimal, without a float in the options line
    ( string_push_str opts ` --conf ` )
    ( string_push_int opts / conf 10 )
    ( string_push_char opts 46 )
    ( string_push_int opts % conf 10 )
    ( string_push_str opts ` --pixel-stride ` ) ( string_push_int opts pstride )
    ? ( rk_jbool j `voxel` ) { ( string_push_str opts ` --voxel auto` ) } {}
    ^ opts
}

@ lm_app → RkApp {
    ^ @ RkApp {
        ( string_from `lingbot-map` )
        ( string_from `a video or photos in order &rarr; a 3-D point cloud, streamed frame by frame` )
        ( string_from `A NURL port of <a href="https://github.com/robbyant/lingbot-map">LingBot-Map</a> (robbyant/lingbot-map), a streaming 3-D reconstruction model.` )
        8808
        ( string_from `.lingbot-map` )
        ( string_from `LINGBOT_MAP_PASSWORD` )
        ( string_from ( __lm_opts_html ) )
        ( string_from ( __lm_opts_js ) )
        120
        600
        \ Json j → String { ^ ( __lm_opts j ) }
    }
}
