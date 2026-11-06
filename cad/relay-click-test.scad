// Relay Everything click test: the floating-band button with no electronics.
// Three printed parts:
//   base - the inside wall and one polished edge, with six raised seats
//   cap  - the other polished edge; glue it onto the base after the band is in
//   band - the brushed centre band; it floats on the six buttons
// button = "dome": put a 3 mm metal snap dome on each seat.
// button = "tl3312": put an E-Switch TL3312 (3.7 x 3.7 x 0.35, the V1 switch) in each square pocket.
// Drop the band on, glue the cap on. Press anywhere on the band: one button should click.
// The band sits band_recess below the two edges, so a table or a steering wheel touches
// the edges first and only a fingertip in the middle clicks. Try pressing it flat on a table.
//
// scale_factor = 1 is the real ring. scale_factor = 2 is twice as big, easier to
// print and to see. The domes, travel and preload stay real size at any scale.
//
// Export each part:
//   openscad -o base.stl -D 'part="base"' relay-click-test.scad
//   openscad -o cap.stl  -D 'part="cap"'  relay-click-test.scad
//   openscad -o band.stl -D 'part="band"' relay-click-test.scad
// Add -D 'button="tl3312"' for the switch version.
// For a shop print at JLC3DP (walls over 0.8 mm, ±0.2 mm), use scale_factor = 2 and fit_gap = 0.25.

part          = "assembly"; // "base", "cap", "band", or "assembly" (view only)
button        = "dome";     // "dome" (3 mm snap dome) or "tl3312" (the V1 switch)
scale_factor  = 1;          // 1 = real size, 2 = twice the size
us_size       = 10;
fit_allowance = 0.20;       // mm on the inner diameter

// Ring shape, at scale_factor 1 (mm)
width         = 6.0;
thickness     = 2.2;
bevel         = 0.5;   // 45° chamfer on each outer edge
flange_width  = 0.8;   // width of each polished edge
inner_wall    = 0.6;   // inside wall; 0.6 prints well, the final ring aims at 0.25
band_wall     = 0.4;   // brushed band wall
comfort       = 0.15;  // comfort-fit curve on the inside

// Button parts, always real size (mm)
dome_count    = 6;     // one every 60°
dome_d        = 3.0;   // snap dome diameter; 4 mm domes also fit at scale 1
dome_h        = 0.30;  // snap dome height before it is pressed
sw_size       = 3.7;   // TL3312 body, square
sw_h          = 0.35;  // TL3312 height
tl            = button == "tl3312";
btn_d         = tl ? sw_size : dome_d;
btn_h         = tl ? sw_h : dome_h;
preload       = 0.03;  // how much the band presses the domes at rest; stops rattle
nub_d         = 1.2;   // nub under the band that presses the dome centre
nub_h         = 0.30;
fit_gap       = 0.10;  // gap between moving parts; use 0.25 for JLC3DP or PCBWay prints (±0.2 mm)
side_gap      = fit_gap;      // gap between the band and each edge
glue_gap      = fit_gap / 2;  // gap for glue between the cap and the base
seat_depth    = 0.10;  // shallow pocket that holds each dome in place
band_recess   = 0.20;  // band top below the edges, against bumps; real size at any scale

$fn = 240;

s       = scale_factor;
w       = width * s;
fw      = flange_width * s;
b       = bevel * s;
r_in    = ((11.63 + 0.8128 * us_size) / 2 + fit_allowance / 2) * s;
r_out   = r_in + thickness * s;
r_floor = r_in + inner_wall * s;       // top of the inside wall
r_top   = r_out - band_recess;         // top of the band
r_band  = r_top - band_wall * s;       // underside of the band
r_seat  = r_band - nub_h - btn_h + preload;  // top of each seat
band_hw = w / 2 - fw - side_gap;       // half width of the band

assert(r_seat > r_floor, "No room under the band: make inner_wall or band_wall thinner");

function r_inner(z) = r_in + comfort * s * pow(2 * z / w, 2);
function arc_deg(len, r) = len / r * 180 / PI;

steps = 40;

module base() {
    inner_curve = [for (i = [0 : steps])
        let (z = -w / 2 + w * i / steps) [r_inner(z), z]];
    rotate_extrude() union() {
        // inside wall, full width
        polygon(concat(inner_curve, [[r_floor, w / 2], [r_floor, -w / 2]]));
        // polished edge on the +z side
        polygon([[r_floor - 0.01, w / 2 - fw], [r_out, w / 2 - fw],
                 [r_out, w / 2 - b], [r_out - b, w / 2], [r_floor - 0.01, w / 2]]);
    }
    // seats, each with a shallow pocket for its button
    seat_len = btn_d + 1.0;
    seat_w   = min(btn_d + 0.6, w - 2 * fw - 0.1); // stay clear of the edges
    for (i = [0 : dome_count - 1]) {
        a = 360 / dome_count * i;
        difference() {
            rotate([0, 0, a - arc_deg(seat_len, r_floor) / 2])
                rotate_extrude(angle = arc_deg(seat_len, r_floor))
                    translate([r_floor - 0.01, -seat_w / 2])
                        square([r_seat - r_floor + 0.01, seat_w]);
            rotate([0, 0, a]) translate([r_seat, 0, 0])
                if (tl) cube([2 * seat_depth, sw_size + 0.2, sw_size + 0.2], center = true);
                else rotate([0, 90, 0]) cylinder(d = dome_d + 0.2, h = 2 * seat_depth, center = true);
        }
    }
}

module cap() {
    rotate_extrude()
        polygon([[r_floor + glue_gap, -w / 2], [r_out - b, -w / 2],
                 [r_out, -w / 2 + b], [r_out, -w / 2 + fw],
                 [r_floor + glue_gap, -w / 2 + fw]]);
}

module band() {
    rotate_extrude()
        translate([r_band, -band_hw]) square([r_top - r_band, 2 * band_hw]);
    for (i = [0 : dome_count - 1])
        rotate([0, 0, 360 / dome_count * i])
            translate([r_band - nub_h, 0, 0]) rotate([0, 90, 0])
                cylinder(d = nub_d, h = nub_h + 0.05, $fn = 48);
}

if (part == "base") base();
else if (part == "cap") cap();
else if (part == "band") band();
else {
    color("dimgray") base();
    color("dimgray") cap();
    color("silver") band();
}

assert(!tl || sw_size + 0.2 <= w - 2 * fw - 0.1, "The TL3312 is too wide for this band: use scale_factor 2");

echo(str("Relay Everything click test: ", button, ", scale ", s, ", US ", us_size,
         ", band ", band_recess, " mm below the edges",
         ", room under band ", r_band - r_floor, " mm, seat height ", r_seat - r_floor, " mm"));
