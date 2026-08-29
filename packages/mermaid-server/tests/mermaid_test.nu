// mermaid_test.nu — unit tests for the parser, the templates, the layout
// and the SVG renderer. Prints one ok/FAIL line per check and exits
// non-zero if anything failed. Run from the package directory, or via
// tests/mermaid_test.sh.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/service.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` )
        ( nurl_println label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` )
        ( nurl_println label )
        = g_fail + g_fail 1
    }
}

@ node_shape MmdGraph g i idx → i {
    ?? ( vec_get [MmdNode] . g nodes idx ) {
        T nd → ^ . nd shape
        F _ → {}
    }
    ^ - 0 1
}

@ node_label_is MmdGraph g i idx s want → b {
    ?? ( vec_get [MmdNode] . g nodes idx ) {
        T nd → ^ != 0 ( nurl_str_eq ( string_data . nd label ) want )
        F _ → {}
    }
    ^ F
}

@ edge_at MmdGraph g i idx → MmdEdge {
    ?? ( vec_get [MmdEdge] . g edges idx ) {
        T e → ^ e
        F _ → {}
    }
    ^ @ MmdEdge { 0 0 ( string_new ) 0 0 0 }
}

// ── Parser ───────────────────────────────────────────────────────────

@ test_parse_basic → v {
    : MmdParseResult r ( mmd_parse `graph TD\n  A[Start] --> B{Ready?}\n  B -->|yes| C([Done])\n` )
    ( check . r ok `parse: a three-node flowchart` )
    : MmdGraph g . r graph
    ( check == . g dir MMD_DIR_TD `parse: direction TD` )
    ( check == ( mmd_node_count g ) 3 `parse: three nodes` )
    ( check == ( mmd_edge_count g ) 2 `parse: two edges` )
    ( check ( node_label_is g 0 `Start` ) `parse: node label from [..]` )
    ( check == ( node_shape g 1 ) MMD_SHAPE_DIAMOND `parse: {..} is a diamond` )
    ( check == ( node_shape g 2 ) MMD_SHAPE_STADIUM `parse: ([..]) is a stadium` )
    : MmdEdge e1 ( edge_at g 1 )
    ( check != 0 ( nurl_str_eq ( string_data . e1 label ) `yes` ) `parse: pipe edge label` )
    ( check == . e1 head MMD_ARROW_POINT `parse: --> is an arrow head` )
    ( mmd_parse_result_free r )
}

@ test_parse_shapes → v {
    : MmdParseResult r ( mmd_parse `flowchart LR\n  a((C)) --> b[[S]] --> c[(D)] --> d{{H}} --> e[/P/] --> f[/T\\] --> g>F]\n` )
    ( check . r ok `parse: every shape spelling` )
    : MmdGraph g . r graph
    ( check == . g dir MMD_DIR_LR `parse: direction LR` )
    ( check == ( node_shape g 0 ) MMD_SHAPE_CIRCLE `parse: ((..)) is a circle` )
    ( check == ( node_shape g 1 ) MMD_SHAPE_SUBROUTINE `parse: [[..]] is a subroutine` )
    ( check == ( node_shape g 2 ) MMD_SHAPE_CYLINDER `parse: [(..)] is a cylinder` )
    ( check == ( node_shape g 3 ) MMD_SHAPE_HEXAGON `parse: {{..}} is a hexagon` )
    ( check == ( node_shape g 4 ) MMD_SHAPE_PARALLELOGRAM `parse: [/../] is a parallelogram` )
    ( check == ( node_shape g 5 ) MMD_SHAPE_TRAPEZOID `parse: [/..\\] is a trapezoid` )
    ( check == ( node_shape g 6 ) MMD_SHAPE_FLAG `parse: >..] is a flag` )
    ( mmd_parse_result_free r )
}

@ test_parse_links → v {
    : MmdParseResult r ( mmd_parse `graph TD\n  A --- B\n  A -.-> C\n  A ==> D\n  A --o E\n  A --x F\n  A <--> G\n  A -- mid --> H\n  A -. dot .-> I\n` )
    ( check . r ok `parse: every link spelling` )
    : MmdGraph g . r graph
    ( check == ( mmd_edge_count g ) 8 `parse: eight links` )
    ( check == . ( edge_at g 0 ) head MMD_ARROW_NONE `parse: --- has no head` )
    ( check == . ( edge_at g 1 ) line MMD_LINE_DOTTED `parse: -.-> is dotted` )
    ( check == . ( edge_at g 2 ) line MMD_LINE_THICK `parse: ==> is thick` )
    ( check == . ( edge_at g 3 ) head MMD_ARROW_CIRCLE `parse: --o is a circle head` )
    ( check == . ( edge_at g 4 ) head MMD_ARROW_CROSS `parse: --x is a cross head` )
    ( check == . ( edge_at g 5 ) tail MMD_ARROW_POINT `parse: <--> has a tail head` )
    : MmdEdge e6 ( edge_at g 6 )
    ( check != 0 ( nurl_str_eq ( string_data . e6 label ) `mid` ) `parse: -- text --> label` )
    : MmdEdge e7 ( edge_at g 7 )
    ( check != 0 ( nurl_str_eq ( string_data . e7 label ) `dot` ) `parse: -. text .-> label` )
    ( check == . e7 line MMD_LINE_DOTTED `parse: -. text .-> stays dotted` )
    ( mmd_parse_result_free r )
}

// `A --- B --- C` must not read `B` as an inline link label: only a
// two-character opening run starts one.
@ test_parse_chain_not_label → v {
    : MmdParseResult r ( mmd_parse `graph TD\n  A --- B --- C\n` )
    ( check . r ok `parse: a chain of unlabelled links` )
    : MmdGraph g . r graph
    ( check == ( mmd_node_count g ) 3 `parse: chain keeps three nodes` )
    ( check == ( mmd_edge_count g ) 2 `parse: chain makes two links` )
    ( check == ( string_len . ( edge_at g 0 ) label ) 0 `parse: --- link carries no label` )
    ( mmd_parse_result_free r )
}

@ test_parse_groups_and_breaks → v {
    : MmdParseResult r ( mmd_parse `graph TD\n  A & B --> C & D\n  E[one<br/>two] --> A\n` )
    ( check . r ok `parse: & groups and <br/>` )
    : MmdGraph g . r graph
    ( check == ( mmd_edge_count g ) 5 `parse: a 2x2 group is four links` )
    ( check ( node_label_is g 4 `one\ntwo` ) `parse: <br/> becomes a newline` )
    ( mmd_parse_result_free r )
}

@ test_parse_errors → v {
    : MmdParseResult r1 ( mmd_parse `sequenceDiagram\n  A ->> B: hi\n` )
    ( check ! . r1 ok `parse: a non-flowchart diagram is rejected` )
    ( check == . r1 line 1 `parse: rejection points at line 1` )
    ( mmd_parse_result_free r1 )

    : MmdParseResult r2 ( mmd_parse `graph TD\n  A[unterminated\n` )
    ( check ! . r2 ok `parse: an unterminated shape is rejected` )
    ( check == . r2 line 2 `parse: unterminated shape points at line 2` )
    ( mmd_parse_result_free r2 )

    : MmdParseResult r3 ( mmd_parse `graph TD\n  subgraph one\n  A --> B\n  end\n` )
    ( check ! . r3 ok `parse: subgraph is rejected, not silently dropped` )
    ( mmd_parse_result_free r3 )

    : MmdParseResult r4 ( mmd_parse `graph TD\n  classDef big fill:#fff\n  A --> B\n` )
    ( check . r4 ok `parse: a styling statement does not fail the parse` )
    ( check == ( vec_len [String] . . r4 graph warnings ) 1 `parse: styling statement warns` )
    ( mmd_parse_result_free r4 )
}

