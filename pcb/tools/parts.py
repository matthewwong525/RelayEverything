"""Relay V1 parts, pins and nets for gen_schematic.py.

Pins come from the datasheets (2026-11-04). Still to confirm: the CSD83325L pads, and the footprints marked relay:.
Positions are in schematic mm (A3 sheet); the Nordic reference circuit sits near x 90-200.
"""

# Box symbols for parts KiCad does not ship: (number, name, pin type), left then right.
CUSTOM_SYMBOLS = {
    "BQ25101YFP": {  # TI 10 mA linear charger, DSBGA-6, 0.4 mm pitch. BQ25101, not BQ25100: only it has CHG.
        "ref": "U",
        "footprint": "Package_BGA:Texas_DSBGA-6_0.95x1.488mm_Layout2x3_P0.4mm",
        "datasheet": "https://www.ti.com/lit/ds/symlink/bq25100.pdf",
        "left": [("A2", "IN", "power_in"), ("B2", "ISET", "passive"), ("B1", "TS", "passive")],
        "right": [("A1", "OUT", "power_out"), ("C1", "~{CHG}", "open_collector"), ("C2", "VSS", "power_in")],
    },
    "TPS7A0218PDQN": {  # TI 1.8 V LDO, 25 nA rest current, X2SON-4 1 x 1
        "ref": "U",
        "footprint": "Package_SON:Texas_X2SON-4_1x1mm_P0.65mm",
        "datasheet": "https://www.ti.com/lit/ds/symlink/tps7a02.pdf",
        "left": [("4", "IN", "power_in"), ("3", "EN", "input")],
        "right": [("1", "OUT", "power_out"), ("2", "GND", "power_in")],
    },
    "T5837": {  # TDK bottom-port PDM mic, DS-000447 rev 1.1. VDD is passive because a chip pin powers it.
        "ref": "MK",
        "footprint": "relay:TDK_T5837",
        "datasheet": "https://invensense.tdk.com/download-pdf/t5837-datasheet/",
        "left": [("7", "VDD", "passive"), ("6", "CLK", "input"), ("2", "SELECT", "input")],
        "right": [("1", "DATA", "output"), ("4", "NC", "passive"), ("5", "NC", "passive"), ("3", "GND", "power_in")],
    },
    "CSD83325L": {  # TI dual N-FET, common drain, 1.35 x 1.35 LGA; the cell's cut-off switch
        "ref": "Q",
        "footprint": "relay:TI_CSD83325L",
        "datasheet": "https://www.ti.com/lit/ds/symlink/csd83325l.pdf",
        "left": [("S1", "S1", "passive"), ("G1", "G1", "input")],
        "right": [("S2", "S2", "passive"), ("G2", "G2", "input")],
    },
}

PASSIVE_FOOTPRINTS = {
    "Device:R_Small": "Resistor_SMD:R_0201_0603Metric",
    "Device:C_Small": "Capacitor_SMD:C_0201_0603Metric",
    "Switch:SW_Push": "relay:EWitch_TL3312",
    "Connector:TestPoint": "TestPoint:TestPoint_Pad_D1.0mm",
    "Device:Battery_Cell": "relay:Cell_Tabs_Ufine156825",
    "Device:Antenna_Chip": "RF_Antenna:Johanson_2450AT18x100",
    "Battery_Management:BQ297xy": "Package_SON:WSON-6_1.5x1.5mm_P0.5mm",
}

# The Nordic reference passives, at 0201 where the part allows it.
REF_DESIGN_FOOTPRINTS = {
    "C1": "Capacitor_SMD:C_0402_1005Metric",
    "C4": "Capacitor_SMD:C_0201_0603Metric",
    "C7": "Capacitor_SMD:C_0201_0603Metric",
    "C2": "Capacitor_SMD:C_0201_0603Metric",
    "C3": "Capacitor_SMD:C_0201_0603Metric",
    "C5": "Capacitor_SMD:C_0201_0603Metric",
    "C6": "Capacitor_SMD:C_0201_0603Metric",
    "C8": "Capacitor_SMD:C_0201_0603Metric",
    "C9": "Capacitor_SMD:C_0201_0603Metric",
    "L1": "Inductor_SMD:L_0402_1005Metric",
    "L2": "Inductor_SMD:L_0201_0603Metric",
    "L3": "Inductor_SMD:L_0201_0603Metric",
    "L4": "Inductor_SMD:L_0201_0603Metric",
    "FB1": "Inductor_SMD:L_0201_0603Metric",
    "Y1": "Crystal:Crystal_SMD_WE_IQXC-26-4Pin_1.6x1.2mm",
}

# nRF54L15 pin name -> net. AIN pins are P1.04-P1.07 and P1.11-P1.14.
MCU_PINS = {
    "P1.04": "PDM_CLK",     # PDM20 is on port P1; CLK needs a clock pin
    "P1.11": "PDM_DIN",     # a second clock pin, to be safe
    "P1.06": "MIC_VDD",     # high drive; keep PDM_CLK low while the mic is off
    "P1.05": "VBAT_SENSE",  # AIN1
    "P0.00": "BTN",         # pull-up inside; P0 and P1 wake from System OFF, P2 cannot
    "P0.01": "CHG_STAT",    # pull-up inside; low while charging
    "SWDIO": "SWDIO",
    "SWDCLK": "SWDCLK",
}
# Unused pins get a no-connect mark. RESET has a pull-up inside; SWD can reset the chip.
MCU_NC = ["~{RESET}"] + [p for p in (
    [f"P0.0{i}" for i in range(5)] + [f"P1.{i:02d}" for i in range(16)] + [f"P2.{i:02d}" for i in range(11)]
) if p not in MCU_PINS]


