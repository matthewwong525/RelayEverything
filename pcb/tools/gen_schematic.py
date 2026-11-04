"""Build the Relay V1 KiCad schematic.

Starts from Nordic's nRF54L15-CAXX reference circuit (nordic-lib-kicad, CERN-OHL-P),
then adds the mic, charger, regulator, cell protection, switches and pads.
Every connection is a net label placed on a pin end, so the drawing stays simple
and the netlist is exact. Nets follow pcb/SCHEMATIC.md.

Run:  /root/Relay/.venv/bin/python pcb/tools/gen_schematic.py
"""

import copy
import uuid
from pathlib import Path

from kiutils.items.common import Effects, Font, Position, Property
from kiutils.items.schitems import LocalLabel, NoConnect, SchematicSymbol, SymbolProjectInstance, SymbolProjectPath
from kiutils.schematic import Schematic
from kiutils.symbol import SymbolLib

ROOT = Path(__file__).resolve().parents[2]
REF_SCH = ROOT / "vendor/nordic-lib-kicad/blocks/nRF54L.kicad_blocks/nRF54L15-CAXX_Reference_Design.kicad_block/nRF54L15-CAXX_Reference_Design.kicad_sch"
KICAD_SYM = Path("/usr/share/kicad/symbols")
OUT_DIR = ROOT / "pcb/kicad"
RELAY_SYM = OUT_DIR / "relay.kicad_sym"
OUT_SCH = OUT_DIR / "relay.kicad_sch"
PROJECT = "relay"

from parts import CUSTOM_SYMBOLS, MCU_NC, MCU_PINS, PASSIVE_FOOTPRINTS, PLACEMENTS, REF_DESIGN_FOOTPRINTS


def uid():
    return str(uuid.uuid4())