// ── Templates ────────────────────────────────────────────────────────

@ test_templates → v {
    : MmdTemplatesRes r ( mmd_templates_load MMD_TSRC_DIR `.templates` )
    ( check . r ok `templates: the shipped directory loads` )
    : MmdTemplateSet ts . r set
    ( check >= ( mmd_templates_count ts ) 3 `templates: three or more templates` )
    ( check >= ( mmd_templates_find ts `dark` ) 0 `templates: 'dark' resolves` )
    ( check == ( mmd_templates_find ts `nope` ) - 0 1 `templates: an unknown name does not` )
    ( check != 0 ( nurl_str_eq ( string_data . ts default_name ) `default` )
    `templates: default = true picks the default` )
    ( check >= ( mmd_templates_find ts `` ) 0 `templates: an empty name means the default` )

    : MmdTheme th ( mmd_templates_theme ts ( mmd_templates_find ts `default` ) )
    ( check != 0 ( nurl_str_eq ( mmd_theme_str th `canvas.background` `` ) `#ffffff` )
    `templates: a nested key flattens to a dotted name` )
    ( check == ( mmd_theme_int th `layout.rank_gap` 0 ) 74 `templates: an integer key parses` )
    ( check != 0 ( nurl_str_eq ( mmd_theme_var_str th `node` `diamond` `fill` `x` ) `#fef3c7` )
    `templates: a per-shape override wins` )
    ( check != 0 ( nurl_str_eq ( mmd_theme_var_str th `node` `rect` `fill` `x` ) `#eef2ff` )
    `templates: a shape without an override falls back` )
    ( check != 0 ( nurl_str_eq ( mmd_theme_var_str th `node` `rect` `nosuch` `fallback` ) `fallback` )
    `templates: an unknown key reaches the default` )
    ( check != 0 ( nurl_str_eq ( mmd_theme_str th `node.stroke_width` `` ) `1.6` )
    `templates: a float keeps its exact spelling` )
    ( mmd_templates_free ts )
    ( string_free . r message )
}

