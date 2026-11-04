// Relay wear test: a plain ring in the final Relay shape, with no electronics.
// Print it, wear it for a few days, and check size, feel and comfort.
// Shape: flat top, polished-style 45° bevels at both edges, comfort-fit inside.
//
// Change the values below, then Render (F6) and Export as STL.
// Command line: openscad -o relay-wear-test-size10.stl -D us_size=10 relay-wear-test.scad

us_size        = 10;     // US ring size
fit_allowance  = 0.20;  // mm added to the inner diameter; a wide band fits tighter
width          = 6.0;   // mm, along the finger
thickness      = 2.2;   // mm, from skin to outside
bevel          = 0.5;   // mm, 45° chamfer on each outer edge
comfort        = 0.30;  // mm, how far the inside edges curve away from the finger

$fn = 240;

// US size to inner diameter (standard chart: 11.63 mm + 0.8128 mm per size).
function inner_diameter(size) = 11.63 + 0.8128 * size;

r_in  = inner_diameter(us_size) / 2 + fit_allowance / 2;
r_out = r_in + thickness;

// Comfort fit: the inside is closest to the finger at the centre line.
function r_inner(z) = r_in + comfort * pow(2 * z / width, 2);

steps = 40;
inner_curve = [for (i = [0 : steps])
    let (z = -width / 2 + width * i / steps) [r_inner(z), z]];

outer_edge = [
    [r_out - bevel,  width / 2],
    [r_out,          width / 2 - bevel],
    [r_out,         -width / 2 + bevel],
    [r_out - bevel, -width / 2],
];

rotate_extrude() polygon(concat(inner_curve, outer_edge));

echo(str("Relay wear test: US ", us_size, ", inner diameter ",
         2 * r_in, " mm, outer diameter ", 2 * r_out, " mm"));
