// mermaid-server/src/render.nu — SVG emission, entirely template-driven.
//
// Nothing here decides what a diagram looks like. Every colour, width,
// radius and font comes out of the `MmdTheme` the caller passes in, so a
// new look is a new TOML file and not a new branch in this file. Two
// mechanisms carry the template through:
//
//   * presentation attributes (`fill=`, `stroke=`) written per element
//     from `mmd_theme_var_str`, which resolves `node.<shape>.<key>`
//     before `node.<key>`; and
//   * a generated `<style>` block, ending with the template's own
//     `canvas.css`. CSS outranks presentation attributes, so a template
//     can restyle anything the key set does not cover yet.
//
// Arrow heads are drawn as real geometry rather than SVG markers: markers
// inherit neither `stroke` nor size cleanly across renderers, and the
// endpoint direction is already known here.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `graph.nu`
$ `theme.nu`
$ `layout.nu`

// ── Text helpers ─────────────────────────────────────────────────────

// XML-escape `text[from,to)` into `out`. The range form is what the
// multi-line label writer needs — slicing a copy per line would allocate
// once per tspan for nothing.
@ __mmdr_escape_range String out s text i n i from i to → v {
    : ~ i k from
    ~ < k to {
        : i c ( nurl_str_at text n k )
        ? == c 38 { ( string_push_str out `&amp;` ) } {
            ? == c 60 { ( string_push_str out `&lt;` ) } {
                ? == c 62 { ( string_push_str out `&gt;` ) } {
                    ? == c 34 { ( string_push_str out `&quot;` ) } {
                        ? == c 39 { ( string_push_str out `&#39;` ) } {
                            ( string_push_char out c )
                        }
                    }
                }
            }
        }
        = k + k 1
    }
}

@ __mmdr_escape String out s text → v {
    : i n ( nurl_str_len text )
    ( __mmdr_escape_range out text n 0 n )
}

@ __mmdr_attr_i String out s name i val → v {
    ( string_push_str out ` ` )
    ( string_push_str out name )
    ( string_push_str out `="` )
    ( string_push_int out val )
    ( string_push_str out `"` )
}

@ __mmdr_attr_s String out s name s val → v {
    ? == ( nurl_str_len val ) 0 { ^ v } {}
    ( string_push_str out ` ` )
    ( string_push_str out name )
    ( string_push_str out `="` )
    ( __mmdr_escape out val )
    ( string_push_str out `"` )
}

@ __mmdr_pt String out i x i y → v {
    ( string_push_int out x )
    ( string_push_str out `,` )
    ( string_push_int out y )
    ( string_push_str out ` ` )
}

@ __mmdr_isqrt i n → i {
    ? <= n 0 { ^ 0 } {}
    : ~ i x n
    : ~ i y / + x 1 2
    ~ < y x {
        = x y
        = y / + x / n x 2
    }
    ^ x
}

// ── Geometry ─────────────────────────────────────────────────────────
//
// The point where the ray from a box's centre in direction (dx,dy) leaves
// the box. Rect-shaped boxes clip on the frame; a diamond clips on
// |x|/hw + |y|/hh = 1; a circle on the ellipse. Everything is scaled by
// 1000 so integer division keeps a usable precision.

@ __mmdr_abs i x → i { ? < x 0 { ^ - 0 x } {} ^ x }

@ __mmdr_clip i shape i cx i cy i w i h i dx i dy → MmdPt {
    : i hw / w 2
    : i hh / h 2
    : i ax ( __mmdr_abs dx )
    : i ay ( __mmdr_abs dy )
    ? & == ax 0 == ay 0 { ^ @ MmdPt { cx cy } } {}

    : ~ i t 0
    ? == shape MMD_SHAPE_CIRCLE {
        : i ux ? > hw 0 / * ax 1000 hw 0
        : i uy ? > hh 0 / * ay 1000 hh 0
        : i k ( __mmdr_isqrt + * ux ux * uy uy )
        = t ? > k 0 / 1000000 k 0
    } {
        ? == shape MMD_SHAPE_DIAMOND {
            : i ux ? > hw 0 / * ax 1000 hw 0
            : i uy ? > hh 0 / * ay 1000 hh 0
            : i k + ux uy
            = t ? > k 0 / 1000000 k 0
        } {
            : ~ i tx 1000000000
            : ~ i ty 1000000000
            ? > ax 0 { = tx / * hw 1000 ax } {}
            ? > ay 0 { = ty / * hh 1000 ay } {}
            = t ? < tx ty tx ty
        }
    }
    ^ @ MmdPt { + cx / * dx t 1000 + cy / * dy t 1000 }
}