// ── Layout ───────────────────────────────────────────────────────────

@ test_layout → v {
    : MmdTemplatesRes tr ( mmd_templates_load MMD_TSRC_DIR `.templates` )
    : MmdTemplateSet ts . tr set
    : MmdTheme th ( mmd_templates_theme ts ( mmd_templates_find ts `default` ) )

    : MmdParseResult r ( mmd_parse `graph TD\n  A --> B --> C --> D\n  A --> D\n` )
    : MmdGraph g . r graph
    : MmdLayout l ( mmd_layout g th )
    ( check == . l ranks 4 `layout: a four-node chain is four layers` )
    : MmdBox a ( mmd_layout_box l 0 )
    : MmdBox d ( mmd_layout_box l 3 )
    ( check < . a y . d y `layout: TD puts the first layer above the last` )
    ( check > . a w 0 `layout: a node has a positive width` )
    ( check <= + . d y . d h . l height `layout: the canvas contains the last node` )
    // A --> D crosses two layer boundaries, so it must be routed.
    ( check == ( mmd_layout_bends l 3 ) 2 `layout: a long link gets one bend per crossed layer` )
    ( check == ( mmd_layout_bends l 0 ) 0 `layout: a neighbouring link is drawn straight` )
    ( mmd_layout_free l )
    ( mmd_parse_result_free r )

    // A cycle must still terminate and rank.
    : MmdParseResult rc ( mmd_parse `graph LR\n  A --> B --> C --> A\n` )
    : MmdLayout lc ( mmd_layout . rc graph th )
    ( check == . lc ranks 3 `layout: a cycle ranks by its back edge` )
    ( check > . lc width . lc height `layout: LR is wider than it is tall` )
    ( mmd_layout_free lc )
    ( mmd_parse_result_free rc )

    ( mmd_templates_free ts )
    ( string_free . tr message )
}

// ── Renderer ─────────────────────────────────────────────────────────

