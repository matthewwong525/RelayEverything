# Relay Everything ring board plan (draft 1, 2026-11-04)

The Relay Everything ring is a 3D-printed resin voice-note ring with a centre band that clicks anywhere you press it. This plan covers the board, the parts and the build order for **V1** (US size 10). Sizes marked *est.* are estimates; confirm each one against its datasheet before layout.

| Version | Width | Thickness | Battery | Life at 5 min of notes a day (est.) |
|---|---|---|---|---|
| **V1 (building now)** | 8.0 mm | 2.93 mm at the band, 3.13 at the edges (Pebble: 2.95) | Ready-made Ufine 156825, 16 mAh, 25 × 6.9 × 1.5 | about 6–8 weeks per charge |
| V1 with Grepow GRP170722 | 7.5 mm (side walls 0.45) | 3.13 mm | 15 mAh, 21.8 × 6.5 × 1.7 | about 6–7 weeks |
| V2 (later) | 6.0 mm | about 2.2 mm | Custom cell, cast inside wall | not planned now |

## How V1 is stacked (radial, finger to outside)

| Layer | mm |
|---|---|
| Printed resin inside wall | 0.50 |
| Cell layer: the cell on the palm side; at the top, the parts hang under the board (mic 0.98 is the tallest) | 1.50 |
| Flexible board (4-layer, stiffener under each switch) | 0.20 *est.* |
| Tact switch (outer face, the only outer part) | 0.35 |
| Band (rests on the switch tops, 0.02 preload) | 0.40 |
| **Total at the band** | **2.93** |
| Edges stand above the band (against bumps) | 0.20 |
| **Total at the edges** | **3.13** |

Rule: **only the six switches sit on the outer face.** Any other part there would block the band's travel. All other parts face the finger. The 3D model is `cad/relay-v1-ring.scad`; set `cell = "grepow"` for the 7.5 mm version.

## Against bumps

The whole band clicks, so a bump could start a note (Carol, 2026-11-04). V1 has no light or buzzer, so three rules stop it, with no new parts:

1. **Hold to record.** The ring records only while you hold the band, like a walkie-talkie. It drops a press shorter than 0.5 s.
2. **No speech, no note.** The phone deletes a note with no speech in it.
3. **Raised edges.** The two edges stand 0.20 mm above the band (`edge_rise` in `cad/relay-v1-ring.scad`, `band_recess` in the click test). A table or a steering wheel touches the edges first; only a fingertip in the middle clicks. The click test checks the height: try 0.1 if 0.2 is hard to press.

## The board: one strip around the ring

- Outline: `cad/relay-flex-outline.scad` (`version = "v1"`). For US size 10 it is **74.3 × 6.8 mm**. The ends meet at the palm with a 1 mm gap.
- Six switches, 12.5 mm apart, at ±6.3, ±18.8 and ±31.3 mm from the top centre. Each has a 0.15–0.2 mm polyimide stiffener behind it.
- Zones, from the top centre:

| Zone (mm from top centre) | What is there |
|---|---|
| −12 to +12 | Chip, crystal, power chip and its inductor, mic, antenna and matching parts, programming pads |
| ±18 to ±22 | Two charging contacts: 1 mm gold-plated pins soldered under the board, flush with the inside wall and sealed in it |
| ±24.6 to ±37.1 (palm) | The cell, under the strip |

## Parts

| Job | Part | Size (mm) | Notes |
|---|---|---|---|
| Chip | Nordic nRF54L15, WLCSP | 2.4 × 2.2 × about 0.4 | Has Bluetooth, a digital mic input and 1.5 MB of memory (about 8 min of compressed voice). The Ezurio BL54L15µ module is too tall (1.75 mm). |
| Crystal | 32 MHz, 1612 size | 1.6 × 1.2 × 0.35 *est.* | Needed for Bluetooth. No 32 kHz crystal: use the chip's internal clock. |
| Mic | TDK T5837 (bottom port) | 3.5 × 2.65 × 0.98 | The T3902 is end-of-life. **Power the mic from a chip pin:** it uses about 9 µA even in sleep, more than the rest of the ring. The sound hole goes through the board, under a waterproof acoustic mesh. Sound reaches it through the band seam. |
| Charger | TI **BQ25101** (the BQ25100 has no charge-status pin) | 0.9 × 1.6, 0.4 mm ball pitch | Charge current set by one resistor: 13.7 kΩ gives 9.9 mA (about 0.6C) for the 16 mAh cell. Leakage under 75 nA. The Nordic nPM1100 is ruled out: its lowest charge current is 20 mA, more than this cell can take. |
| Regulator | Low-power LDO at 1.8 V (for example TI TPS7A02) | about 1 × 1 *est.* | Feeds the chip and the mic. Pick one with a rest current under 0.1 µA. |
| Battery protection | TI BQ29700 and a tiny dual N-FET (CSD83325L, pads to confirm) | 1.5 × 1.5 and 1.35 × 1.35 | The ready-made Ufine cell has no protection of its own. **It uses 4 µA**, more than the rest of the ring asleep: life falls to about 5–6 weeks. Look for a lower-current protection chip. |
| Battery | Ufine 156825, 16 mAh | 25 × 6.9 × 1.5 | Sets the ring width (8.0 mm). One cell is enough; a second cell on the other side would give about 3–4 months, but take board space. |
| Button | 6 × E-Switch TL3312 (160 gf), all on one input | 3.7 × 3.7 × 0.35 | DigiKey sells them one at a time. Any press wakes the chip. |
| Antenna | Small 2.4 GHz chip antenna, or a trace loop along the strip | about 1.6 × 0.8 *est.* | **Biggest unknown.** Needs a matching network and tuning on the real ring. |
| Charging | 2 gold-plated pins, 1 mm | 1 × 2 | Flush with the inside wall. The clip touches them. The charge chip takes power only in, so sweat cannot drain the cell. |
| Programming | 4 pads: power, ground, SWDIO, SWCLK | 0.8 each | You load code through the nRF54L15 DK's debug output, before you seal the ring |