@ __mmdr_pt_at ( Vec MmdPt ) pts i k → MmdPt {
    ?? ( vec_get [MmdPt] pts k ) {
        T p → ^ p
        F _ → {}
    }
    ^ @ MmdPt { 0 0 }
}

// `from` moved `d` pixels towards `toward`.
@ __mmdr_shorten MmdPt from MmdPt toward i d → MmdPt {
    : i dx - . toward x . from x
    : i dy - . toward y . from y
    : i len ( __mmdr_isqrt + * dx dx * dy dy )
    ? <= len 0 { ^ from } {}
    ^ @ MmdPt { + . from x / * dx d len + . from y / * dy d len }
}

// ── Style block ──────────────────────────────────────────────────────

@ __mmdr_style String out MmdTheme t → v {
    ( string_push_str out `<style>\n` )
    ( string_push_str out `svg{font-family:` )
    ( string_push_str out ( mmd_theme_str t `canvas.font_family` `system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif` ) )
    ( string_push_str out `;font-size:` )
    ( string_push_int out ( mmd_theme_int t `canvas.font_size` 14 ) )
    ( string_push_str out `px}\n` )
    ( string_push_str out `.mmd-node text{font-weight:` )
    ( string_push_str out ( mmd_theme_str t `node.font_weight` `500` ) )
    ( string_push_str out `}\n` )
    ( string_push_str out `.mmd-edge-label text{font-size:` )
    ( string_push_int out ( mmd_theme_int t `edge.font_size` - ( mmd_theme_int t `canvas.font_size` 14 ) 2 ) )
    ( string_push_str out `px}\n` )
    ( string_push_str out `.mmd-edge path,.mmd-edge line{fill:none;stroke-linecap:round}\n` )
    : s css ( mmd_theme_str t `canvas.css` `` )
    ? > ( nurl_str_len css ) 0 {
        ( string_push_str out css )
        ( string_push_str out `\n` )
    } {}
    ( string_push_str out `</style>\n` )
}

// ── Node shapes ──────────────────────────────────────────────────────

@ __mmdr_shape_attrs String out MmdTheme t s nm → v {
    ( __mmdr_attr_s out `fill` ( mmd_theme_var_str t `node` nm `fill` `#eef2ff` ) )
    ( __mmdr_attr_s out `stroke` ( mmd_theme_var_str t `node` nm `stroke` `#4f46e5` ) )
    ( __mmdr_attr_s out `stroke-width` ( mmd_theme_var_str t `node` nm `stroke_width` `1.5` ) )
    ( __mmdr_attr_s out `stroke-dasharray` ( mmd_theme_var_str t `node` nm `dash` `` ) )
}

