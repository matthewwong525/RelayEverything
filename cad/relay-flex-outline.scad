// Relay flexible board outline, laid flat, for KiCad (Edge.Cuts).
// The strip wraps once around the inside wall of the ring, outer face toward the band.
// Export: openscad -o relay-flex-outline-size10.dxf -D us_size=10 relay-flex-outline.scad
// Zones along the strip, measured from the top centre (0 mm), are in the plan (PLAN.md).

version       = "v1";  // "v1": 8 mm ring, board over a 1.5 mm cell; "v2": 6 mm ring
us_size       = 10;
fit_allowance = 0.20;
end_gap       = 1.0;   // gap where the two ends of the strip meet (palm side)

// v1 matches relay-v1-ring.scad: 0.5 mm printed wall + 1.5 mm cell under the board,
// width 8.0 mm minus two 0.5 mm walls and 0.1 mm clearance each side.
// v2: 0.25 mm cast wall, width 6.0 mm minus two 0.8 mm edges and 0.2 mm clearance.
under_board   = version == "v1" ? 0.50 + 1.5 : 0.25;
strip_width   = version == "v1" ? 6.8 : 4.0;

r_in   = (11.63 + 0.8128 * us_size) / 2 + fit_allowance / 2;
r_flex = r_in + under_board;
length = 2 * PI * r_flex - end_gap;

translate([-length / 2, -strip_width / 2]) square([length, strip_width]);

echo(str("Relay flex strip ", version, ": US ", us_size, ", length ", length, " mm, width ", strip_width,
         " mm, switch spacing ", 2 * PI * r_flex / 6, " mm"));
