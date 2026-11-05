---
title: The board
description: The flexible board inside the Relay ring, and where each part sits on it.
---

The Relay ring has one flexible board: a strip that runs around the inside of the ring. Its KiCad files and plans are [on GitHub](https://github.com/matthewwong525/RelayEverything/tree/main/pcb).

- **Size:** 74.3 × 6.8 mm for US size 10. The ends meet at the palm side.
- **Layers:** four copper layers, with a thin stiffener behind each switch.
- **Switches:** six, 12.5 mm apart. Only the switches face out; every other part faces the finger, so nothing blocks the band.

## Where the parts sit

| Place on the ring | What is there |
|---|---|
| Top, above the finger | The chip, its crystal, the power parts, the microphone, the antenna and the programming pads |
| Each side | A charging pin |
| Palm side | The battery, under the strip |

The microphone hears through a small hole in the board, under a waterproof mesh. Sound reaches it through the band's seam.

## Status

The schematic is drawn. The layout comes next. The open questions are the antenna, and whether the factory can fit the chip on a flexible board. [Parts and battery](../parts-and-battery/) lists the parts.