@ __mmdr_node_shape String out MmdTheme t i shape i x i y i w i h → v {
    : s nm ( mmd_shape_name shape )
    : i cx + x / w 2
    : i cy + y / h 2
    : i inset ( mmd_theme_var_int t `node` nm `inset` 18 )

    ? == shape MMD_SHAPE_CIRCLE {
        ( string_push_str out `<ellipse` )
        ( __mmdr_attr_i out `cx` cx )
        ( __mmdr_attr_i out `cy` cy )
        ( __mmdr_attr_i out `rx` / w 2 )
        ( __mmdr_attr_i out `ry` / h 2 )
        ( __mmdr_shape_attrs out t nm )
        ( string_push_str out ` />` )
        ^ v
    } {}

    ? == shape MMD_SHAPE_DIAMOND {
        ( string_push_str out `<polygon points="` )
        ( __mmdr_pt out cx y )
        ( __mmdr_pt out + x w cy )
        ( __mmdr_pt out cx + y h )
        ( __mmdr_pt out x cy )
        ( string_push_str out `"` )
        ( __mmdr_shape_attrs out t nm )
        ( string_push_str out ` />` )
        ^ v
    } {}

    ? == shape MMD_SHAPE_HEXAGON {
        : i ins ? < inset / w 3 inset / w 3
        ( string_push_str out `<polygon points="` )
        ( __mmdr_pt out + x ins y )
        ( __mmdr_pt out - + x w ins y )
        ( __mmdr_pt out + x w cy )
        ( __mmdr_pt out - + x w ins + y h )
        ( __mmdr_pt out + x ins + y h )
        ( __mmdr_pt out x cy )
        ( string_push_str out `"` )
        ( __mmdr_shape_attrs out t nm )
        ( string_push_str out ` />` )
        ^ v
    } {}

    ? | == shape MMD_SHAPE_PARALLELOGRAM | == shape MMD_SHAPE_PARALLELOGRAM_ALT
    | == shape MMD_SHAPE_TRAPEZOID == shape MMD_SHAPE_TRAPEZOID_ALT {
        : i ins ? < inset / w 3 inset / w 3
        ( string_push_str out `<polygon points="` )
        ? == shape MMD_SHAPE_PARALLELOGRAM {
            ( __mmdr_pt out + x ins y )
            ( __mmdr_pt out + x w y )
            ( __mmdr_pt out - + x w ins + y h )
            ( __mmdr_pt out x + y h )
        } {}
        ? == shape MMD_SHAPE_PARALLELOGRAM_ALT {
            ( __mmdr_pt out x y )
            ( __mmdr_pt out - + x w ins y )
            ( __mmdr_pt out + x w + y h )
            ( __mmdr_pt out + x ins + y h )
        } {}
        ? == shape MMD_SHAPE_TRAPEZOID {
            ( __mmdr_pt out + x ins y )
            ( __mmdr_pt out - + x w ins y )
            ( __mmdr_pt out + x w + y h )
            ( __mmdr_pt out x + y h )
        } {}
        ? == shape MMD_SHAPE_TRAPEZOID_ALT {
            ( __mmdr_pt out x y )
            ( __mmdr_pt out + x w y )
            ( __mmdr_pt out - + x w ins + y h )
            ( __mmdr_pt out + x ins + y h )
        } {}
        ( string_push_str out `"` )
        ( __mmdr_shape_attrs out t nm )
        ( string_push_str out ` />` )
        ^ v
    } {}

    ? == shape MMD_SHAPE_FLAG {
        : i ins ? < inset / w 4 inset / w 4
        ( string_push_str out `<polygon points="` )
        ( __mmdr_pt out x y )
        ( __mmdr_pt out + x w y )
        ( __mmdr_pt out + x w + y h )
        ( __mmdr_pt out x + y h )
        ( __mmdr_pt out + x ins cy )
        ( string_push_str out `"` )
        ( __mmdr_shape_attrs out t nm )
        ( string_push_str out ` />` )
        ^ v
    } {}

    ? == shape MMD_SHAPE_CYLINDER {
        : i ry ( mmd_theme_var_int t `node` nm `rim` 9 )
        : i hw / w 2
        ( string_push_str out `<path d="M ` )
        ( string_push_int out x )
        ( string_push_str out ` ` )
        ( string_push_int out + y ry )
        ( string_push_str out ` A ` )
        ( string_push_int out hw )
        ( string_push_str out ` ` )
        ( string_push_int out ry )
        ( string_push_str out ` 0 0 1 ` )
        ( string_push_int out + x w )
        ( string_push_str out ` ` )
        ( string_push_int out + y ry )
        ( string_push_str out ` L ` )
        ( string_push_int out + x w )
        ( string_push_str out ` ` )
        ( string_push_int out - + y h ry )
        ( string_push_str out ` A ` )
        ( string_push_int out hw )
        ( string_push_str out ` ` )
        ( string_push_int out ry )
        ( string_push_str out ` 0 0 1 ` )
        ( string_push_int out x )
        ( string_push_str out ` ` )
        ( string_push_int out - + y h ry )
        ( string_push_str out ` Z"` )
        ( __mmdr_shape_attrs out t nm )
        ( string_push_str out ` />` )
        ( string_push_str out `<path d="M ` )
        ( string_push_int out x )
        ( string_push_str out ` ` )
        ( string_push_int out + y ry )
        ( string_push_str out ` A ` )
        ( string_push_int out hw )
        ( string_push_str out ` ` )
        ( string_push_int out ry )
        ( string_push_str out ` 0 0 0 ` )
        ( string_push_int out + x w )
        ( string_push_str out ` ` )
        ( string_push_int out + y ry )
        ( string_push_str out `"` )
        ( __mmdr_attr_s out `fill` `none` )
        ( __mmdr_attr_s out `stroke` ( mmd_theme_var_str t `node` nm `stroke` `#4f46e5` ) )
        ( __mmdr_attr_s out `stroke-width` ( mmd_theme_var_str t `node` nm `stroke_width` `1.5` ) )
        ( string_push_str out ` />` )
        ^ v
    } {}

    // Everything else is a (possibly rounded) rectangle.
    : ~ i rx ( mmd_theme_var_int t `node` nm `radius` 6 )
    ? == shape MMD_SHAPE_STADIUM { = rx / h 2 } {}
    ? == shape MMD_SHAPE_ROUND { = rx ( mmd_theme_var_int t `node` nm `radius` / h 3 ) } {}
    ( string_push_str out `<rect` )
    ( __mmdr_attr_i out `x` x )
    ( __mmdr_attr_i out `y` y )
    ( __mmdr_attr_i out `width` w )
    ( __mmdr_attr_i out `height` h )
    ( __mmdr_attr_i out `rx` rx )
    ( __mmdr_shape_attrs out t nm )
    ( string_push_str out ` />` )
    ? == shape MMD_SHAPE_SUBROUTINE {
        : i ins ( mmd_theme_var_int t `node` nm `bar` 8 )
        : ~ i side 0
        ~ < side 2 {
            : i lx ? == side 0 + x ins - + x w ins
            ( string_push_str out `<line` )
            ( __mmdr_attr_i out `x1` lx )
            ( __mmdr_attr_i out `y1` y )
            ( __mmdr_attr_i out `x2` lx )
            ( __mmdr_attr_i out `y2` + y h )
            ( __mmdr_attr_s out `stroke` ( mmd_theme_var_str t `node` nm `stroke` `#4f46e5` ) )
            ( __mmdr_attr_s out `stroke-width` ( mmd_theme_var_str t `node` nm `stroke_width` `1.5` ) )
            ( string_push_str out ` />` )
            = side + side 1
        }
    } {}
}

