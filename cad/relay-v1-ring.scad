// Relay V1 ring: the first ring with real parts inside.
// Ready-made curved cell on the palm side, flexible board around the ring,
// six 0.35 mm tact switches (E-Switch TL3312) under a floating band.
//
// Printed parts:
//   base - inside wall and one polished edge
//   cap  - the other polished edge; glue it on after the cell, board and band are in
//   band - the floating centre band; it rests on the six switches
// part = "assembly" also shows the cell, board and switches (grey), for a fit check only.
//
// Export:
//   openscad -o v1-base.stl -D 'part="base"' relay-v1-ring.scad
//   openscad -o v1-cap.stl  -D 'part="cap"'  relay-v1-ring.scad
//   openscad -o v1-band.stl -D 'part="band"' relay-v1-ring.scad

part          = "assembly";
cell          = "ufine";  // "ufine" (16 mAh, 25 x 6.9 x 1.5) or "grepow" (15 mAh, 21.8 x 6.5 x 1.7)
us_size       = 10;
fit_allowance = 0.20;

// Cell sizes (mm) from the maker pages
cell_len = cell == "grepow" ? 21.8 : 25.0;
cell_w   = cell == "grepow" ? 6.5  : 6.9;
cell_t   = cell == "grepow" ? 1.7  : 1.5;

// Ring shape (mm)
width        = cell == "grepow" ? 7.5 : 8.0; // the cell sets the width
side_wall    = 0.50;  // edge wall beside the cell; 0.5 is near the print limit
edge_top     = 0.80;  // polished edge width beside the band
bevel        = 0.50;
inner_wall   = 0.50;  // printed; a cast inside wall can be 0.25 later
band_wall    = 0.40;
edge_rise    = 0.20;  // edges stand above the band, so a bump hits them, not the band
comfort      = 0.15;

// Board and switches (mm)
board_t      = 0.20;  // 4-layer flex with stiffener
switch_h     = 0.35;  // TL3312
switch_w     = 3.7;
switch_count = 6;
preload      = 0.02;  // band presses the switches a little, to stop rattle
fit_gap      = 0.10;  // use 0.25 for shop prints

$fn = 240;

r_in    = (11.63 + 0.8128 * us_size) / 2 + fit_allowance / 2;
r_floor = r_in + inner_wall;
r_board = r_floor + cell_t;            // underside of the board
r_top   = r_board + board_t;           // top of the board
r_band  = r_top + switch_h - preload;  // underside of the band
r_out   = r_band + band_wall;           // top of the band
r_edge  = r_out + edge_rise;            // top of each edge
w       = width;
band_hw = w / 2 - edge_top - fit_gap;
cav_hw  = w / 2 - side_wall;           // half width of the space for the cell and board

assert(cell_w / 2 <= cav_hw - 0.05, "The cell is too wide for this ring: make it wider");

function r_inner(z) = r_in + comfort * pow(2 * z / w, 2);
function arc_deg(len, r) = len / r * 180 / PI;

steps = 40;

// One polished edge, on the +z side. Thin beside the cell, wide beside the band.
module edge_profile(r_start) {
    polygon([[r_start, cav_hw], [r_top, cav_hw], [r_top, w / 2 - edge_top],
             [r_edge, w / 2 - edge_top], [r_edge, w / 2 - bevel],
             [r_edge - bevel, w / 2], [r_start, w / 2]]);
}

module base() {
    inner_curve = [for (i = [0 : steps])
        let (z = -w / 2 + w * i / steps) [r_inner(z), z]];
    rotate_extrude() union() {
        polygon(concat(inner_curve, [[r_floor, w / 2], [r_floor, -w / 2]]));
        edge_profile(r_floor - 0.01);
    }
}

module cap() {
    rotate_extrude() mirror([0, 1]) edge_profile(r_floor + fit_gap / 2);
}

module band() {
    rotate_extrude() translate([r_band, -band_hw]) square([r_out - r_band, 2 * band_hw]);
}

module fit_check_parts() {
    // cell on the palm side (180°)
    color("orange") rotate([0, 0, 180 - arc_deg(cell_len, r_floor) / 2])
        rotate_extrude(angle = arc_deg(cell_len, r_floor))
            translate([r_floor, -cell_w / 2]) square([cell_t, cell_w]);
    // board, all the way around
    color("green") rotate_extrude()
        translate([r_board, -(cav_hw - 0.1)]) square([board_t, 2 * (cav_hw - 0.1)]);
    // switches, every 60°, starting 30° from the top
    for (i = [0 : switch_count - 1])
        color("black") rotate([0, 0, 30 + 360 / switch_count * i])
            translate([r_top + switch_h / 2, 0, 0])
                cube([switch_h, switch_w, switch_w], center = true);
}

if (part == "base") base();
else if (part == "cap") cap();
else if (part == "band") band();
else {
    color("dimgray") base();
    color("dimgray") cap();
    color("silver", 0.6) band();
    fit_check_parts();
}

echo(str("Relay V1: cell ", cell, ", US ", us_size, ", width ", w, " mm, thickness ",
         r_edge - r_in, " mm at the edges, ", r_out - r_in, " mm at the band, inner diameter ",
         2 * r_in, " mm"));