## Power budget (est.)

| State | Current | Note |
|---|---|---|
| Asleep, waiting for a press | about 1–2 µA | Chip asleep, mic off, charger and regulator at rest |
| Recording | about 3 mA | Mic, digital mic input, compression |
| Sending to phone | about 5 mA for seconds | Only after a recording |

16 mAh (V1): about 6–8 weeks per charge at 5 min of notes a day, about 3 months at 2–3 min. A lithium cell keeps most of its capacity for about 300–500 charges, so at one charge a month it ages by time first: plan on about 2–3 years.

## Build order

1. **Click test and wear test** (3D files in `cad/`). Confirm the size, the feel, the click with TL3312 switches, and that the raised edges stop a flat press.
2. **Code on the nRF54L15 DK**, at the same time as the board design:
   - Ring: hold to record, drop a press under 0.5 s, compress, store, then signal the phone.
   - iPhone app: wakes in the background, pulls the audio, deletes a note with no speech, posts it to WongOS `/api/ring` in the Pebble webhook format (multipart audio and recordedAt). The format is in coredevices/mobileapp `INDEX_WEBHOOK_API.md`.
3. **Schematic (drawn: `pcb/kicad/`, made by `pcb/tools/gen_schematic.py`) and layout in KiCad**, from Nordic's nRF54L15 WLCSP reference layout. Import `relay-flex-outline-v1-size10.dxf` as the board edge.
4. **Ask the fab before you order** (each is a message to a company, so ask Matthew first):
   - Can they assemble the nRF54L15 WLCSP on a 4-layer flex, with via-in-pad?
   - What are their stiffener and bend limits?

   JLCPCB lists 0.15 mm vias and PI stiffeners of 0.1–0.25 mm, but I found no WLCSP-on-flex statement. If JLCPCB cannot, PCBWay is the next one to ask.
5. **First boards (5–10), assembled**, tested flat on the bench before they go into a ring.
6. **Antenna tuning** on a real ring with a NanoVNA, or with paid help from an RF designer.
7. **V1 ring** with the ready-made cell. V2 (6 mm, custom cell) waits until V1 works.

## Open questions

1. Can the fab assemble the WLCSP chip on flex, or do we need a small rigid island for the chip?
2. Nordic's own layout for this chip uses 8 copper layers with stacked micro-vias. Can we route it on 4 layers?
3. Antenna: a chip antenna or a trace loop? Can the floating band act as the antenna?
4. How long do Ufine samples take to arrive in Canada, and can they ship loose lithium cells here? (Ufine, 2026-11-04: curved cells in stock, US$3.81 each as samples, US$3.05 at 100; shipping options to follow.)
5. How long is the TL3312 switch travel, and does a press feel good through the band?
6. Which seal for the band seams keeps the click sharp?
7. Which protection chip uses under 1 µA? Ufine's curved cells come with no protection board, so the ring's board must carry it. First candidate: ABLIC **S-82N1B**: 0.6 µA typical, 0.99 µA max running, 50 nA in power-saving; overcharge level set at the factory, 3.5–4.6 V in 5 mV steps. Package SNT-6A, 1.8 × 1.57 × 0.5 mm (fits under the board beside the mic). Like other chips of this type it drives an outside pair of switches (a dual N-MOSFET); pick one about 1.6 × 1.6 mm or smaller. Candidate: onsemi EFC2J004NUZ (common-drain, 12 V, 7.1 mΩ, WLCSP-6, made for 1-cell packs and wearables); check its size and stock. Larger fallbacks: onsemi EFC2K102NUZTDG (2.98 × 1.49 × 0.1 mm). Datasheet: ablic.com/en/semicon/datasheets/power-management-ic/lithium-ion-battery-protection-ic/s-82n1b/