// ── Text ─────────────────────────────────────────────────────────────

@ __mmdr_text String out s label i cx i cy i line_h s fill s cls → v {
    : i lines ( mmd_text_lines label )
    ( string_push_str out `<text` )
    ( __mmdr_attr_i out `x` cx )
    ( __mmdr_attr_i out `y` cy )
    ( __mmdr_attr_s out `class` cls )
    ( __mmdr_attr_s out `text-anchor` `middle` )
    ( __mmdr_attr_s out `dominant-baseline` `central` )
    ( __mmdr_attr_s out `fill` fill )
    ( string_push_str out `>` )

    : i n ( nurl_str_len label )
    : ~ i start 0
    : ~ i li 0
    : ~ i k 0
    ~ <= k n {
        : b at_end == k n
        : i c ? at_end 10 ( nurl_str_at label n k )
        ? | at_end == c 10 {
            ( string_push_str out `<tspan` )
            ( __mmdr_attr_i out `x` cx )
            ( string_push_str out ` dy="` )
            ( string_push_int out ? == li 0 / * - 1 lines line_h - 0 2 line_h )
            ( string_push_str out `">` )
            ( __mmdr_escape_range out label n start k )
            ( string_push_str out `</tspan>` )
            = li + li 1
            = start + k 1
        } {}
        = k + k 1
    }
    ( string_push_str out `</text>` )
}

