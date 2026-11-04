# Relay V1 schematic, as a connection list (draft 1, 2026-11-04)

This list is the input for the KiCad schematic. Each block names its parts and the nets between them. Pin and ball numbers come from each datasheet at drawing time; no pin is fixed here. Start from Nordic's nRF54L15 WLCSP reference circuit for the chip, the crystal and the antenna, and do not change their values.

## Nets

| Net | Joins |
|---|---|
| `VCHG` | Charge pin 1, charger input, 1 µF capacitor to `GND` |
| `GND` | Charge pin 2, all grounds |
| `VBAT` | Cell + through the protection chip, charger battery output, LDO input |
| `VDD` | LDO output (1.8 V), nRF54L15 supply pins and decoupling as in the reference circuit, programming pad `VDD` |
| `MIC_VDD` | P1.06 in high drive (mic power on/off), T5837 pad 7, 0.1 µF to `GND`. The mic needs 1.65–1.98 V. Keep `PDM_CLK` low while the mic is off. |
| `PDM_CLK` | P1.04 (a clock pin on P1, where PDM20 lives), T5837 pad 6 |
| `PDM_DIN` | P1.11, T5837 pad 1. SELECT to `GND`: right channel, data after the falling clock edge |
| `BTN` | All six TL3312 switches in parallel to `GND`; P0.00 with internal pull-up, set to wake the chip (P2 pins cannot wake it) |
| `CHG_STAT` | BQ25101 CHG (open-drain, low during the first charge only), P0.01 with pull-up (the ring knows it is charging) |
| `VBAT_SENSE` | `VBAT` through an always-on 10 MΩ / 4.7 MΩ divider (0.29 µA) and 100 nF, to P1.05 (AIN1). 4.2 V reads as 1.34 V. |
| `SWDIO`, `SWDCLK` | nRF54L15 debug pins, programming pads |
| `RF` | nRF54L15 antenna pin, matching network (as in the reference circuit, tune later), chip antenna |
| `XC1`, `XC2` | nRF54L15 crystal pins, 32 MHz crystal, load capacitors as in the reference circuit |

## Blocks

| Block | Parts | Notes |
|---|---|---|
| Chip | nRF54L15 WLCSP, decoupling, 32 MHz crystal | Reference circuit. Use the chip's internal low-power clock (no 32 kHz crystal). PDM is on port P1: `PDM_CLK` on P1.04, `PDM_DIN` on P1.11 (both clock pins). |
| Mic | TDK T5837, bottom port | Sound hole through the board. Waterproof acoustic mesh on the outer face over the hole. Set the SELECT pin for one channel. |
| Button | 6 × E-Switch TL3312 | All on `BTN`. A polyimide stiffener behind each. |
| Charging | 2 gold-plated pins, BQ25101, 13.7 kΩ charge resistor (9.9 mA) | The charger takes power only in, so sweat across the pins cannot drain the cell. Add a TVS diode on `VCHG` if there is room. |
| Cell | Ufine 156825 (16 mAh), protection chip | Protection cuts the cell off below about 3.0 V and above 4.25 V. |
| Power | LDO 1.8 V, under 0.1 µA rest current | |
| Debug | 4 pads: `VDD`, `GND`, `SWDIO`, `SWDCLK` | Connect to the nRF54L15 DK's debug output with a pogo-pin clip before the ring is sealed. |

## Rules for the layout

1. Only the six switches go on the outer face. All other parts go on the inner face.
2. Put the chip, crystal, antenna and matching network close together. Keep metal away from the antenna, and keep it far from the cell.
3. Keep the mic hole near a band seam, because the sound comes in there.
4. Put stiffeners only under the switches and the chip area. The rest of the strip must bend to the ring radius (about 12 mm for size 10).