def r(value, at, n1, n2):
    return {"lib": "Device:R_Small", "value": value, "at": at, "nets": {"1": n1, "2": n2}}


def c(value, at, n1, n2):
    return {"lib": "Device:C_Small", "value": value, "at": at, "nets": {"1": n1, "2": n2}}


def tp(name, at, net):
    return {"lib": "Connector:TestPoint", "value": name, "at": at, "nets": {"1": net}}


X = 240  # left edge of the new circuits
PLACEMENTS = {
    # Charging: two pins on the inside wall, then the charger
    "TP1": tp("CHG+", (X, 30), "VCHG"),
    "TP2": tp("CHG-", (X + 10, 30), "GND"),
    "C10": c("1uF", (X + 20, 30), "VCHG", "GND"),
    "U2": {"lib": "relay:BQ25101YFP", "at": (X + 50, 35), "nets": {
        "A2": "VCHG", "B2": "ISET", "B1": "TS", "A1": "VBAT", "C1": "CHG_STAT", "C2": "GND"}},
    # ISET = KISET / ICHG = 135 A-ohm / 10 mA = 13.5k; 13.7k gives 9.9 mA (0.6C).
    "R1": r("13.7k", (X + 30, 50), "ISET", "GND"),
    # TS: a fixed 10k makes the charger read a normal temperature.
    "R2": r("10k", (X + 40, 55), "TS", "GND"),
    "C11": c("1uF", (X + 75, 30), "VBAT", "GND"),

    # Cell and its protection (cuts the cell's minus side)
    "BT1": {"lib": "Device:Battery_Cell", "value": "Ufine 156825 16mAh", "at": (X, 90),
            "nets": {"1": "VBAT", "2": "BAT_N"}},
    "U3": {"lib": "Battery_Management:BQ297xy", "value": "BQ29700DSE", "at": (X + 40, 90), "nets": {
        "5": "PROT_VDD", "6": "PACK_N", "4": "BAT_N", "1": None, "2": "COUT", "3": "DOUT"}},
    "R3": r("330", (X + 20, 80), "VBAT", "PROT_VDD"),
    "C12": c("100nF", (X + 25, 100), "PROT_VDD", "BAT_N"),
    "R4": r("2.2k", (X + 60, 80), "PACK_N", "GND"),
    "Q1": {"lib": "relay:CSD83325L", "at": (X + 80, 100), "nets": {
        "S1": "BAT_N", "G1": "DOUT", "S2": "GND", "G2": "COUT"}},

    # 1.8 V supply for the chip and the mic
    "U4": {"lib": "relay:TPS7A0218PDQN", "at": (X + 40, 140), "nets": {
        "4": "VBAT", "3": "VBAT", "1": "VDD", "2": "GND"}},
    "C13": c("1uF", (X + 15, 140), "VBAT", "GND"),
    "C14": c("1uF", (X + 65, 140), "VDD", "GND"),

    # Cell voltage: always-on divider, 0.29 uA; 4.2 V reads as 1.34 V
    "R5": r("10M", (X + 100, 130), "VBAT", "VBAT_SENSE"),
    "R6": r("4.7M", (X + 100, 145), "VBAT_SENSE", "GND"),
    "C15": c("100nF", (X + 110, 145), "VBAT_SENSE", "GND"),

    # Mic, powered from a high-drive chip pin; SELECT low = right channel (data after the CLK falling edge)
    "MK1": {"lib": "relay:T5837", "at": (X + 40, 185), "nets": {
        "7": "MIC_VDD", "6": "PDM_CLK", "2": "GND", "1": "PDM_DIN", "4": "GND", "5": "GND", "3": "GND"}},
    "C16": c("100nF", (X + 15, 185), "MIC_VDD", "GND"),

    # Antenna on the reference circuit's ANT net
    "AE1": {"lib": "Device:Antenna_Chip", "value": "2450AT18A100", "at": (X + 100, 185),
            "nets": {"1": "ANT", "2": None}},

    # Programming pads
    "TP3": tp("VDD", (X, 245), "VDD"),
    "TP4": tp("GND", (X + 10, 245), "GND"),
    "TP5": tp("SWDIO", (X + 20, 245), "SWDIO"),
    "TP6": tp("SWDCLK", (X + 30, 245), "SWDCLK"),
}

# Six switches under the band, all on one input
for i in range(6):
    PLACEMENTS[f"SW{i + 1}"] = {"lib": "Switch:SW_Push", "value": "TL3312", "at": (X + 15 * i, 215),
                               "nets": {"1": "BTN", "2": "GND"}}

# Power flags: these nets get power from outside the sheet (charger clip, cell, a chip pin).
for i, net in enumerate(["GND", "VCHG", "BAT_N"]):
    PLACEMENTS[f"#FLG0{i + 1}"] = {"lib": "power:PWR_FLAG", "value": "PWR_FLAG", "at": (X + 130 + 15 * i, 30),
                                   "footprint": "", "nets": {"1": net}}