// ── Arrow heads ──────────────────────────────────────────────────────
//
// `dx`/`dy` point along the edge, into the head. Lengths are scaled by
// 1000 so the unit vector survives integer division.

@ __mmdr_head String out MmdTheme t s lname i kind i px i py i dx i dy → v {
    ? == kind MMD_ARROW_NONE { ^ v } {}
    : i size ( mmd_theme_var_int t `edge` lname `arrow_size` 10 )
    : i len ( __mmdr_isqrt + * dx dx * dy dy )
    ? == len 0 { ^ v } {}
    : i ux / * dx 1000 len
    : i uy / * dy 1000 len
    : s colour ( mmd_theme_var_str t `edge` lname `arrow` ( mmd_theme_var_str t `edge` lname `stroke` `#64748b` ) )

    ? == kind MMD_ARROW_POINT {
        : i bx - px / * ux size 1000
        : i by - py / * uy size 1000
        : i wx / * - 0 uy / size 2 1000
        : i wy / * ux / size 2 1000
        ( string_push_str out `<polygon points="` )
        ( __mmdr_pt out px py )
        ( __mmdr_pt out + bx wx + by wy )
        ( __mmdr_pt out - bx wx - by wy )
        ( string_push_str out `"` )
        ( __mmdr_attr_s out `fill` colour )
        ( __mmdr_attr_s out `class` `mmd-arrow` )
        ( string_push_str out ` />` )
        ^ v
    } {}

    ? == kind MMD_ARROW_CIRCLE {
        : i r / size 3
        : i bx - px / * ux r 1000
        : i by - py / * uy r 1000
        ( string_push_str out `<circle` )
        ( __mmdr_attr_i out `cx` bx )
        ( __mmdr_attr_i out `cy` by )
        ( __mmdr_attr_i out `r` r )
        ( __mmdr_attr_s out `fill` ( mmd_theme_str t `canvas.background` `#ffffff` ) )
        ( __mmdr_attr_s out `stroke` colour )
        ( __mmdr_attr_s out `stroke-width` ( mmd_theme_var_str t `edge` lname `stroke_width` `1.6` ) )
        ( string_push_str out ` />` )
        ^ v
    } {}

    // Cross.
    : i r / size 3
    : i ax / * ux r 1000
    : i ay / * uy r 1000
    : i bx / * - 0 uy r 1000
    : i by / * ux r 1000
    ( string_push_str out `<line` )
    ( __mmdr_attr_i out `x1` + - px ax bx )
    ( __mmdr_attr_i out `y1` + - py ay by )
    ( __mmdr_attr_i out `x2` - + px ax bx )
    ( __mmdr_attr_i out `y2` - + py ay by )
    ( __mmdr_attr_s out `stroke` colour )
    ( __mmdr_attr_s out `stroke-width` `2` )
    ( string_push_str out ` />` )
    ( string_push_str out `<line` )
    ( __mmdr_attr_i out `x1` - - px ax bx )
    ( __mmdr_attr_i out `y1` - - py ay by )
    ( __mmdr_attr_i out `x2` + + px ax bx )
    ( __mmdr_attr_i out `y2` + + py ay by )
    ( __mmdr_attr_s out `stroke` colour )
    ( __mmdr_attr_s out `stroke-width` `2` )
    ( string_push_str out ` />` )
}

// ── Edges ────────────────────────────────────────────────────────────

