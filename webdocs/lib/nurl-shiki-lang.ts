import nurlGrammar from '../../tooling/vscode-nurl/syntaxes/nurl.tmLanguage.json';

// Reuses the VSCode extension's TextMate grammar so highlighting stays in
// sync with tooling/vscode-nurl/syntaxes/nurl.tmLanguage.json.
//
// Cast as `any`: TS's JSON-module inference turns differing `captures` key
// sets across pattern variants into a union with `"3"?: undefined`, which
// fails Shiki's `IRawCaptures` index signature even though the grammar is a
// valid TextMate definition at runtime.
export const nurlLang = {
  ...(nurlGrammar as any),
  name: 'nurl',
  aliases: ['nu'],
};

// nurl mark from public/graphics/nurl1.svg, recolored to `currentColor` so it
// follows the codeblock header's icon color in both themes.
export const nurlIcon =
  '<svg viewBox="0 0 489.06471 489.06814" fill="currentColor">' +
  '<g transform="translate(-3254.9645,-3384.7127)">' +
  '<path d="m 3620.7148,3614.9102 -0.1953,120.9121 0.3457,69.8593 h -91.7441 v -131.0937 l -126.041,98.5351 -38.5391,-49.2988 80.961,-63.291 h -190.5254 l -0.012,120.9453 c 0,51.1151 41.1409,92.2685 92.2559,92.2735 l 304.5078,0.029 c 51.1151,0 92.2705,-41.1409 92.2754,-92.2559 v -14.0371 z" />' +
  '<path d="m 3347.2676,3384.7129 c -51.1151,0 -92.2685,41.1408 -92.2735,92.2559 l -0.012,120.9921 v 0 h 190.5137 l -80.957,-63.289 38.5371,-49.2989 126.041,98.5333 v -131.0938 h 91.7441 l 123.1563,152.4121 0.012,-128.209 c 0,-51.115 -41.1428,-92.2685 -92.2578,-92.2734 z" />' +
  '</g></svg>';
