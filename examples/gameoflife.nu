// gameoflife.nu — Conway's Life, classic two-color, big and clear

& libc   @ rand → i

& canvas @ canvas_open         i w i h → * i
& canvas @ canvas_present      → v
& canvas @ canvas_sleep        i ms → v
& canvas @ canvas_should_close → i
& canvas @ canvas_close        → v

: i CELL  8         // pixels per cell side
: i GW    80        // grid width in cells
: i GH    45        // grid height in cells
: i W     640       // GW * CELL
: i H     360       // GH * CELL
: i FPS   15

@ main → i {
  : i ncells   * GW GH
  : i frame_ms / 1000 FPS

  : * i grid_a # * i ( malloc * ncells 8 )
  : * i grid_b # * i ( malloc * ncells 8 )

  : ~ i ix 0
  ~ < ix ncells {
    = . grid_a ix 0
    = . grid_b ix 0
    = ix + ix 1
  }

  // Seed: Gosper Glider Gun + three free gliders
  : [i seed [ i |
    29 5
    27 6   29 6
    17 7   18 7   25 7   26 7   39 7   40 7
    16 8   20 8   25 8   26 8   39 8   40 8
    5 9    6 9    15 9   21 9   25 9   26 9
    5 10   6 10   15 10  19 10  21 10  22 10  27 10  29 10
    15 11  21 11  29 11
    16 12  20 12
    17 13  18 13
    46 25  47 26  45 27  46 27  47 27
    61 35  62 36  60 37  61 37  62 37
    11 30  12 31  10 32  11 32  12 32
  ]
  : i seed_n 102

  : ~ i si 0
  ~ < si seed_n {
    : i si1 + si 1
    : i sx . seed si
    : i sy . seed si1
    : i sidx + * sy GW sx
    = . grid_a sidx 1
    = si + si 2
  }

  : i BLACK 4278190080
  : i WHITE 4294967295

  : * i fb ( canvas_open W H )
  : ~ i parity 0

  ~ == 0 ( canvas_should_close ) {
    : ~ i cy 0
    ~ < cy GH {
      : ~ i cx 0
      ~ < cx GW {
        : i idx + * cy GW cx
        : i cur ? == parity 0 . grid_a idx . grid_b idx

        : ~ i count 0
        : ~ i dy -1
        ~ <= dy 1 {
          : ~ i dx -1
          ~ <= dx 1 {
            : b is_self & == dx 0 == dy 0
            ? is_self {} {
              : i ny0 + cy dy
              : i nx0 + cx dx
              : i ny ? < ny0 0 + ny0 GH ? >= ny0 GH - ny0 GH ny0
              : i nx ? < nx0 0 + nx0 GW ? >= nx0 GW - nx0 GW nx0
              : i nidx + * ny GW nx
              : i nv ? == parity 0 . grid_a nidx . grid_b nidx
              = count + count nv
            }
            = dx + dx 1
          }
          = dy + dy 1
        }

        : b survives & == cur 1 & >= count 2 <= count 3
        : b births   & == cur 0 == count 3
        : i alive_next ? | survives births 1 0

        ? == parity 0 {
          = . grid_b idx alive_next
        } {
          = . grid_a idx alive_next
        }

        // Paint the CELL × CELL block, no trail
        : i color ? == alive_next 1 WHITE BLACK
        : i px0 * cx CELL
        : i py0 * cy CELL
        : ~ i py 0
        ~ < py CELL {
          : ~ i px 0
          ~ < px CELL {
            : i fy + py0 py
            : i fx + px0 px
            : i fidx + * fy W fx
            = . fb fidx color
            = px + px 1
          }
          = py + py 1
        }

        = cx + cx 1
      }
      = cy + cy 1
    }

    = parity ? == parity 0 1 0
    ( canvas_present )
    ( canvas_sleep frame_ms )
  }

  ( canvas_close )
  ^ 0
}