@ __mmdr_edge_label String out MmdTheme t s label i cx i cy i font → v {
    ? == ( nurl_str_len label ) 0 { ^ v } {}
    : i units ( _mmdl_text_units label )
    : i tw / * units font 100
    : i lines ( mmd_text_lines label )
    : i pad ( mmd_theme_int t `edge.label_pad` 5 )
    : i bw + tw * 2 pad
    : i bh + * lines + font 4 * 2 - pad 2
    ( string_push_str out `<g class="mmd-edge-label">` )
    ( string_push_str out `<rect` )
    ( __mmdr_attr_i out `x` - cx / bw 2 )
    ( __mmdr_attr_i out `y` - cy / bh 2 )
    ( __mmdr_attr_i out `width` bw )
    ( __mmdr_attr_i out `height` bh )
    ( __mmdr_attr_i out `rx` ( mmd_theme_int t `edge.label_radius` 4 ) )
    ( __mmdr_attr_s out `fill` ( mmd_theme_str t `edge.label_fill` `#ffffff` ) )
    ( __mmdr_attr_s out `stroke` ( mmd_theme_str t `edge.label_stroke` `` ) )
    ( string_push_str out ` />` )
    ( __mmdr_text out label cx cy + font 4 ( mmd_theme_str t `edge.text` `#475569` ) `` )
    ( string_push_str out `</g>` )
}

// A link from a node to itself: a bow on the side the layout does NOT use
// for the flow, so it never sits on top of the node's other links.
@ __mmdr_self_loop String out MmdTheme t MmdEdge e s lname i dir i x i y i w i h i font → v {
    : i r ( mmd_theme_int t `edge.loop_size` 26 )
    : b horizontal | == dir MMD_DIR_LR == dir MMD_DIR_RL
    // Anchor points and the outward normal: right side for a vertical
    // flow, top edge for a horizontal one.
    : i ax ? horizontal + x / w 3 + x w
    : i ay ? horizontal y + y / h 3
    : i bx ? horizontal + x / * 2 w 3 + x w
    : i by ? horizontal y + y / * 2 h 3
    : i nx ? horizontal 0 r
    : i ny ? horizontal - 0 r 0

    ( string_push_str out `<path d="M ` )
    ( string_push_int out ax )
    ( string_push_str out ` ` )
    ( string_push_int out ay )
    ( string_push_str out ` C ` )
    ( string_push_int out + ax ? horizontal - 0 r nx )
    ( string_push_str out ` ` )
    ( string_push_int out + ay ? horizontal ny - 0 r )
    ( string_push_str out ` ` )
    ( string_push_int out + bx ? horizontal r nx )
    ( string_push_str out ` ` )
    ( string_push_int out + by ? horizontal ny r )
    ( string_push_str out ` ` )
    ( string_push_int out bx )
    ( string_push_str out ` ` )
    ( string_push_int out by )
    ( string_push_str out `"` )
    ( __mmdr_attr_s out `fill` `none` )
    ( __mmdr_attr_s out `stroke` ( mmd_theme_var_str t `edge` lname `stroke` `#64748b` ) )
    ( __mmdr_attr_s out `stroke-width` ( mmd_theme_var_str t `edge` lname `stroke_width` `1.6` ) )
    ( __mmdr_attr_s out `stroke-dasharray` ( mmd_theme_var_str t `edge` lname `dash` `` ) )
    ( string_push_str out ` />` )
    // The tangent at the end of the bow is the last control point → end.
    ( __mmdr_head out t lname . e head bx by
    - bx + bx ? horizontal r nx
    - by + by ? horizontal ny r )
    ( __mmdr_edge_label out t ( string_data . e label )
    + / + ax bx 2 ? horizontal 0 / * r 3 4
    + / + ay by 2 ? horizontal - 0 / * r 3 4 0
    font )
}

