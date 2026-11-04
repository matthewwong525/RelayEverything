# Relay 3D files

Open the .scad files in OpenSCAD (free, openscad.org), change the values at the top, then Render (F6) and Export STL.

- relay-wear-test.scad: plain ring in the final shape (6 mm wide, 2.2 mm thick, US size input). Print it in two resins and wear it.
- relay-click-test.scad: the floating-band button (base, cap, band). `button` picks 3 mm snap domes or TL3312 switches for the six seats. The band sits 0.2 mm below the edges (`band_recess`), against bumps. Drop the band on, glue the cap on.
- relay-v1-ring.scad: the V1 ring (8.0 x 2.93 mm) with space for the 16 mAh Ufine cell, the board and six TL3312 switches. part="assembly" shows the parts inside.
- relay-flex-outline.scad: the board outline laid flat, for KiCad.

Ready files in stl/ (US size 10):
- relay-wear-test-size10.stl: the final 6 x 2.2 mm shape
- relay-wear-test-v1-8x2.9-size10.stl: the V1 size, to feel it before the real V1
- v1-base.stl, v1-cap.stl, v1-band.stl: the V1 ring shell (home printer; the 0.4-0.5 mm walls are under JLC's 0.8 mm limit)
- relay-flex-outline-v1-size10.dxf: V1 board edge, 74.3 x 6.8 mm
- click-test-2x-jlc-{base,cap,band}.stl: twice the size, gaps 0.25 mm, for JLC3DP or PCBWay; holds 3 mm snap domes
- click-test-2x-jlc-tl3312-*.stl: the same, with square pockets for the TL3312 switches of V1
- click-test-1x-home-*.stl: real size, gaps 0.1 mm, for a home resin printer (walls are below JLC's 0.8 mm limit)