@ test_render → v {
    : MmdTemplatesRes tr ( mmd_templates_load MMD_TSRC_DIR `.templates` )
    ( mmd_state_init . tr set )
    ( string_free . tr message )

    : MmdRenderRes r ( mmd_render_source `graph TD\n  A["a & b <c>"] --> B{Q}\n  B -.-> A\n` `` )
    ( check . r ok `render: a diagram renders` )
    : String svg . r svg
    ( check ( string_starts_with svg `<svg xmlns=` ) `render: output is an SVG document` )
    ( check ( string_contains svg `viewBox=` ) `render: it carries a viewBox` )
    ( check ( string_contains svg `a &amp; b &lt;c&gt;` ) `render: label text is XML-escaped` )
    ( check ( string_contains svg `stroke-dasharray="5 5"` ) `render: a dotted link is dashed` )
    ( check ( string_contains svg `class="mmd-node mmd-s-diamond"` ) `render: shapes are classed` )
    ( check ( string_contains svg `data-id="A"` ) `render: nodes keep their mermaid id` )
    ( check > . r width 0 `render: reported width is positive` )
    ( check == . r nodes 2 `render: reports the node count` )
    ( mmd_render_res_free r )

    : MmdRenderRes rd ( mmd_render_source `graph TD\n  A --> B\n` `dark` )
    ( check . rd ok `render: a named template renders` )
    ( check ( string_contains . rd svg `#0b1120` ) `render: the named template's colours are used` )
    ( mmd_render_res_free rd )

    : MmdRenderRes ru ( mmd_render_source `graph TD\n  A --> B\n` `nope` )
    ( check ! . ru ok `render: an unknown template is an error` )
    ( mmd_render_res_free ru )

    : MmdRenderRes re ( mmd_render_source `graph TD\n  A[oops\n` `` )
    ( check ! . re ok `render: a parse error surfaces` )
    ( check == . re line 2 `render: the parse error keeps its line` )
    ( mmd_render_res_free re )

    // A self-link and a lone node must both survive the pipeline.
    : MmdRenderRes rs ( mmd_render_source `graph LR\n  A --> A\n  B\n` `` )
    ( check . rs ok `render: a self-link and a lone node render` )
    ( mmd_render_res_free rs )

    ( mmd_state_free )
}

// ── MCP ──────────────────────────────────────────────────────────────

@ json_text_of Json result → s {
    ?? ( json_obj_get result `content` ) {
        T arr → {
            ?? ( json_arr_get arr 0 ) {
                T first → {
                    ?? ( json_obj_get first `text` ) {
                        T t → ^ ( json_str_data t )
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ ``
}

@ test_mcp → v {
    : MmdTemplatesRes tr ( mmd_templates_load MMD_TSRC_DIR `.templates` )
    ( mmd_state_init . tr set )
    ( string_free . tr message )

    : ( Vec Json ) tools ( mmd_tools_list )
    ( check == ( vec_len [Json] tools ) 3 `mcp: three tools are advertised` )
    ( vec_free_with [Json] tools \ Json j → v { ( json_free j ) } )

    : Json args ( json_obj_new )
    ( json_obj_set args `source` ( json_str_lit `graph TD\n A --> B\n` ) )
    : Json res ( mmd_dispatch_tool `mermaid_render` args )
    ( check ! ( json_as_bool
    ?? ( json_obj_get res `isError` ) { T v → v F _ → ( json_bool F ) } )
    `mcp: mermaid_render succeeds` )
    ( check != 0 ( nurl_str_starts ( json_text_of res ) `<svg` ) `mcp: mermaid_render returns SVG` )
    ( json_free res )

    : Json vres ( mmd_dispatch_tool `mermaid_validate` args )
    ( check != 0 ( nurl_str_starts ( json_text_of vres ) `ok: 2 nodes` ) `mcp: mermaid_validate counts nodes` )
    ( json_free vres )
    ( json_free args )

    : Json empty ( json_obj_new )
    : Json tres ( mmd_dispatch_tool `mermaid_templates` empty )
    : String tlist ( string_from ( json_text_of tres ) )
    ( check ( string_contains tlist `dark` ) `mcp: mermaid_templates lists them` )
    ( string_free tlist )
    ( json_free tres )

    : Json ures ( mmd_dispatch_tool `no_such_tool` empty )
    ( check ( json_as_bool
    ?? ( json_obj_get ures `isError` ) { T v → v F _ → ( json_bool F ) } )
    `mcp: an unknown tool is an error` )
    ( json_free ures )
    ( json_free empty )

    ( mmd_state_free )
}

@ main → i {
    ( test_parse_basic )
    ( test_parse_shapes )
    ( test_parse_links )
    ( test_parse_chain_not_label )
    ( test_parse_groups_and_breaks )
    ( test_parse_errors )
    ( test_templates )
    ( test_layout )
    ( test_render )
    ( test_mcp )
    : String sum ( string_with_cap 48 )
    ( string_push_int sum g_pass )
    ( string_push_str sum ` passed, ` )
    ( string_push_int sum g_fail )
    ( string_push_str sum ` failed` )
    ( nurl_println ( string_data sum ) )
    ( string_free sum )
    ^ ? > g_fail 0 1 0
}