// Draw one edge as a path through `pts`, pulling the first and last
// segments back out of whatever arrow head sits there, then the heads and
// the label. `pts` always has at least two points.
@ __mmdr_polyline String out MmdTheme t MmdEdge e s lname ( Vec MmdPt ) pts → v {
    : i n ( vec_len [MmdPt] pts )
    ? < n 2 { ^ v } {}
    : i size ( mmd_theme_var_int t `edge` lname `arrow_size` 10 )

    : MmdPt p0 ( __mmdr_pt_at pts 0 )
    : MmdPt p1 ( __mmdr_pt_at pts 1 )
    : MmdPt pl ( __mmdr_pt_at pts - n 1 )
    : MmdPt pp ( __mmdr_pt_at pts - n 2 )

    : MmdPt s0 ? != . e tail MMD_ARROW_NONE ( __mmdr_shorten p0 p1 - size 1 ) p0
    : MmdPt s1 ? != . e head MMD_ARROW_NONE ( __mmdr_shorten pl pp - size 1 ) pl

    ( string_push_str out `<path d="M ` )
    ( string_push_int out . s0 x )
    ( string_push_str out ` ` )
    ( string_push_int out . s0 y )
    : ~ i k 1
    ~ < k - n 1 {
        : MmdPt m ( __mmdr_pt_at pts k )
        ( string_push_str out ` L ` )
        ( string_push_int out . m x )
        ( string_push_str out ` ` )
        ( string_push_int out . m y )
        = k + k 1
    }
    ( string_push_str out ` L ` )
    ( string_push_int out . s1 x )
    ( string_push_str out ` ` )
    ( string_push_int out . s1 y )
    ( string_push_str out `"` )
    ( __mmdr_attr_s out `stroke` ( mmd_theme_var_str t `edge` lname `stroke` `#64748b` ) )
    ( __mmdr_attr_s out `stroke-width` ( mmd_theme_var_str t `edge` lname `stroke_width` `1.6` ) )
    ( __mmdr_attr_s out `stroke-dasharray` ( mmd_theme_var_str t `edge` lname `dash` `` ) )
    ( __mmdr_attr_s out `stroke-linejoin` `round` )
    ( string_push_str out ` />` )

    ( __mmdr_head out t lname . e head . pl x . pl y - . pl x . pp x - . pl y . pp y )
    ( __mmdr_head out t lname . e tail . p0 x . p0 y - . p0 x . p1 x - . p0 y . p1 y )

    // Label at the middle of the route: the middle bend when there is one,
    // otherwise the midpoint of the straight run.
    : ~ i lx / + . p0 x . pl x 2
    : ~ i ly / + . p0 y . pl y 2
    ? > n 2 {
        : MmdPt mid ( __mmdr_pt_at pts / n 2 )
        = lx . mid x
        = ly . mid y
    } {}
    ( __mmdr_edge_label out t ( string_data . e label ) lx ly ( mmd_theme_int t `canvas.font_size` 14 ) )
}

// ── The renderer ─────────────────────────────────────────────────────

