// packages/recon-kit/src/app.nu — RkApp, what a model package hands
// rk_serve (serve.nu) and what the page (ui.nu) is filled from. A module
// of its own because both need it and each must compile alone.

$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

// What a model package hands rk_serve: its name and defaults, the part of
// the page that is its own, and how the page's options become its CLI's.
: RkApp {
    String name  // `map-anything`: log lines, the sign-in realm, the title
    String tagline  // under the page title
    String about  // the page's footer (HTML): what the model is
    i port  // the default port
    String home_dir  // the default data directory under $HOME, `.map-anything`
    String pass_env  // the password's environment variable
    String opts_html  // the model's option fields (HTML), in the options grid
    String opts_js  // defines modelOptions() and modelHint(n, isVideo, picked)
    i views  // the views slider's default
    i views_max  // and its top
    // the start request's JSON → the options line for the CLI. Built from
    // validated numbers and fixed words: it goes through a shell (single-
    // quoted — and __rk_opts_ok refuses anything but [a-z0-9 .-] anyway).
    ( @ String Json ) opts
}