def write_custom_library():
    """Write relay.kicad_sym with box symbols for the parts KiCad does not ship."""
    out = ['(kicad_symbol_lib (version 20231120) (generator "relay_gen")']
    for name, spec in CUSTOM_SYMBOLS.items():
        left, right = spec["left"], spec["right"]
        rows = max(len(left), len(right), 1)
        top = 2.54 * -(-(rows + 1) // 2)  # half height, on the 2.54 grid so pins land on it
        out.append(f'  (symbol "{name}" (in_bom yes) (on_board yes)')
        out.append(f'    (property "Reference" "{spec["ref"]}" (at 0 {top + 2.54:.2f} 0) (effects (font (size 1.27 1.27))))')
        out.append(f'    (property "Value" "{name}" (at 0 {-top - 2.54:.2f} 0) (effects (font (size 1.27 1.27))))')
        out.append(f'    (property "Footprint" "{spec["footprint"]}" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))')
        out.append(f'    (property "Datasheet" "{spec.get("datasheet", "")}" (at 0 0 0) (effects (font (size 1.27 1.27)) hide))')
        out.append(f'    (symbol "{name}_0_1" (rectangle (start -7.62 {top:.2f}) (end 7.62 {-top:.2f}) (stroke (width 0.254) (type default)) (fill (type background))))')
        out.append(f'    (symbol "{name}_1_1"')
        for side, pins, x, ang in (("L", left, -10.16, 0), ("R", right, 10.16, 180)):
            for i, (num, pname, etype) in enumerate(pins):
                y = top - 2.54 * (i + 1)
                out.append(f'      (pin {etype} line (at {x:.2f} {y:.2f} {ang}) (length 2.54) (name "{pname}" (effects (font (size 1.27 1.27)))) (number "{num}" (effects (font (size 1.27 1.27)))))')
        out.append('    )')
        out.append('  )')
    out.append(')')
    RELAY_SYM.write_text("\n".join(out) + "\n")


def load_lib_symbol(lib_file, name, lib_nick):
    lib = SymbolLib.from_file(str(lib_file))
    for sym in lib.symbols:
        if sym.entryName == name:
            s = copy.deepcopy(sym)
            s.libraryNickname = lib_nick
            return s
    raise KeyError(f"{name} not in {lib_file}")


def pin_points(lib_sym):
    """Map pin number -> (x, y, name) in symbol space (y up)."""
    pts = {}
    for unit in lib_sym.units:
        for p in unit.pins:
            pts.setdefault(p.number, (p.position.X, p.position.Y, p.name))
    return pts


def prop(key, value, x, y, hide=False):
    return Property(key=key, value=value, position=Position(X=x, Y=y, angle=0),
                    effects=Effects(font=Font(width=1.27, height=1.27), hide=hide))


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_custom_library()

    sch = Schematic.from_file(str(REF_SCH))
    sch.paper.paperSize = "A3"
    sheet_path = "/" + sch.uuid
    pwr_count = [100]

    def instance(ref):
        return [SymbolProjectInstance(name=PROJECT, paths=[SymbolProjectPath(sheetInstancePath=sheet_path, reference=ref, unit=1)])]

    for s in sch.schematicSymbols:
        for inst in s.instances:
            inst.name = PROJECT

    lib_syms = {s.libId: s for s in sch.libSymbols}

    def need(lib_id):
        if lib_id in lib_syms:
            return lib_syms[lib_id]
        nick, name = lib_id.split(":")
        lib_file = RELAY_SYM if nick == "relay" else KICAD_SYM / f"{nick}.kicad_sym"
        s = load_lib_symbol(lib_file, name, nick)
        sch.libSymbols.append(s)
        lib_syms[lib_id] = s
        return s

    labels = []
    need("power:GND")

    def gnd_at(x, y):
        pwr_count[0] += 1
        ref = f"#PWR{pwr_count[0]}"
        g = SchematicSymbol(position=Position(X=round(x, 2), Y=round(y, 2), angle=0), unit=1,
                            inBom=False, onBoard=True, uuid=uid())
        g.libraryNickname, g.entryName = "power", "GND"
        g.properties = [prop("Reference", ref, x, y + 5, hide=True), prop("Value", "GND", x, y + 3.5),
                        prop("Footprint", "", x, y, hide=True), prop("Datasheet", "", x, y, hide=True)]
        g.pins = {"1": uid()}
        g.instances = instance(ref)
        sch.schematicSymbols.append(g)

    def label_at(x, y, net, angle=0):
        if net == "GND":
            return gnd_at(x, y)
        labels.append(LocalLabel(text=net, position=Position(X=round(x, 2), Y=round(y, 2), angle=angle),
                                 effects=Effects(font=Font(width=1.27, height=1.27)), uuid=uid()))

    # kiutils drops KiCad 9's hide flags; hide all but Reference and Value again.
    for sym in sch.schematicSymbols:
        for p in sym.properties:
            if p.key not in ("Reference", "Value"):
                p.effects = p.effects or Effects(font=Font(width=1.27, height=1.27))
                p.effects.hide = True
    # Footprints for the reference-design passives (0201 where possible)
    for sym in sch.schematicSymbols:
        ref = next(p for p in sym.properties if p.key == "Reference").value
        if ref in REF_DESIGN_FOOTPRINTS:
            next(p for p in sym.properties if p.key == "Footprint").value = REF_DESIGN_FOOTPRINTS[ref]

    # Nets on the nRF54L15
    u1 = next(s for s in sch.schematicSymbols if next(p for p in s.properties if p.key == "Reference").value == "U1")
    u1_pts = pin_points(lib_syms[u1.libId])
    by_name = {}
    for num, (x, y, name) in u1_pts.items():
        by_name.setdefault(name, []).append((num, x, y))
    for pin_name, net in MCU_PINS.items():
        num, px, py = by_name[pin_name][0]
        ang = 0 if px > 0 else 180
        label_at(u1.position.X + px, u1.position.Y - py, net, ang)
    for pin_name in MCU_NC:
        num, px, py = by_name[pin_name][0]
        sch.noConnects.append(NoConnect(position=Position(X=u1.position.X + px, Y=u1.position.Y - py), uuid=uid()))
    # The reference circuit names the VDD net through C1; label it VDD too.
    num, px, py = by_name["VDD"][0]
    label_at(u1.position.X + px, u1.position.Y - py, "VDD", 90)

    # New parts
    for ref, spec in PLACEMENTS.items():
        lib = need(spec["lib"])
        x0, y0 = (round(v / 2.54) * 2.54 for v in spec["at"])
        sym = SchematicSymbol(position=Position(X=x0, Y=y0, angle=0), unit=1,
                              inBom=not ref.startswith("#"), onBoard=True, uuid=uid())
        sym.libraryNickname, sym.entryName = spec["lib"].split(":")
        sym.properties = [
            prop("Reference", ref, x0, y0 - 7),
            prop("Value", spec.get("value", spec["lib"].split(":")[1]), x0, y0 + 7),
            prop("Footprint", spec.get("footprint", PASSIVE_FOOTPRINTS.get(spec["lib"], "")), x0, y0, hide=True),
            prop("Datasheet", "", x0, y0, hide=True),
        ]
        pts = pin_points(lib)
        sym.pins = {num: uid() for num in pts}
        sym.instances = instance(ref)
        sch.schematicSymbols.append(sym)
        for num, net in spec["nets"].items():
            px, py, _ = pts[num]
            ang = 180 if px < 0 else 0
            if abs(px) < 0.01:
                ang = 90 if py > 0 else 270
            if net is None:
                sch.noConnects.append(NoConnect(position=Position(X=x0 + px, Y=y0 - py), uuid=uid()))
            else:
                label_at(x0 + px, y0 - py, net, ang)

    sch.labels.extend(labels)
    sch.to_file(str(OUT_SCH))
    print(f"Wrote {OUT_SCH} with {len(sch.schematicSymbols)} symbols and {len(labels)} labels")


if __name__ == "__main__":
    main()