@ mmd_render_svg MmdGraph g MmdLayout l MmdTheme t → String {
    : i font ( mmd_theme_int t `canvas.font_size` 14 )
    : i line_h ( mmd_theme_int t `layout.line_height` + font 5 )
    : i nn ( mmd_node_count g )
    : i ne ( mmd_edge_count g )

    : String out ( string_with_cap + 2048 * 320 + nn ne )
    ( string_push_str out `<svg xmlns="http://www.w3.org/2000/svg" role="img"` )
    ( __mmdr_attr_i out `width` . l width )
    ( __mmdr_attr_i out `height` . l height )
    ( string_push_str out ` viewBox="0 0 ` )
    ( string_push_int out . l width )
    ( string_push_str out ` ` )
    ( string_push_int out . l height )
    ( string_push_str out `">\n` )
    ( __mmdr_style out t )

    : i nw ( vec_len [String] . g warnings )
    ? > nw 0 {
        ( string_push_str out `<desc>` )
        : ~ i wi 0
        ~ < wi nw {
            ?? ( vec_get [String] . g warnings wi ) {
                T s → {
                    ? > wi 0 { ( string_push_str out `; ` ) } {}
                    ( __mmdr_escape out ( string_data s ) )
                }
                F _ → {}
            }
            = wi + wi 1
        }
        ( string_push_str out `</desc>\n` )
    } {}

    ( string_push_str out `<rect class="mmd-bg" x="0" y="0"` )
    ( __mmdr_attr_i out `width` . l width )
    ( __mmdr_attr_i out `height` . l height )
    ( __mmdr_attr_s out `fill` ( mmd_theme_str t `canvas.background` `#ffffff` ) )
    ( string_push_str out ` />\n` )

    // Edges first so nodes paint over the line ends.
    ( string_push_str out `<g class="mmd-edges">` )
    : ~ i k 0
    ~ < k ne {
        ?? ( vec_get [MmdEdge] . g edges k ) {
            T e → {
                : MmdBox a ( mmd_layout_box l . e from )
                : MmdBox b ( mmd_layout_box l . e to )
                : s lname ( mmd_line_name . e line )
                ( string_push_str out `<g class="mmd-edge mmd-l-` )
                ( string_push_str out lname )
                ( string_push_str out `">` )
                ? == . e from . e to {
                    ( __mmdr_self_loop out t e lname . g dir . a x . a y . a w . a h font )
                } {
                    : i acx + . a x / . a w 2
                    : i acy + . a y / . a h 2
                    : i bcx + . b x / . b w 2
                    : i bcy + . b y / . b h 2
                    : ~ i ashape MMD_SHAPE_RECT
                    : ~ i bshape MMD_SHAPE_RECT
                    ?? ( vec_get [MmdNode] . g nodes . e from ) {
                        T nd → { = ashape . nd shape }
                        F _ → {}
                    }
                    ?? ( vec_get [MmdNode] . g nodes . e to ) {
                        T nd → { = bshape . nd shape }
                        F _ → {}
                    }

                    // The polyline: source border, every bend the layout
                    // reserved a lane for, target border. A direct link is
                    // the two-point case of the same code.
                    : i nb ( mmd_layout_bends l k )
                    : ~ i fx bcx
                    : ~ i fy bcy
                    : ~ i tx acx
                    : ~ i ty acy
                    ? > nb 0 {
                        : MmdPt p0 ( mmd_layout_bend l k 0 )
                        : MmdPt pn ( mmd_layout_bend l k - nb 1 )
                        = fx . p0 x
                        = fy . p0 y
                        = tx . pn x
                        = ty . pn y
                    } {}
                    : MmdPt pa ( __mmdr_clip ashape acx acy . a w . a h - fx acx - fy acy )
                    : MmdPt pb ( __mmdr_clip bshape bcx bcy . b w . b h - tx bcx - ty bcy )

                    : ( Vec MmdPt ) pts ( vec_with_cap [MmdPt] + nb 2 )
                    ( vec_push [MmdPt] pts pa )
                    : ~ i bi 0
                    ~ < bi nb {
                        ( vec_push [MmdPt] pts ( mmd_layout_bend l k bi ) )
                        = bi + bi 1
                    }
                    ( vec_push [MmdPt] pts pb )
                    ( __mmdr_polyline out t e lname pts )
                    ( vec_free [MmdPt] pts )
                }
                ( string_push_str out `</g>` )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( string_push_str out `</g>\n` )

    ( string_push_str out `<g class="mmd-nodes">` )
    : ~ i i 0
    ~ < i nn {
        ?? ( vec_get [MmdNode] . g nodes i ) {
            T nd → {
                : MmdBox bx ( mmd_layout_box l i )
                : s nm ( mmd_shape_name . nd shape )
                ( string_push_str out `<g class="mmd-node mmd-s-` )
                ( string_push_str out nm )
                ( string_push_str out `" data-id="` )
                ( __mmdr_escape out ( string_data . nd id ) )
                ( string_push_str out `">` )
                ( __mmdr_node_shape out t . nd shape . bx x . bx y . bx w . bx h )
                ( __mmdr_text out ( string_data . nd label )
                + . bx x / . bx w 2
                + . bx y / . bx h 2
                line_h
                ( mmd_theme_var_str t `node` nm `text` `#0f172a` )
                `mmd-label` )
                ( string_push_str out `</g>` )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( string_push_str out `</g>\n</svg>\n` )
    ^ out
}
