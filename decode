#!/usr/bin/python3

import argparse
import sys
import struct
import json
import time
import traceback
from enum import Enum
import io


version = None  # global state is not nice but that's how it is for now.

skipped_blueprints = 0

################################################################
#
# utilities

def debug(*args):
    if opt.d:
        print(*args, file=sys.stderr, flush=True)

def verbose(*args):
    if opt.v or opt.d:
        print(*args, file=sys.stderr, flush=True)

def error(*args):
    print(*args, file=sys.stderr, flush=True)


def normalize_float(value):
    rounded = round(value)
    if rounded == value:
        return rounded
    else:
        return value


def normalize_position(p):
    p["x"] = normalize_float(p["x"])
    p["y"] = normalize_float(p["y"])


class ParseError(Exception):
    pass


################################################################
#
# Version

class Version(int):
    def __new__(cls, v0: int, v1: int, v2: int, v3: int = 0):
        encoded = (v0 << 48) + (v1 << 32) + (v2 << 16) + v3
        return super().__new__(cls, encoded)

    def __format__(self, spec):
        decoded = self._decode()
        return format(".".join(map(str, decoded)), spec)

    def __repr__(self):
        v0, v1, v2, v3 = self._decode()
        return f"Version({v0}, {v1}, {v2}, {v3})"

    def _decode(self):
        def _(bits):
            return int(self) >> bits & 0xffff
        return ( _(48), _(32), _(16), _(0) )


V_1_0_0_0  = Version(1,0,0)  # first stable in 1.0 -- obviously
V_1_1_0_0  = Version(1,1,0)  # first EXPERIMENTAL in 1.1
V_1_1_4_0  = Version(1,1,4)
V_1_1_19_0 = Version(1,1,19) # first stable in 1.1 -- not so obvious
V_1_1_43_0 = Version(1,1,43)
V_1_1_51_4 = Version(1,1,51,4)
V_1_1_62_5 = Version(1,1,62,5)

STABLE_V_1_1 = V_1_1_19_0   # marker for "somewhere between 1.0 and first stable 1.1"

MINIMUM_VERSION = V_1_0_0_0


################################################################
#
# Index

class Index:

    # types (distinct number ranges)
    # `value` is the prototype-class (except "entity"). In BP exports the wording is just "virtual".
    class Type(Enum):
        ITEM = "item"
        FLUID = "fluid"
        VSIGNAL = "virtual-signal"
        TILE = "tile"
        ENTITY = "entity"
        RECIPE = "recipe"

    ITEM = Type.ITEM
    FLUID = Type.FLUID
    VSIGNAL = Type.VSIGNAL
    TILE = Type.TILE
    ENTITY = Type.ENTITY
    RECIPE = Type.RECIPE

    _type_mapping = {
        # item
        "ammo": ITEM,
        "armor": ITEM,
        "blueprint": ITEM,
        "blueprint-book": ITEM,
        "capsule": ITEM,
        "deconstruction-item": ITEM,
        "gun": ITEM,
        "item": ITEM,
        "item-with-entity-data": ITEM,
        "module": ITEM,
        "spidertron-remote": ITEM,
        "rail-planner": ITEM,
        "repair-tool": ITEM,
        "tool": ITEM,
        "upgrade-item": ITEM,
        # item without known ways to put them into blueprints
        "copy-paste-tool": ITEM,
        "item-with-label": ITEM,
        "item-with-inventory": ITEM,
        "item-with-tags": ITEM,
        "mining-tool": ITEM,
        "selection-tool": ITEM,
        # fluid
        "fluid": FLUID,
        # virtual-signal
        "virtual-signal": VSIGNAL,
        # entity
        "accumulator": ENTITY,
        "ammo-turret": ENTITY,
        "arithmetic-combinator": ENTITY,
        "artillery-turret": ENTITY,
        "artillery-wagon": ENTITY,
        "assembling-machine": ENTITY,
        "beacon": ENTITY,
        "boiler": ENTITY,
        "burner-generator": ENTITY,
        "cargo-wagon": ENTITY,
        "cliff": ENTITY,
        "constant-combinator": ENTITY,
        "container": ENTITY,
        "curved-rail": ENTITY,
        "decider-combinator": ENTITY,
        "electric-energy-interface": ENTITY,
        "electric-pole": ENTITY,
        "electric-turret": ENTITY,
        "entity-ghost": ENTITY,
        "fish": ENTITY,
        "fluid-turret": ENTITY,
        "fluid-wagon": ENTITY,
        "furnace": ENTITY,
        "gate": ENTITY,
        "generator": ENTITY,
        "heat-interface": ENTITY,
        "heat-pipe": ENTITY,
        "infinity-container": ENTITY,
        "infinity-pipe": ENTITY,
        "inserter": ENTITY,
        "item-entity": ENTITY,
        "item-request-proxy": ENTITY,
        "lab": ENTITY,
        "lamp": ENTITY,
        "land-mine": ENTITY,
        "linked-belt": ENTITY,
        "linked-container": ENTITY,
        "loader": ENTITY,
        "loader-1x1": ENTITY,
        "locomotive": ENTITY,
        "logistic-container": ENTITY,
        "mining-drill": ENTITY,
        "offshore-pump": ENTITY,
        "pipe": ENTITY,
        "pipe-to-ground": ENTITY,
        "power-switch": ENTITY,
        "programmable-speaker": ENTITY,
        "pump": ENTITY,
        "radar": ENTITY,
        "rail-chain-signal": ENTITY,
        "rail-signal": ENTITY,
        "reactor": ENTITY,
        "roboport": ENTITY,
        "rocket-silo": ENTITY,
        "simple-entity": ENTITY,
        "solar-panel": ENTITY,
        "splitter": ENTITY,
        "storage-tank": ENTITY,
        "straight-rail": ENTITY,
        "tile-ghost": ENTITY,
        "train-stop": ENTITY,
        "transport-belt": ENTITY,
        "tree": ENTITY,
        "underground-belt": ENTITY,
        "wall": ENTITY,
        # tile
        "tile": TILE,
        # recipe
        "recipe": RECIPE,
        # special
        "flying-text": ENTITY,  # no handler (yet), used for "unknown-entity" in upgrade- and deconstruction plans
    }

    class Entry:
        def __init__(self, id: int, type, prototype: str, name: str):
            self.id = id
            self.type = type
            self.prototype = prototype
            self.name = name

    def __init__(self):
        self._data = {
            self.ITEM: {},
            self.FLUID: {},
            self.VSIGNAL: {},
            self.TILE: {},
            self.ENTITY: {},
            self.RECIPE: {},
        }

    def add(self, id: int, prototype: str, name: str) -> Entry:
        if id == 0x00:
            raise ValueError("ID 0 is not allowed")
        if prototype not in self._type_mapping:
            raise KeyError(f"unknown prototype '{prototype}'")
        type = self._type_mapping[prototype]
        bucket = self._data[type]
        if id in bucket:
            raise ValueError(f"ID {id} ({id:#x}) is already used for '{bucket[id]['name']}'")
        entry = bucket[id] = Index.Entry(id, type, prototype, name)
        return entry

    def get(self, type: Type, id: int) -> Entry:
        return self._data[type][id]


################################################################
#
# primitives

class PrimitiveStream:

    def __init__(self, f):
        self._f = f

    def _read(self, format):
        return struct.unpack(
            format,
            self._f.read(struct.calcsize(format)))[0]

    def tell(self):
        return self._f.tell()

    def seek(self, offset, whence):
        return self._f.seek(offset, whence)

    def bool(self):
        data = self.u8()
        if data != 0x00 and data != 0x01:
            position = self.tell() - 1
            raise ParseError(f"invalid boolean value {data:#04x} at position {position} ({position:#x})")
        return data == 0x01

    def s8(self):
        return self._read("<b")

    def u8(self):
        return self._read("<B")

    def s16(self):
        return self._read("<h")

    def u16(self):
        return self._read("<H")

    def s32(self):
        return self._read("<i")

    def u32(self):
        return self._read("<I")

    # see https://en.wikipedia.org/wiki/Single-precision_floating-point_format#Single-precision_examples
    # for remarkable examples like "0x3f80_0000" for "1"
    def f32(self):
        return self._read("<f")

    # see https://en.wikipedia.org/wiki/Double-precision_floating-point_format#Double-precision_examples
    # for remarkable examples like "0x3ff0_0000_0000_0000" for "1"
    def f64(self):
        return self._read("<d")

    def count(self):
        length = self.u8()
        if length == 0xff:
            return self.u32()
        else:
            return length

    def count8(self):
        data = self.u8()
        if data == 0xff:
            position = self.tell()
            raise ParseError(f"unexpected flexible length 0xff at {position} ({position:#x})")
        return data

    def count16(self):
        return self.u16()

    def count32(self):
        return self.u32()

    def string(self):
        length = self.count()
        return self._f.read(length).decode("utf-8")

    def mapped_u8(self, *args):
        index = self.u8()
        if index in range(len(args)):
            return args[index]
        else:
            position = self.tell() - 1
            raise ParseError(f"unexpected value {index} at position {position} ({position:#x}): only 0..{len(args)-1} expected")

    def expect(self, *expected_bytes):
        if not expected_bytes:
            raise ValueError("expect at least one byte")

        for expected in expected_bytes:
            actual = self.u8()
            if actual != expected:
                position = self.tell() - 1
                raise ParseError(f"expected {expected:#04x} but got {actual:#04x} at position {position} ({position:#x})")

    def expect_oneof(self, *expected_values):
        if not expected_values:
            raise ValueError("expect at least one byte")

        actual = self.u8()
        if actual not in set(expected_values):
            position = self.tell() - 1
            expected = ", ".join([ f"{b:#04x}" for b in expected_values])
            raise ParseError(f"expected one of ({expected}) but got {actual:#04x} at position {position} ({position:#x})")

    def ignore(self, size, guess=None):
        file_position = self.tell()
        data = self._f.read(size)
        data = self._to_hex(data)

        if guess:
            debug(f"#\tignored {guess} @{file_position:#x}: {data}")
        else:
            debug(f"#\tignored @{file_position:#x}: {data}")

    def dump_trailing_data(self, offsets=True, printables=True):
        position, data = self._f.tell(), self._f.read(16)
        if data:
            debug("trailing data:")
            while data:
                parts = []
                if offsets:
                    parts.append(f"{position:06x}")
                parts.append(self._to_hex(data))
                if printables:
                    parts.append(self._to_print(data))
                debug(*parts)
                position, data = self._f.tell(), self._f.read(16)

    @staticmethod
    def _to_hex(data: bytes):
        return " ".join([f'{b:02x}' for b in data])

    @staticmethod
    def _to_print(data: bytes):
        return "".join([b if b.isprintable() else "." for b in data.decode("latin1")])


################################################################
#
# stream helpers

def read_entry(stream, index: Index, type: Index.Type) -> Index.Entry:
    if type == Index.TILE:
        id = stream.u8()
        offset = 1
    else:
        id = stream.u16()
        offset = 2

    if id:
        try:
            return index.get(type, id)
        except KeyError:
            file_position = stream.tell() - offset
            raise ParseError(f"unknown '{type.value}' ID {id:#x} at {file_position} ({file_position:#x})") from None
    else:
        return None


def read_name(stream, index: Index, type: Index.Type) -> str:
    entry = read_entry(stream, index, type)
    if entry:
        return entry.name
    else:
        return None


def read_signal(stream, index: Index):
    index_type = stream.mapped_u8(Index.ITEM, Index.FLUID, Index.VSIGNAL)
    name = read_name(stream, index, index_type)
    if not name:
        return None
    return {
        "type": {Index.ITEM: "item", Index.FLUID: "fluid", Index.VSIGNAL: "virtual"}[index_type],
        "name": name
    }


# circuit condition, logistic condition, train schedules
#
#   length: 12 byte
#   default: 01 00 00 00 00 00 00 00 00 00 00 01
#
def read_condition(stream, index: Index):
    # same order in drop-down
    comparator = stream.mapped_u8(">", "<", "=", "≥", "≤", "≠")

    first_signal = read_signal(stream, index)
    second_signal = read_signal(stream, index)
    constant = stream.s32()
    use_constant = stream.bool()

    # hide "default" condition
    if not first_signal and not second_signal and comparator == "<" and not constant:
        return None

    condition = {}
    if first_signal:
        condition["first_signal"] = first_signal

    condition["comparator"] = comparator
    # The export does not output data if it is hidden in the UI.
    if use_constant:
        condition["constant"] = constant
    else:
        condition["second_signal"] = second_signal

    return condition


#
# Property Tree
#
# See https://wiki.factorio.com/Property_tree
#
# Known differences:
#
#   - Strings in keys (list and dictionaries) and values (type 3) have an
#       additional `is_empty` flag.
#
#       The wiki insinuates (by linking to Pascal strings) that keys don't
#       have an additional flag, only "value" strings.
#
#   - The `any-type` flag after the type field should be `False` by default but
#       it seems to be `True` sometimes.
#
# Also:
#
#   - Type 0 (`None`) cannot be set via Lua: `nil` values in tables just
#       don't exist.
#   - Type 4 (`List`) cannot be set via Lua: Both arrays and dictionaries are
#       the same construct.
#
def read_tag_property_tree(stream):
    type = stream.u8()
    any_type = stream.bool() # ignored
    if type == 0:       # None
        return None
    elif type == 1:     # Bool
        return stream.bool()
    elif type == 2:     # Number
        return normalize_float(stream.f64())
    elif type == 3:     # String
        return read_tag_string(stream)
    elif type == 4:     # List
        return read_tag_list(stream)
    elif type == 5:     # Dictionary
        return read_tag_dictionary(stream)
    else:
        position = stream.tell() - 2
        raise ParseError(f"invalid type {type} in property tree at position {position} ({position:#x})")


def read_tag_list(stream):
    result = []
    count = stream.count32()
    for i in range(count):
        entry_name = read_tag_string(stream) # ignored
        entry_value = read_tag_property_tree(stream)
        result.append(entry_value)
    return result


def read_tag_dictionary(stream):
    result = {}
    count = stream.count32()
    for i in range(count):
        entry_name = read_tag_string(stream)
        entry_value = read_tag_property_tree(stream)
        result[entry_name] = entry_value
    return result

def read_tag_string(stream):
    is_empty = stream.bool()
    if is_empty:
        return None
    else:
        return stream.string()


################################################################
#
# entity parts (ep_*)


def ep_entity_id(stream, index, entity):
    flags = stream.u8()
    # 0x10	-- has entity id (default=0)
    if flags | 0x10 != 0x10:
        file_position = stream.tell() - 1
        raise ParseError(f"unexpected flags {flags:#04x} at {file_position} ({file_position:#x})")

    if flags & 0x10:
        stream.expect(0x01)
        entity_id = stream.u32()
        entity["entity_id"] = entity_id
        # Note: The export format uses "entity_number" here but means index
        # number in the entity list. This "entity_number" is referenced by
        # "entity_id" in the wire connections.
        #
        # The binary format uses another value - an unique number.
        # The code therefore uses the term "entity_id" for the raw binary
        # number. This number and the counterparts in the wire connection
        # and train schedules must be replaced later when all entities
        # (and their *number*) known.


def ep_v1_1_51_4_flag(stream, index, entity, *expected_values):
    if version >= V_1_1_51_4:
        # * In the vanilla game turrets, land-mines and radar have the
        #   value 0x01.
        # * In the vanilla game rail vehicles (locomotive, cargo-wagon,
        #   fluid-wagon, artillery-wagon) have the value 0x00 but in
        #   Krastorio 2 the value is 0x01 without any change in the export.
        if len(expected_values) == 1:
            stream.expect(*expected_values)
        else:
            stream.expect_oneof(*expected_values)


def ep_v1_1_62_5_flag(stream, index, entity):
    # Release-Notes 1.1.62:
    #   > Added support for container entities with filters
    #   > by using inventory_type = "with_bar" or "with_filters_and_bar".
    # So this could be a flag opening a "filters" section.
    if version >= V_1_1_62_5:
        stream.expect(0x00)


def ep_bar(stream, index, entity):
    # TODO: cargo-wagon wants to call this not with a real entity
    # but with an "inventory" wrapper. Handle this case better.

    # "Warehousing Mod" writes 2000 stacks but the UI reports 1800.
    bar = stream.u16()
    # The export format suppresses the default values. But these
    # are - in general - unknown to me beyond the vanilla chests.
    bar_defaults = {
        # container
        "wooden-chest" : 0x10,
        "iron-chest"   : 0x20,
        "steel-chest"  : 0x30,
        # logistic-container
        "logistic-chest-active-provider"	: 0x30,
        "logistic-chest-passive-provider"	: 0x30,
        "logistic-chest-storage"	: 0x30,
        "logistic-chest-requester"	: 0x30,
        "logistic-chest-buffer"		: 0x30,
        # cheat mode
        "infinity-chest" : 0x30,
        # trains
        "cargo-wagon"	 : 0x28,
        # Editor Extensions
        "ee-infinity-chest"                  : 0x64,
        "ee-infinity-chest-active-provider"  : 0x64,
        "ee-infinity-chest-passive-provider" : 0x64,
        "ee-infinity-chest-storage"          : 0x64,
        "ee-infinity-chest-buffer"           : 0x64,
        "ee-infinity-chest-requester"        : 0x64,
        "ee-aggregate-chest"                 : -1,
        "ee-aggregate-chest-passive-provider": -1,
        "ee-infinity-cargo-wagon"            : 0x64,
    }
    default_bar = bar_defaults.get(entity["name"])
    if default_bar != -1 and default_bar != bar:
        entity["bar"] = bar


# maybe helpfull: https://wiki.factorio.com/Types/Direction
# Turrets seem to support an additional value `8`.
def ep_direction(stream, index, entity):
    direction = stream.u8()
    if direction:
        entity["direction"] = direction


def ep_orientation(stream, index, entity):
    # 00 00 00 00 = 0.0f  -> North
    # 00 00 80 3e = 0.25f -> East
    # 00 00 00 3f = 0.5f  -> South
    # 00 00 40 3f = 0.75f -> West
    orientation = stream.f32()
    orientation = normalize_float(orientation)
    entity["orientation"] = orientation


def ep_logistic_settings(stream, index, entity):
    # 1: active provider
    # 2: storage
    # 3: requester
    # 4: passive provider
    # 5: buffer
    logistic_mode = stream.u8()  # not used in export
    if not 0 <= logistic_mode <= 5:
        raise ParseError(f"unknown logistic mode {logistic_mode}")

    stream.expect(0x03)

    request_filters = []
    filter_count = stream.count()
    for f in range(filter_count):
        item_name = read_name(stream, index, Index.ITEM)
        item_count = stream.u32()
        stream.expect(0x00)
        if item_name:
            request_filters.append({
                "index": f + 1,
                "name": item_name,
                "count": item_count
            })
    if request_filters:
        entity["request_filters"] = request_filters

    if logistic_mode in (2,3,5) or version >= STABLE_V_1_1:
        # In v1.0.0 every logistic chest which can have logistic-filters
        # or -requests has the flag "request from buffers". But the UI
        # shows this flag only for requester chests.
        # In v1.0.0 the existence of the flag correlates with the number
        # of filters because a fixed number of slots were always allocated
        # for a specific type of chest.
        # Since 1.1.19 the number of filter slots can be extended (and
        # possibly shrunk), so this may not be a stable criteria any more.
        # So it's nice that the flag is always present since v1.1.19.
        request_from_buffers = stream.bool()
        if request_from_buffers:
            entity["request_from_buffers"] = True


def ep_circuit_connections(stream, index, entity, own_circuit_id="1"):
    connections = {}

    # How many "colors"?
    # https://lua-api.factorio.com/latest/defines.html#defines.wire_type
    for color in ("red", "green"):
        peers = []
        peer_count = stream.count8()
        for p in range(peer_count):
            entity_id = stream.u32()
            circuit_id = stream.u8()
            peers.append({
                "entity_id": entity_id,
                "circuit_id": circuit_id,
            })
            stream.expect(0xff)
        if peers:
            connections[color] = peers

    # maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.circuit_connector_id

    if connections:
        if "connections" not in entity:
            entity["connections"] = {}
        entity["connections"][str(own_circuit_id)] = connections

    stream.expect(*[0x00]*9)


def ep_circuit_condition(stream, index, entity):
    circuit_condition = read_condition(stream, index)
    if circuit_condition:
        control_behavior = entity.setdefault("control_behavior", {})
        control_behavior["circuit_condition"] = circuit_condition


def ep_logistic_condition(stream, index, entity):
    logistic_condition = read_condition(stream, index)
    if logistic_condition:
        control_behavior = entity.setdefault("control_behavior", {})
        control_behavior["logistic_condition"] = logistic_condition

    logistic_connected = stream.bool()
    if logistic_connected:
        control_behavior = entity.setdefault("control_behavior", {})
        control_behavior["connect_to_logistic_network"] = True


def ep_railway_vehicle_common(stream, index, entity):
    stream.expect(*[0x00]*10, 0x01)

    # Setable in Krastorio 2 in locomotives, cargo wagon and artillery wagon
    # but not fluid wagon.
    # Strange: Seems to be stored only in the .dat file but not in the export
    # strings. This defeats a perfect round-trip!
    enable_logistics_while_moving = stream.bool()

    stream.expect(*[0x00]*22)

    # 26 22 4f
    # e7 73 ed
    # ac d3 65
    # 84 38 b3 02 # first reported by PDiracDelta
    # 56 47 07 09
    # Seems to be stuck at (0,0,0,0) since v.1.1.19 or v1.1.21.
    stream.ignore(4, "train-id(?)")

    stream.expect(0x00)


def ep_filters(stream, index, entity):
    # Even without filters the count is > 0 for filter-inserters.
    filter_count = stream.u8()

    filters = []
    for f in range(filter_count):
        filter_name = read_name(stream, index, Index.ITEM)
        if filter_name:
            filters.append({
                "index": f + 1,
                "name": filter_name
            })
    if filters:
        entity["filters"] = filters


def ep_items(stream, index, entity):

    # Interesting point: Items are not a simple list like icons.
    # Instead the items are first sorted and then grouped by type.
    # So building an assembler with modules Eff1, Sp1, Eff1, Sp1 the blueprint
    # only contains the data "Sp1: 2, Eff:2". So some details are omitted.

    items = {}
    item_count = stream.u32()
    for i in range(item_count):
        item_name = read_name(stream, index, Index.ITEM)
        item_count = stream.u32()
        items[item_name] = item_count
    if items:
        entity["items"] = items


def ep_color(stream, index, entity):
    use_color = stream.bool()
    if use_color:
        entity["color"] = {
            "r": normalize_float(stream.f32()),
            "g": normalize_float(stream.f32()),
            "b": normalize_float(stream.f32()),
            "a": normalize_float(stream.f32()),
        }


def ep_turret_common(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x01) # Strange: Why is that value "1" HERE!
    stream.expect(*[0x00]*4)
    stream.expect(0x00, 0x00, 0x80, 0x3f) # 1.0f
    stream.expect(*[0x00]*17)

    # Strictly speaking: artillery-turret doesn't have "orientation" besides 0.0f.
    ep_orientation(stream, index, entity)


def fixup_turret_direction(stream, index, entity):
    direction = entity.get("direction")
    orientation = entity.pop("orientation", 0.0)
    if direction == 8:
        # This "precedence" is not backed by hard facts!
        # But there are also no counterexamples.
        #
        # The vanilla game pins `direction` always to `8` for some turret
        # types like gun-turrets. But at least one modded turret
        # (shotgun-ammo-turret-rampant-arsenal) managed to store "synchronized"
        # `direction`/`orientation` values -- just like vanilla flamethrower
        # turrets.
        direction = int(8 * orientation)
        if direction:
            entity["direction"] = direction
        else:
            del entity["direction"]


#
# Currently this is not setable in a vanilla game. The mod
# https://mods.factorio.com/mod/QuickbarTemplates sets a tag
# into a constant-combinator. See:
#
# https://github.com/raiguard/Factorio-SmallMods/blob/master/QuickbarTemplates/control.lua#L81
#
def ep_tags(stream, index, entity):
    has_tags = stream.bool();
    if has_tags:
        tags = {}
        # Strange: Although this is conceptually the same as a tag dictionary
        # a different encoding is used. Since this encoding is simpler it is
        # a pitty that the next layers are encoded more convolutly.
        count = stream.count()
        for i in range(count):
            key = stream.string()
            value = read_tag_property_tree(stream)
            tags[key] = value
        entity["tags"] = tags


################################################################
#
# entity handlers (eh_*)

def eh_container(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_v1_1_62_5_flag(stream, index, entity)

    # restriction aka. "bar"
    ep_bar(stream, index, entity)

    # circuit connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        ep_circuit_connections(stream, index, entity)


def eh_logistic_container(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_v1_1_62_5_flag(stream, index, entity)

    # restriction aka. "bar"
    ep_bar(stream, index, entity)

    stream.expect(0x00)

    # request filters and "request from buffers"
    has_logistic_settings = stream.bool()
    if has_logistic_settings:
        ep_logistic_settings(stream, index, entity)
        stream.expect(0x00, 0x00)

    # circuit connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        ep_circuit_connections(stream, index, entity)
        mode_of_operation = stream.u8()
        if mode_of_operation:
            control_behavior = entity.setdefault("control_behavior", {})
            control_behavior["circuit_mode_of_operation"] = mode_of_operation


def eh_infinity_container(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_v1_1_62_5_flag(stream, index, entity)

    # restriction aka. "bar"
    ep_bar(stream, index, entity)

    stream.expect(0x00)

    # request filters and "request from buffers"
    has_logistic_settings = stream.bool()
    if has_logistic_settings:
        ep_logistic_settings(stream, index, entity)
        stream.expect(0x00, 0x00)

    # circuit connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        ep_circuit_connections(stream, index, entity)
        mode_of_operation = stream.u8()
        if mode_of_operation:
           control_behavior = entity.setdefault("control_behavior", {})
           control_behavior["circuit_mode_of_operation"] = mode_of_operation

    # infinity settings
    entity["infinity_settings"] = {}

    filters = []
    filter_count = stream.count()
    for f in range(filter_count):
        item_name = read_name(stream, index, Index.ITEM)
        item_count = stream.u32()
        mode = stream.mapped_u8("at-least", "at-most", "exactly")
        filters.append({
            "index": f + 1,
            "name": item_name,
            "count": item_count,
            "mode": mode
        })
    if filters:
        entity["infinity_settings"]["filters"] = filters

    remove_unfiltered_items = stream.bool()
    entity["infinity_settings"]["remove_unfiltered_items"] = remove_unfiltered_items


def eh_storage_tank(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    # circuit network connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)


def eh_transport_belt(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    # circuit network connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:

        # connections
        ep_circuit_connections(stream, index, entity)

        # circuit condition & logistic condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        stream.expect(0x00, 0x00)

        # mode of operation (specific for transport-belt)
        # maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.control_behavior
        control_behavior = entity.setdefault("control_behavior", {})

        circuit_enable_disable = stream.bool()
        control_behavior["circuit_enable_disable"] = circuit_enable_disable

        circuit_read_hand_contents = stream.bool()
        control_behavior["circuit_read_hand_contents"] = circuit_read_hand_contents

        circuit_contents_read_mode = stream.u8()
        control_behavior["circuit_contents_read_mode"] = circuit_contents_read_mode

        # really strange stuff
        stream.expect(0xff, 0xff, 0xff, 0xff)
        stream.expect(0xff, 0xff, 0xff, 0xff)


def eh_underground_belt(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)
    type = stream.mapped_u8("input", "output")
    entity["type"] = type


def eh_splitter(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    priorities = stream.u8()

    # "explanation": masks
    # => 0x10	-> output prio enabled
    # => 0x20	-> input priority enabled
    # => 0x0c	-> input priority left
    # => 0x03	-> output priority left
    # strange thing: why two bits for both 0x0c and 0x03?

    priority_mapping = {
        0x00 : [None, None],
        0x10 : [None, "right"],
        0x13 : [None, "left"],
        0x20 : ["right", None],
        0x2c : ["left", None],
        0x30 : ["right", "right"],
        0x33 : ["right", "left"],
        0x3c : ["left", "right"],
        0x3f : ["left", "left"]
    }

    mapped_priorities = priority_mapping[priorities]
    if not mapped_priorities:
        raise ParseError(f"unexpected splitter priority code {priorities:#04x}")
    input_priority, output_priority = mapped_priorities

    if input_priority:
        entity["input_priority"] = input_priority
    if output_priority:
        entity["output_priority"] = output_priority

    filter_name = read_name(stream, index, Index.ITEM)
    if filter_name:
        entity["filter"] = filter_name


def eh_inserter(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    # 0x01 -- override_stack_size
    # 0x02 -- filter_mode: 0=blacklist, 1(default)=whitelist
    # 0x04 -- TODO - unknown - default=1(?)
    # others: TODO - unknown - default=0(?)
    flags = stream.u8()
    if flags | 0x03 != 0x07:
        file_position = stream.tell() - 1
        raise ParseError(f"unexpected flag {flags:#04x} at {file_position} ({file_position:#x})")

    # direction
    ep_direction(stream, index, entity)

    # override stack size
    if flags & 0x01:
        entity["override_stack_size"] = stream.u8()

    # circuit network connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # circuit condition & logistic condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        stream.expect(0x00, 0x00)

        # mode of operation

        control_behavior = entity.setdefault("control_behavior", {})

        # maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.control_behavior
        mode_of_operation = stream.u8()
        if mode_of_operation:
            control_behavior["circuit_mode_of_operation"] = mode_of_operation

        read_hand_flag = stream.bool()
        read_hand_mode = stream.bool() # not a bool but only 0/1 allowed
        if read_hand_flag:
            control_behavior["circuit_read_hand_contents"] = True
        if read_hand_mode:
            control_behavior["circuit_hand_read_mode"] = 1

        set_stack_size = stream.bool()
        if set_stack_size:
            control_behavior["circuit_set_stack_size"] = True
        stack_control_input_signal = read_signal(stream, index)
        if stack_control_input_signal:
            control_behavior["stack_control_input_signal"] = stack_control_input_signal

        if not control_behavior:
            del entity["control_behavior"]

        # End of "mode of operation"

    # item filters
    ep_filters(stream, index, entity)

    if not flags & 0x02:
        entity["filter_mode"] = "blacklist"

    # pickup/drop position
    is_miniloader = stream.bool()
    if is_miniloader:
        # examples: miniloader mod
        entity["drop_position"] = {
            "x": stream.f64(),
            "y": stream.f64()
        }
        entity["pickup_position"] = {
            "x": stream.f64(),
            "y": stream.f64()
        }
        normalize_position(entity["drop_position"])
        normalize_position(entity["pickup_position"])


def eh_electric_pole(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    # v1.1.0:
    #   > Power pole connections are saved in the blueprint.
    #   > They still auto connect to other poles outside the blueprint.
    # https://wiki.factorio.com/Version_history/1.1.0#1.1.0
    if version >= V_1_1_0_0:
        # Strange: first and only zero-terminated list.
        # Even stranger: first and only  occurence of an implicitly
        # terminated list!
        # Fun fact: poles cannot have more than 5 wired in the game (at least
        # pole to pole. Check pole-to-switch!)
        neighbours = []
        next_neighbour = stream.u32()
        while next_neighbour:
            neighbours.append(next_neighbour)
            if len(neighbours) >= 5:
                break
            next_neighbour = stream.u32()
        if neighbours:
           entity["neighbours"] = neighbours
    else:
        stream.expect(*[0x00]*4)

    # circuit network connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        ep_circuit_connections(stream, index, entity)

    # TODO: This applies only to power-switches, but the export
    # mentions these connections only on the side of the switch.
    # Normal circuit connections are listed in the export on both
    # sides.
    peer_count = stream.count8()
    for p in range(peer_count):
        peer_id = stream.u32()
        circuit_id = stream.u8()


def eh_pipe(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)


def eh_pipe_to_ground(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)


def eh_pump(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    stream.expect(*[0x00]*20)
    stream.expect(0x01, 0x00, 0x00, 0x00, 0x01)

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # circuit condition & logistic condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)
        stream.expect(0x00, 0x00)


def eh_straight_rail(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)


def eh_curved_rail(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)


def eh_train_stop(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    station = stream.string()
    entity["station"] = station

    ep_direction(stream, index, entity)

    set_trains_limit = False
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # circuit condition & logistic condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        stream.expect(0x00, 0x00)

        circuit_enable_disable = stream.bool()
        send_to_train = stream.bool()
        read_from_train = stream.bool()
        read_stopped_train = stream.bool()

        control_behavior = entity.setdefault("control_behavior", {})
        if read_from_train:
            control_behavior["read_from_train"] = True
        if circuit_enable_disable:
            control_behavior["circuit_enable_disable"] = True

        # "true" is the silent default
        if not send_to_train:
            control_behavior["send_to_train"] = False

        # Why two flags (read_stopped_train and train_stopped_flag)?
        if read_stopped_train:
            control_behavior["read_stopped_train"] = True
        # since v1.1.19 this flag seems to be stuck at 0x01
        train_stopped_flag = stream.bool()
        train_stopped_signal = read_signal(stream, index)
        if train_stopped_flag:
            control_behavior["train_stopped_signal"] = train_stopped_signal

        stream.expect(*[0x00]*4)

        if version >= STABLE_V_1_1:
            read_trains_count = stream.bool()
            trains_count_signal = read_signal(stream, index)
            if read_trains_count:
                control_behavior["read_trains_count"] = read_trains_count
                control_behavior["trains_count_signal"] = trains_count_signal

            set_trains_limit = stream.bool()
            trains_limit_signal = read_signal(stream, index)
            if set_trains_limit:
                control_behavior["set_trains_limit"] = set_trains_limit
                control_behavior["trains_limit_signal"] = trains_limit_signal

    ep_color(stream, index, entity)

    if version >= STABLE_V_1_1:
        # -1: unset, so 0 is a valid value
        manual_trains_limit = stream.s32()
        # strange: First time information (set_trains_limit) of an optional
        #   block is needed outside that block. And just for filtering a value!
        if manual_trains_limit >= 0 and not set_trains_limit:
            entity["manual_trains_limit"] = manual_trains_limit
        stream.expect(0x00)


def eh_rail_signal(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        control_behavior = entity.setdefault("control_behavior", {})

        circuit_close_signal = stream.bool()
        control_behavior["circuit_close_signal"] = circuit_close_signal

        circuit_read_signal = stream.bool()
        control_behavior["circuit_read_signal"] = circuit_read_signal

        # TODO: similar to signals in roboport
        def encode_color_signal(default_name, key):
            value = read_signal(stream, index)
            if value and (value["type"] != "virtual" or value["name"] != default_name):
                control_behavior[key] = value

        encode_color_signal("signal-red", "red_output_signal")
        encode_color_signal("signal-yellow", "orange_output_signal")
        encode_color_signal("signal-green", "green_output_signal")

        ep_circuit_condition(stream, index, entity)

        stream.expect(0x00)


def eh_rail_chain_signal(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    if version >= STABLE_V_1_1:
        # strange: a new flag for nothing visible?
        stream.expect(0x01)

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        control_behavior = entity.setdefault("control_behavior", {})

        # TODO: similar to signals in roboport
        def encode_color_signal(default_name, key):
            value = read_signal(stream, index)
            if value and (value["type"] != "virtual" or value["name"] != default_name):
                control_behavior[key] = value

        encode_color_signal("signal-red", "red_output_signal")
        encode_color_signal("signal-yellow", "orange_output_signal")
        encode_color_signal("signal-green", "green_output_signal")
        encode_color_signal("signal-blue", "blue_output_signal")

        if not control_behavior:
            del entity["control_behavior"]


def eh_locomotive(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00, 0x01)
    stream.expect(0x00)

    ep_orientation(stream, index, entity)

    ep_railway_vehicle_common(stream, index, entity)

    ep_color(stream, index, entity)

    stream.expect(*[0x00]*6)


def eh_cargo_wagon(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00, 0x01)
    stream.expect(0x00)
    ep_orientation(stream, index, entity)

    ep_railway_vehicle_common(stream, index, entity)

    # Wagon colors cannot be set in the UI. Mods can.
    # But other wagons (fluid, artillery) don't support them.
    ep_color(stream, index, entity)

    stream.expect(*[0x00]*5)

    inventory = entity.setdefault("inventory", {})

    ep_filters(stream, index, inventory)

    # "filters" and "bar" are wrapped into "inventory".
    # But `ep_bar` actualle requires a real entity argument. :-(
    # TODO: better handling
    ep_bar(stream, index, entity)
    bar = entity.get("bar")
    if bar:
        inventory["bar"] = bar
        del entity["bar"]
    if not inventory:
        entity["inventory"] = None


def eh_fluid_wagon(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00, 0x01)
    stream.expect(0x00)
    ep_orientation(stream, index, entity)

    ep_railway_vehicle_common(stream, index, entity)

    stream.expect(*[0x00]*32)


def eh_artillery_wagon(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00, 0x01)
    stream.expect(0x00)
    ep_orientation(stream, index, entity)

    ep_railway_vehicle_common(stream, index, entity)

    stream.expect(*[0x00]*10)
    stream.expect(0x00, 0x00, 0x80, 0x3f) # 1.0f
    stream.expect(*[0x00]*21)
    stream.expect(0xff, 0x7f) # s16: max. positive value
    stream.expect(0xff, 0xff, 0xff, 0x7f) # s32: max. positive value
    stream.expect(0xff, 0xff, 0xff, 0x7f) # s32: max. positive value

    stream.expect(*[0x00]*13)
    stream.expect(0xff, 0xff, 0xff, 0x7f) # s32: max. positive value
    stream.expect(0xff, 0xff, 0xff, 0x7f) # s32: max. positive value
    stream.expect(*[0x00]*8)
    stream.expect(0x03)
    stream.expect(*[0x00]*8)
    stream.expect(0x01, 0x00)
    stream.expect(0x00, 0x00, 0x80, 0x3f) # 1.0f
    stream.expect(*[0x00]*18)


def eh_roboport(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        control_behavior = {}

        # flags and signals
        read_logistics = stream.bool()
        if not read_logistics:
            control_behavior["read_logistics"] = False

        read_robot_stats = stream.bool()
        if read_robot_stats:
            control_behavior["read_robot_stats"] = True

        def roboport_signal(default_signal, key):
            signal = read_signal(stream, index)
            # map None to a special "empty" signal
            if not signal:
                signal = { "type": "item" }
            # default_signal is not written
            if read_robot_stats and signal != { "type": "virtual", "name": default_signal }:
                control_behavior[key] = signal

        roboport_signal("signal-X", "available_logistic_output_signal")
        roboport_signal("signal-Y", "total_logistic_output_signal")
        roboport_signal("signal-Z", "available_construction_output_signal")
        roboport_signal("signal-T", "total_construction_output_signal")

        if control_behavior:
            entity["control_behavior"] = control_behavior


def eh_lamp(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        #connections
        ep_circuit_connections(stream, index, entity)

        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        # Strange: Why a copy of the previous flag?
        # Strange: Why only for lamps? All other relevant entities also have
        #   two bytes free here.
        # Neither of these provides any hints:
        # https://lua-api.factorio.com/latest/LuaControlBehavior.html#LuaLampControlBehavior.brief
        # https://lua-api.factorio.com/latest/LuaControlBehavior.html#LuaGenericOnOffControlBehavior.brief
        logistic_connected_copy = stream.bool()
        logistic_connected = entity.get("control_behavior", {}).get("connect_to_logistic_network", False)
        if logistic_connected != logistic_connected_copy:
            raise ParseError(f"different value 'connect_to_logistic_network' ({logistic_connected}) and its special copy for lamps ({logistic_connected_copy})")

        stream.expect(0x00)

        use_colors = stream.bool()
        if use_colors:
            control_behavior = entity.setdefault("control_behavior", {})
            control_behavior["use_colors"] = True


def eh_arithmetic_combinator(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    # connections
    ep_circuit_connections(stream, index, entity, "1")
    ep_circuit_connections(stream, index, entity, "2")

    # condition
    first_signal = read_signal(stream, index)
    second_signal = read_signal(stream, index)
    output_signal = read_signal(stream, index)
    second_constant = stream.s32()
    operation = stream.mapped_u8("*", "/", "+", "-", "%", "^", "<<", ">>", "AND", "OR", "XOR")
    use_second_constant = stream.bool()
    first_constant = stream.s32()
    use_first_constant = stream.bool()

    control_behavior = entity["control_behavior"] = {}
    conditions =  control_behavior["arithmetic_conditions"] = {}

    conditions["operation"] = operation

    if use_first_constant:
        conditions["first_constant"] = first_constant
    elif first_signal:
        conditions["first_signal"] = first_signal

    if use_second_constant:
        conditions["second_constant"] = second_constant
    elif second_signal:
        conditions["second_signal"] = second_signal

    if output_signal:
        conditions["output_signal"] = output_signal


def eh_decider_combinator(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    # connections
    ep_circuit_connections(stream, index, entity, "1")
    ep_circuit_connections(stream, index, entity, "2")

    # condition
    first_signal = read_signal(stream, index)
    second_signal = read_signal(stream, index)
    output_signal = read_signal(stream, index)
    second_constant = stream.s32()
    comparator = stream.mapped_u8(">", "<", "=", "≥", "≤", "≠")

    copy_count_from_input = stream.bool()
    use_constant = stream.bool()

    control_behavior = entity["control_behavior"] = {}
    conditions = control_behavior["decider_conditions"] = {}

    conditions["comparator"] = comparator
    if first_signal:
        conditions["first_signal"] = first_signal

    if use_constant:
        conditions["constant"] = second_constant
    elif second_signal:
        conditions["second_signal"] = second_signal

    if output_signal:
        conditions["output_signal"] = output_signal

    conditions["copy_count_from_input"] = copy_count_from_input


def eh_constant_combinator(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    # circuit connections
    ep_circuit_connections(stream, index, entity)

    control_behavior = None

    # filters
    filters = []
    filter_count = stream.count32()
    for f in range(filter_count):
        signal = read_signal(stream, index)
        count = stream.s32()
        if signal:
            filters.append({
                "index": f + 1,
                "signal": signal,
                "count": count
            })
    if filters:
        control_behavior = entity.setdefault("control_behavior", {})
        # Export: Why "filter"? These are not filters.
        control_behavior["filters"] = filters

    is_on = stream.bool()
    if not is_on:
        control_behavior = entity.setdefault("control_behavior", {})
        control_behavior["is_on"] = False

    ep_direction(stream, index, entity)


def eh_power_switch(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    # v1.1.4:
    #   > Power switch will now save it's on/off state in blueprints and
    #   > the state can also be copy-pasted between power switches.
    #   https://wiki.factorio.com/Version_history/1.1.0#1.1.4
    if version >= V_1_1_4_0:
        switch_state = stream.bool()
        entity["switch_state"] = switch_state
    else:
        stream.expect(0x00)

    stream.expect(*[0x00]*12)

    connections = {}

    # Contrary to circuit-connections there is no counter/list and therefore
    # at most one wire can connect to each side. On the other hand the
    # export format has exactly lists in place. *shrug*
    # On the other hand the switch misses one structural level. *sigh*
    connection_cu0 = stream.u32()
    if connection_cu0:
        # Strange: Caps-key are unusual!
        connections["Cu0"] = [
            {
                "entity_id": connection_cu0,
                "wire_id": 0
            }
        ]

    connection_cu1 = stream.u32()
    if connection_cu1:
        # Strange: Caps-key are unusual!
        connections["Cu1"] = [
            {
                "entity_id": connection_cu1,
                "wire_id": 0
            }
        ]

    if connections:
        entity["connections"] = connections

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        stream.expect(0x00, 0x00)


def eh_programmable_speaker(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    # https://lua-api.factorio.com/latest/Concepts.html#ProgrammableSpeakerParameters
    entity["parameters"] = {
        "playback_volume": normalize_float(stream.f64()),
        "playback_globally": stream.bool(),
        "allow_polyphony": stream.bool(),
    }

    # https://lua-api.factorio.com/latest/Concepts.html#ProgrammableSpeakerAlertParameters
    alert_parameters = entity["alert_parameters"] = {
        "show_alert": stream.bool(),
        "show_on_map": stream.bool(),
        "icon_signal_id": read_signal(stream, index),
        "alert_message": stream.string(),
    }
    if not alert_parameters["icon_signal_id"]:
        del alert_parameters["icon_signal_id"]

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # condition
        ep_circuit_condition(stream, index, entity)

        # https://lua-api.factorio.com/latest/Concepts.html#ProgrammableSpeakerCircuitParameters
        control_behavior = entity.setdefault("control_behavior", {})
        control_behavior["circuit_parameters"] = {
            "signal_value_is_pitch": stream.bool(),
            "instrument_id": stream.u32(),
            "note_id": stream.u32(),
        }


def eh_boiler(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)


def eh_generator(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(*[0x00]*28)
    ep_direction(stream, index, entity)


def eh_solar_panel(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)


def eh_accumulator(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(*[0x00]*13)

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # output signal
        output_signal = read_signal(stream, index)
        control_behavior = entity["control_behavior"] = {
            "output_signal": output_signal
        }


def eh_reactor(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(*[0x00]*2)


def eh_heat_pipe(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(0x00)


def eh_mining_drill(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    stream.expect(*[0x00]*36)

    is_pumpjack = stream.bool()     # 1 for pumpjack, 0 otherwise

    stream.expect(0x00)

    # circuit network connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # circuit condition & logistic condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        stream.expect(0x00, 0x00)

        # mode of operation (specific for mining drill)

        # maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.control_behavior

        control_behavior = entity.setdefault("control_behavior", {})

        control_behavior["circuit_enable_disable"] = stream.bool()
        control_behavior["circuit_read_resources"] = stream.bool()

        stream.expect(0x00)

        control_behavior["circuit_resource_read_mode"] = stream.u8()

        stream.expect(0x00)


def eh_offshore_pump(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    stream.expect(*[0x00]*4)

    # circuit network connections
    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        # circuit condition & logistic condition
        ep_circuit_condition(stream, index, entity)
        ep_logistic_condition(stream, index, entity)

        stream.expect(0x00, 0x00)


def eh_furnace(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(*[0x00]*2)

    # Vanilla furnaces cannot be rotated in game. Importing a manipulating
    # the blueprint string *does* write the direction into this field. But
    # re-exporting the blueprint will not contain the direction any more.
    # Modded entities like a "flare stack" from "Angel's Petrochemical
    # Processing" however can be rotated in game and are roundtrip-capable.
    ep_direction(stream, index, entity)

    stream.expect(*[0x00]*2)


def eh_assembling_machine(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    recipe = read_name(stream, index, Index.RECIPE)
    if recipe:
        entity["recipe"] = recipe

    ep_direction(stream, index, entity)


def eh_lab(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(*[0x00]*23)


def eh_beacon(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x3f) # 1.0d
    stream.expect(*[0x00]*8)


def eh_land_mine(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x01) # Strange: Why is that value "1" HERE!
    stream.expect(0x78, 0x00, 0x00, 0x00)


def eh_wall(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(0x00)

    has_circuit_connections = stream.bool()
    if has_circuit_connections:
        # connections
        ep_circuit_connections(stream, index, entity)

        control_behavior = entity["control_behavior"] = {}
        control_behavior["circuit_open_gate"] = stream.bool()
        control_behavior["circuit_read_sensor"] = stream.bool()

        # TODO: Similar to signals in roboport. Examine "empty" signal encoding!
        output_signal = read_signal(stream, index)
        if output_signal != { "type": "virtual", "name": "signal-G" }:
            control_behavior["output_signal"] = output_signal

        ep_circuit_condition(stream, index, entity)
        stream.expect(0x00)


def eh_gate(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    stream.expect(0x00, 0x00, 0x80, 0x3f)    # 1.0f
    stream.expect(*[0x00]*9)


def eh_ammo_turret(stream, index, entity):
    ep_turret_common(stream, index, entity)

    # same for ammo-turret and electric-turret:
    stream.expect(*[0x00]*12)
    ep_direction(stream, index, entity)
    stream.expect(*[0x00]*16)
    stream.expect(0xff, 0xff, 0xff, 0xff)
    stream.expect(*[0x00]*4)

    # `gun-turrets` store the special fixed value `8` in `direction` and no
    # `orientation` by default.
    # They export *neither* field! On import only `direction` is read and
    # the equivalent `orientation` value is stored.
    # Modded turrets like `shotgun-ammo-turret-rampant-arsenal` (Warptorio)
    # managed to store synchronized values in both fields though.
    fixup_turret_direction(stream, index, entity)


def eh_electric_turret(stream, index, entity):
    ep_turret_common(stream, index, entity)

    # same for ammo-turret and electric-turret:
    stream.expect(*[0x00]*12)
    ep_direction(stream, index, entity)
    stream.expect(*[0x00]*16)
    stream.expect(0xff, 0xff, 0xff, 0xff)
    stream.expect(*[0x00]*4)

    # The `laser-turret` behaves like the vanilla `gun-turret`.
    fixup_turret_direction(stream, index, entity)


def eh_fluid_turret(stream, index, entity):
    ep_turret_common(stream, index, entity)

    stream.expect(*[0x00]*12)
    ep_direction(stream, index, entity)
    stream.expect(*[0x00]*16)
    stream.expect(0xff, 0xff, 0xff, 0xff)
    stream.expect(*[0x00]*19)

    # The vanilla `flamethrower-turret` stores synchronized
    # `direction` and `orientation` fields and also exports
    # and imports the `direction` field. So an export/import
    # roundtrip is possible without any loss.
    fixup_turret_direction(stream, index, entity)


def eh_artillery_turret(stream, index, entity):
    ep_turret_common(stream, index, entity)

    stream.expect(0xff, 0x7f)
    stream.expect(0xff, 0xff, 0xff, 0x7f)
    stream.expect(0xff, 0xff, 0xff, 0x7f)
    stream.expect(*[0x00]*5)

    ep_direction(stream, index, entity)

    stream.expect(*[0x00]*8)
    stream.expect(0xff, 0xff, 0xff, 0x7f)
    stream.expect(0xff, 0xff, 0xff, 0x7f)
    stream.expect(*[0x00]*8)
    stream.expect(0x03)
    stream.expect(*[0x00]*8)
    stream.expect(0x01, 0x00)
    stream.expect(0x00, 0x00, 0x80, 0x3f) #1.0f
    stream.expect(*[0x00]*18)

    # The vanilla `artillery-turret` stores, exports and imports the
    # `direction` field making lossless roundtrips possible. The
    # `orientation` field is always pinned to `0.0`.
    fixup_turret_direction(stream, index, entity)


def eh_radar(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x01) # Strange: Why is that value "1" HERE!
    stream.expect(*[0x00]*16)
    stream.expect(0x9a, 0x99, 0x19, 0x3e) # 0.15f
    stream.expect(0x00)


def eh_rocket_silo(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    recipe = read_name(stream, index, Index.RECIPE)
    if recipe:
        entity["recipe"] = recipe

    stream.expect(*[0x00]*59)

    auto_launch = stream.bool()
    if auto_launch:
        entity["auto_launch"] = True


def eh_loader(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    type = stream.mapped_u8("input", "output")
    entity["type"] = type

    stream.expect(*[0x00]*4)
    ep_filters(stream, index, entity)


def eh_loader_1x1(stream, index, entity):
    eh_loader(stream, index, entity)


def eh_electric_energy_interface(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    power_production = stream.f64()
    # strange default
    if power_production != 1e11 / 12:
        entity["power_production"] = normalize_float(power_production)

    power_usage = stream.f64()
    if power_usage:
        entity["power_usage"] = normalize_float(power_usage)

    stream.expect(*[0x00]*8)

    # strange place for "direction"
    ep_direction(stream, index, entity)

    stream.expect(*[0x00]*4)

    buffer_size = stream.f64()
    entity["buffer_size"] = normalize_float(buffer_size)

    stream.expect(*[0x00]*8)


def eh_infinity_pipe(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    fluid_name = read_name(stream, index, Index.FLUID)
    percentage = stream.f64()
    temperature = stream.f64()
    # "add"/"remove" are valid since v1.1.33:
    # https://wiki.factorio.com/Version_history/1.1.0#1.1.33
    mode = stream.mapped_u8("at-least", "at-most", "exactly", "add", "remove")

    if fluid_name:
        entity["infinity_settings"] = {
            "name": fluid_name,
            "percentage": normalize_float(percentage),
            "temperature": normalize_float(temperature),
            "mode": mode
        }


def eh_heat_interface(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    temperature = stream.f64()
    entity["temperature"] = normalize_float(temperature)

    # "add"/"remove" are valid since v1.1.33:
    # https://wiki.factorio.com/Version_history/1.1.0#1.1.33
    mode = stream.mapped_u8("at-least", "at-most", "exactly", "add", "remove")
    entity["mode"] = mode


# since v1.1.19
def eh_linked_belt(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    ep_direction(stream, index, entity)

    type = stream.mapped_u8("input", "output")
    entity["type"] = type

    belt_link = stream.u32()
    if belt_link:
        entity["belt_link"] = belt_link


# since v1.1.19
def eh_linked_container(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)

    link_id = stream.u32()
    entity["link_id"] = link_id

    ep_v1_1_62_5_flag(stream, index, entity)


# reachable via map editor or infinity-chest
def eh_burner_generator(stream, index, entity):
    ep_v1_1_51_4_flag(stream, index, entity, 0x00)
    stream.expect(*[0x00]*12)
    ep_direction(stream, index, entity)


entity_handlers = {
    # Logistics
    "container": eh_container,
    "logistic-container": eh_logistic_container,
    "infinity-container": eh_infinity_container,
    "storage-tank": eh_storage_tank,
    "transport-belt": eh_transport_belt,
    "underground-belt": eh_underground_belt,
    "splitter": eh_splitter,
    "inserter": eh_inserter,
    "electric-pole": eh_electric_pole,
    "pipe": eh_pipe,
    "pipe-to-ground": eh_pipe_to_ground,
    "pump": eh_pump,
    "straight-rail": eh_straight_rail,
    "curved-rail": eh_curved_rail,
    "train-stop": eh_train_stop,
    "rail-signal": eh_rail_signal,
    "rail-chain-signal": eh_rail_chain_signal,
    "locomotive": eh_locomotive,
    "cargo-wagon" : eh_cargo_wagon,
    "fluid-wagon": eh_fluid_wagon,
    "artillery-wagon": eh_artillery_wagon,
    "roboport": eh_roboport,
    "lamp": eh_lamp,
    "arithmetic-combinator": eh_arithmetic_combinator,
    "decider-combinator": eh_decider_combinator,
    "constant-combinator": eh_constant_combinator,
    "power-switch": eh_power_switch,
    "programmable-speaker": eh_programmable_speaker,
    # Production
    "boiler": eh_boiler,
    "generator": eh_generator,
    "solar-panel": eh_solar_panel,
    "accumulator": eh_accumulator,
    "reactor": eh_reactor,
    "heat-pipe": eh_heat_pipe,
    "mining-drill": eh_mining_drill,
    "offshore-pump": eh_offshore_pump,
    "furnace": eh_furnace,
    "assembling-machine": eh_assembling_machine,
    "lab": eh_lab,
    "beacon": eh_beacon,
    # Combat
    "land-mine": eh_land_mine,
    "wall": eh_wall,
    "gate": eh_gate,
    "ammo-turret": eh_ammo_turret,
    "electric-turret": eh_electric_turret,
    "fluid-turret": eh_fluid_turret,
    "artillery-turret": eh_artillery_turret,
    "radar": eh_radar,
    "rocket-silo": eh_rocket_silo,
    # Infinity / Cheat Mode
    "loader": eh_loader,
    "loader-1x1": eh_loader_1x1,
    "electric-energy-interface": eh_electric_energy_interface,
    "infinity-pipe": eh_infinity_pipe,
    "heat-interface": eh_heat_interface,
    "linked-belt": eh_linked_belt,
    "linked-container": eh_linked_container,
    # not reachable in normal game but e.g. in the map editor
    "burner-generator": eh_burner_generator,
}


################################################################
#
# library -- utilities

def parse_version(stream, result):
    version = (
        stream.u16(),
        stream.u16(),
        stream.u16(),
        stream.u16(),
    )
    debug(f"version: {'.'.join(map(str, version))}")
    result["version"] = Version(*version)
    if opt.x:
        result["_version_"] = version


def parse_migrations(stream, result):
    migrations = []
    migration_count = stream.count8()
    if opt.x:
        debug(f"migrations: {migration_count}")
    for m in range(migration_count):
        mod_name = stream.string()
        migration_file = stream.string()
        if opt.x:
            debug(f"    [{m}] mod '{mod_name}', migration '{migration_file}'")
        migrations.append({
            "mod_name": mod_name,
            "migration_file": migration_file
        })
    if opt.x:
        result["migrations"] = migrations


def parse_index(stream, result):
    index = Index()
    index_dict = {}

    prototype_count = stream.count16()
    debug(f"used prototypes: {prototype_count}")
    for p in range(prototype_count):
        prototype_name = stream.string()
        names = index_dict[prototype_name] = {}
        if prototype_name == "tile":    # strange exception
            name_count = stream.count8()
            debug(f"    [{p}] prototype '{prototype_name}' - entries: {name_count}")
            for n in range(name_count):
                name_id = stream.u8()
                name = stream.string()
                debug(f"        [{n}] {name_id:02x} '{name}'")
                names[name_id] = name
                index.add(name_id, prototype_name, name)
        else:
            name_count = stream.count16()
            debug(f"    [{p}] prototype '{prototype_name}' - entries: {name_count}")
            for n in range(name_count):
                name_id = stream.u16()
                name = stream.string()
                debug(f"        [{n}] {name_id:04x} '{name}'")
                names[name_id] = name
                index.add(name_id, prototype_name, name)

    if index_dict and opt.x:
        result["index"] = index_dict

    return index


# Strange: Why the inconsistency between `-` vs. `_` and `*planner` vs. `*item`?
# Strange: Why another piece of information alltogether?
object_prototypes = (
    dict(key="blueprint", prototype="blueprint"),
    dict(key="blueprint_book", prototype="blueprint-book"),
    dict(key="deconstruction_planner", prototype="deconstruction-item"),
    dict(key="upgrade_planner", prototype="upgrade-item"),
)

def parse_library_objects(stream, index, result, library_version):

    object_count = stream.count32()
    verbose(f"\nlibrary objects: {object_count}")
    objects = []
    for o in range(object_count):
        is_used = stream.bool()
        if is_used:
            verbose(f"\n[{o}] library slot: used")

            # Strange: Here is a rare redundancy with the prototype.
            prefix = stream.mapped_u8(*object_prototypes)

            # See _generation_counter_ in parse_blueprint_library for details.
            generation = stream.u32()

            entry = read_entry(stream, index, Index.ITEM)
            if not entry:
                file_position = stream.tell() - 2
                raise ParseError(f"found item ID 0x0000 at {file_position} ({file_position:#x}) where a real ID is required.")

            if entry.prototype != prefix["prototype"]:
                raise ParseError(
                    f"mismatch between content-type '{prefix['prototype']}'"
                    f" and actual content item {entry.prototype}")

            handler = object_handlers.get(entry.prototype)
            if not handler:
                raise ParseError(f"no handler for {entry.prototype}/{entry.name} ({entry.id:#x})")

            handler_result = handler(stream, index, library_version)
            if handler_result:
                if opt.x:
                    handler_result["_generation_"] = generation
                objects.append({
                    # Strange: This index is zero-based, not one-based.
                    "index": o,
                    prefix["key"]: handler_result
                })
        else:
            verbose(f"\n[{o}] library slot: free")

    result["blueprints"] = objects


def parse_icons(stream, index, result):
    unknown_icons = []
    unknown_icons_count = stream.u8()
    for u in range(unknown_icons_count):
        name = stream.string()
        unknown_icons.append(name)

    icons = []
    icon_count = stream.count8()
    if not icon_count:
        return
    debug(f"icons: {icon_count}")
    for i in range(icon_count):
        icon = read_signal(stream, index)
        if icon:
            if unknown_icons[i:i+1]:
                icon["name"] = unknown_icons[i]
            debug(f"    [{i}] '{icon['type']}' / '{icon['name']}'")
            icons.append({
                "index": i + 1,
                "signal": icon
            })
        else:
            debug(f"    [{i}] (none)")
    if icons:
        result["icons"] = icons


def parse_snap_to_grid(stream, result):
    snap_to_grid = stream.bool()
    if snap_to_grid:
        result["snap-to-grid"] = {
            "x": stream.u32(),
            "y": stream.u32()
        }

        absolute_snapping = stream.bool()
        if absolute_snapping:
            result["absolute-snapping"] = absolute_snapping
            if version >= STABLE_V_1_1:
                relative = {
                    "x": stream.s32(),
                    "y": stream.s32()
                }
                if relative != {"x": 0, "y": 0}:
                    result["position-relative-to-grid"] = relative


def parse_entities(stream, index, result):
    entities = result["entities"] = []

    entity_count = stream.count32()
    debug(f"entities: {entity_count}")
    for e in range(entity_count):
        file_position = stream.tell()

        # type/name
        entry = read_entry(stream, index, Index.ENTITY)
        if not entry:
            raise ParseError(f"found entity ID 0x0000 at {stream.tell()-2:#x} where a real ID is required.")

        # position

        # maybe helpfull: https://wiki.factorio.com/Data_types
        # maybe helpfull: https://wiki.factorio.com/Types/Position
        offset_x = stream.s16()     # lookahead
        if offset_x == 0x7fff:
            position = {
                "x": stream.s32() / 256,
                "y": stream.s32() / 256
            }
        else:
            offset_y = stream.s16()
            if entities:
                last_position = entities[-1]["position"]
                position = {
                    "x": last_position["x"] + offset_x / 256,
                    "y": last_position["y"] + offset_y / 256
                }
            else:
                position = {
                    "x": offset_x / 256,
                    "y": offset_y / 256
                }

        normalize_position(position)

        # debug output
        debug(f"    [{len(entities)}] @{file_position:#x} - "
            f"x: {position['x']}, y: {position['y']}, "
            f"'{entry.prototype}/{entry.name}' ({entry.id:#06x})")

        # attach entity
        entity = {
            "entity_number": e + 1,
            "name": entry.name,
            "position": position,
        }
        entities.append(entity)

        # Strange: What is this?
        stream.expect(0x20)

        # entity ids
        ep_entity_id(stream, index, entity)

        # parse entity details
        handler = entity_handlers.get(entry.prototype)
        if not handler:
            raise ParseError(f"no entity handler for {entry.prototype}/{entry.name} ({entry.id:#x})")
        handler(stream, index, entity)

        # vanilla: modules, fuel; mods&co: ammo, ...
        ep_items(stream, index, entity)

        ep_tags(stream, index, entity)

    if not entities:
        del result["entities"]


def parse_schedules(stream, index, result):
    schedules_count = stream.count8()
    schedules = []
    if schedules_count:
        debug(f"schedules: {schedules_count}")
    for sc in range(schedules_count):
        debug(f"    [{sc}] schedule:")
        schedule = {
            "schedule": []
        }

        locomotives = schedule["locomotives"] = []
        locomotive_count = stream.count8()
        debug(f"    locomotives: {locomotive_count}")
        for lo in range(locomotive_count):
            locomotive_id = stream.u32()
            if locomotive_id:
                debug(f"        {locomotive_id}")
                locomotives.append(locomotive_id)
            else:
                # Actually I cannot recreate the situation but there are two reports.
                # One of them contained NO train related stuff :-/
                debug(f"        {locomotive_id} (ignored)")

        # https://wiki.factorio.com/Blueprint_string_format#Schedule_Record_object
        # https://lua-api.factorio.com/latest/Concepts.html#TrainScheduleRecord
        station_count = stream.count8()
        debug(f"    stations: {station_count}")
        for st in range(station_count):
            station_position = stream.tell()
            station_name = stream.string()
            station = {
                "station": station_name,
            }
            debug(f"        [{st}] @{station_position:#x} '{station_name}'");

            # Strange 1: Only case where something else than a flag enables additional data.
            # Strange 2: The "temporary" flag down below would fit but can't be used for parsing (to late)
            if not station_name:
                # Release-Note  1.1.43:
                #       Added LuaEntity::connected_rail_direction read.
                #       Added TrainScheduleRecord::rail_direction.
                # see:
                #   https://lua-api.factorio.com/1.1.42/Concepts.html#TrainScheduleRecord
                #   https://lua-api.factorio.com/1.1.43/Concepts.html#TrainScheduleRecord
                if version < V_1_1_43_0:
                    # There seems to be no way to resolve this to anything recognizable.
                    # NOT canditates:
                    #   - entity_ids or indizes
                    #   - (short) coordinates
                    # Doesn't matter much because the export string also contains nothing.
                    stream.ignore(4, "rail")
                else:
                    # "rail" -- Seems to be pinned to zero now.
                    stream.expect(0x00, 0x00, 0x00, 0x00)
                    # "rail_direction"
                    stream.bool()

            # https://wiki.factorio.com/Blueprint_string_format#Wait_Condition_object
            # https://lua-api.factorio.com/latest/Concepts.html#WaitCondition
            wait_conditions = []
            wait_condition_count = stream.u32()
            for wc in range(wait_condition_count):
                wait_condition = {}

                wait_condition_types = (
                    "time",
                    "full",
                    "empty",
                    "item_count",
                    "circuit",
                    "inactivity",
                    "robots_inactive", # 1.0.0: not offered in UI
                    "fluid_count",
                    "passenger_present",
                    "passenger_not_present",
                )
                condition_type = wait_condition["type"] = stream.mapped_u8(*wait_condition_types)

                wait_condition["compare_type"] = stream.mapped_u8("and", "or")

                ticks = stream.u16()
                if ticks or condition_type in ("time", "inactivity"):
                    # Strange: The export features "ticks: 0" for "time" and "inactivity".
                    wait_condition["ticks"] = ticks

                stream.expect(0x00, 0x00)

                condition = read_condition(stream, index)
                if condition:
                    wait_condition["condition"] = condition

                wait_conditions.append(wait_condition)

            if wait_conditions:
                station["wait_conditions"] = wait_conditions

            # Strange: A rare redundancy between this flag and empty statiion name (see above).
            temporary = stream.bool()
            if temporary:
                station["temporary"] = True

            schedule["schedule"].append(station)

        if locomotives:
            schedules.append(schedule)
        else:
            debug(f"    skipping schedule -- no valid locomotives!")

    if schedules:
        result["schedules"] = schedules


def parse_tiles(stream, index, result):
    tiles = []
    tile_count = stream.count32()
    debug(f"tiles: {tile_count}")
    for t in range(tile_count):
        tiles.append({
            "position": {
                "x": stream.s32(),
                "y": stream.s32()
            },
            # FIXME: guard against 0x00 IDs
            "name": read_name(stream, index, Index.TILE)
        })

    if tiles:
        result["tiles"] = tiles


def fixup_entity_ids(blueprint):

    entities = blueprint.get("entities")
    if not entities:
        return

    # make mapping entity_id -> entity_number
    id_to_entity = {}
    for entity in entities:
        if "entity_id" in entity and "entity_number" in entity:
            entity_id = entity["entity_id"]
            del entity["entity_id"]
            id_to_entity[entity_id] = entity

    # apply mapping to all (remaining) occurrences of "entity_id" in
    # connections (color wires and copper wires) and trains schedules

    def walk(it):
        if isinstance(it, dict):
            # handle color- and copper wires in connections
            if "entity_id" in it:
                # update entity_id with value of entity_number
                peer = id_to_entity[it["entity_id"]]
                it["entity_id"] = peer["entity_number"]

                # delete "circuit_id: 1" if the peer has only one circuit
                if "circuit_id" in it:
                    peer_name = peer["name"]
                    # FIXME: what a hack!
                    if peer_name not in ("arithmetic-combinator", "decider-combinator"):
                        # TODO: check "prototype". not "name"
                        #   XOR: both combinator leave some sentinel value in their entity.
                        #   XOR: perhaps check the connections in peer: it may/must(?)
                        # TODO: check for circuit "1"
                        del it["circuit_id"]
            # handle train schedules
            if "locomotives" in it:
                it["locomotives"] = [ id_to_entity[l]["entity_number"] for l in it["locomotives"]]
            # handle electric pole wiring
            if "neighbours" in it:
                it["neighbours"] = [ id_to_entity[n]["entity_number"] for n in it["neighbours"]]
            # handle linked belt connections
            if "belt_link" in it:
                it["belt_link"] = id_to_entity[it["belt_link"]]["entity_number"]
            for value in it.values():
                walk(value)

        elif isinstance(it, list):
            for value in it:
                walk(value)

    walk(blueprint)


################################################################
#
# library -- primary objects

def parse_blueprint_library(stream: PrimitiveStream):
    result = {
        "blueprint_book": {
            "item": "blueprint-book",
            "blueprints": [],
            "version": None,
        }
    }

    book_item = result["blueprint_book"]

    parse_version(stream, book_item)
    library_version = book_item["version"]

    global version
    version = library_version

    if version < MINIMUM_VERSION:
        raise ParseError(f"Blueprint file format is too old: {version}. Minimum version is {MINIMUM_VERSION}. Sorry :-(")

    stream.expect(0x00)

    parse_migrations(stream, result)

    global_index = parse_index(stream, result)

    # unknown strange thing: mostly 0x00 but sometimes 0x03 and in one case
    # even 0x0e! So more probably a counter than some flags.
    stream.ignore(1, "library state(?)")

    stream.expect(0x00)

    # Adding a blueprint to the library increments the counter, deleting and moving does not.
    # When a new blueprint is added to the library this global counter is copied to the new
    # blueprint and incremened after that. This happens for each new blueprint, not per save.
    generation_counter = stream.u32()
    debug(f"generation counter: {generation_counter} ({generation_counter:#x})")
    if opt.x:
        result["_generation_counter_"] = generation_counter

    # unix timestamp
    timestamp = stream.u32()    # u32/s32?
    timestring = time.strftime("%FT%T%z", time.localtime(timestamp)) # localtime/gmtime?
    # FIXME: use datetime.fromtimestamp(timestamp, timezone.utc) or something like that
    debug(f"timestamp: {timestring}")
    if opt.x:
        result["_save_timestamp_"] = timestring

    stream.expect(0x01)

    parse_library_objects(stream, global_index, book_item, library_version)

    book_item["label"] = timestring
    book_item["description"] = \
        f"filename: {opt.filename}\n" \
        f"timestamp: {timestring}\n" \
        f"generation: {generation_counter}\n"

    return result


def parse_blueprint(stream: PrimitiveStream, index, library_version):
    result = {
        "item": "blueprint",
    }

    file_position = stream.tell()

    label = stream.string()
    if label:
        result["label"] = label
    verbose(f"blueprint '{label}' (@{file_position:#x})")

    stream.expect(0x00)

    has_removed_mods = stream.bool()

    # Interesting: A rare redundancy. Could be used to fast skimming
    # the library. Reasons: a) Speed, b) unparsable content due to mods/versions.
    content_size = stream.count()
    content_start = stream.tell()

    global version
    try:

        if has_removed_mods:
            verbose(f"    blueprint contains stuff from removed mods!")

            # Actually the local index is located AFTER the blueprint data.
            # So seek there. Bye bye streaming access :-[
            stream.seek(content_size, 1)

            # read local index
            index_size = stream.count()
            index_start = stream.tell()

            parse_version(stream, result)
            index_version = result["version"]
            version = index_version

            if version < MINIMUM_VERSION:
                raise ParseError(f"Blueprint index format is too old: {version}. Minimum version is {MINIMUM_VERSION}.")

            stream.expect(0x00)
            index = parse_index(stream, result)

            # check position
            index_end = stream.tell()
            parsed_size = index_end - index_start
            if parsed_size != index_size:
                raise AssertionError(f"mismatch between declared local index size ({index_size})"
                    f" and parsed index size ({parsed_size})")

            # seek back
            stream.seek(content_start, 0)

        parse_version(stream, result)
        blueprint_version = result["version"]
        version = blueprint_version
        # Note: The index version and the blueprint version CAN be different!
        # Encountered an index with version 1.0.0.0 and a blueprint with 0.18.29.0
        # inside a library of version 1.1.15.0

        if version < MINIMUM_VERSION:
            raise ParseError(f"Blueprint format is too old: {version}. Minimum version is {MINIMUM_VERSION}.")

        stream.expect(0x00)

        parse_migrations(stream, result)

        description = stream.string()
        if description:
            result["description"] = description

        parse_snap_to_grid(stream, result)

        parse_entities(stream, index, result)

        parse_schedules(stream, index, result)

        parse_tiles(stream, index, result)

        parse_icons(stream, index, result)

        fixup_entity_ids(result)

    except Exception as e:
        if not opt.skip:
            raise

        error(f"ERROR: skipping blueprint '{label}' due to exception: {e}")
        traceback.print_exc()

        stream.seek(content_start + content_size, 0)

        global skipped_blueprints
        skipped_blueprints += 1

        result = None

    finally:
        version = library_version

    content_end = stream.tell()
    parsed_size = content_end - content_start
    if parsed_size != content_size:
        raise AssertionError(f"mismatch between declared blueprint size ({content_size})"
            f" and parsed size ({parsed_size})")

    # Strange: Conditional data usually follows the flag immediately.
    if has_removed_mods:
        # skp because already read
        index_size = stream.count()
        stream.seek(index_size, 1)

    return result


def parse_blueprint_book(stream: PrimitiveStream, index, library_version):
    result = {
        "item": "blueprint-book",
        "version": library_version,
    }

    file_position = stream.tell()

    label = result["label"] = stream.string()
    verbose(f"blueprint-book '{label}' (@{file_position:#x})")

    description = stream.string()
    if description:
        result["description"] = description

    parse_icons(stream, index, result)

    parse_library_objects(stream, index, result, library_version)

    active_index = stream.u8()
    result["active_index"] = active_index

    stream.expect(0x00)

    verbose(f"end of book '{label}' (@{stream.tell():#x})")

    return result


def parse_deconstruction_item(stream: PrimitiveStream, index, library_version):
    def read_filters(section_name, type):
        unknowns = {}
        unknown_count = stream.count8()
        for u in range(unknown_count):
            filter_index = stream.u16()
            name = stream.string()
            unknowns[filter_index] = name

        filters = []
        filter_count = stream.u8()
        debug(f"{section_name.replace('_', '-')}: {filter_count}")
        for f in range(filter_count):
            name = read_name(stream, index, type)
            if name:
                unknown_replacement = unknowns.get(f)
                if unknown_replacement:
                    name = unknown_replacement
                debug(f"    [{f}]: {name}")
                filters.append({
                    # Strange: This index is zero-based, not one-based.
                    "index": f,
                    "name": name
                })
        if filters:
            result["settings"][section_name] = filters

    result = {
        "item": "deconstruction-planner",
        "version": library_version,
        "settings": {},
    }

    file_position = stream.tell()

    result["label"] = stream.string()

    verbose(f"deconstruction-item '{result['label']}' (@{file_position:#x})")

    description = stream.string()
    if description:
        result["settings"]["description"] = description

    # strange: Icons in "settings" instead of top-level.
    parse_icons(stream, index, result["settings"])

    entity_filter_mode = stream.u8()
    if entity_filter_mode:
        result["settings"]["entity_filter_mode"] = entity_filter_mode

    read_filters("entity_filters", Index.ENTITY)

    trees_and_rocks_only = stream.bool()
    if trees_and_rocks_only:
        result["settings"]["trees_and_rocks_only"] = True

    tile_filter_mode = stream.u8()
    if tile_filter_mode:
        result["settings"]["tile_filter_mode"] = tile_filter_mode

    tile_selection_mode = stream.u8()
    if tile_selection_mode:
        result["settings"]["tile_selection_mode"] = tile_selection_mode

    read_filters("tile_filters", Index.TILE)

    return result


def parse_upgrade_item(stream: PrimitiveStream, index, library_version):
    result = {
        "item": "upgrade-planner",
        "version": library_version,
        "settings": {}
    }

    file_position = stream.tell()

    result["label"] = stream.string()

    verbose(f"upgrade-item '{result['label']}' (@{file_position:#x})")

    description = stream.string()
    if description:
        result["settings"]["description"] = description

    # strange: Icons in "settings" instead of top-level.
    parse_icons(stream, index, result["settings"])

    unknowns_from = {}
    unknowns_to = {}
    unknown_count = stream.count8()
    for u in range(unknown_count):
        name = stream.string()
        is_to = stream.bool()
        mapper_index = stream.u16()
        if is_to:
            unknowns_to[mapper_index] = name
        else:
            unknowns_from[mapper_index] = name

    def reader(unknowns):
        type = stream.mapped_u8(Index.ENTITY, Index.ITEM)
        name = read_name(stream, index, type)
        if name:
            unknown_replacement = unknowns.get(m)
            if unknown_replacement:
                name = unknown_replacement
            return {
                "type": type.value,
                "name": name
            }
        else:
            return None

    mappers = []
    mapper_count = stream.count8()
    for m in range(mapper_count):
        # see read_signal but the types are different
        _from = reader(unknowns_from)
        _to = reader(unknowns_to)
        if _from or _to:
            mappers.append({
                # Strange: This index is zero-based, not one-based.
                "index": m,
                "from": _from,
                "to": _to
            })
    if mappers:
        result["settings"]["mappers"] = mappers
    return result


object_handlers = {
    "blueprint": parse_blueprint,
    "blueprint-book": parse_blueprint_book,
    "deconstruction-item": parse_deconstruction_item,
    "upgrade-item": parse_upgrade_item,
}


################################################################
#
# main

if __name__ == "__main__":
    # Pin encoding to UTF-8 because:
    #  - The output MUST support characters like '≠' (\u2260)
    #  - The output must conform to Factorio's export format.
    # The user's prefered encoding might not support that.
    # So STDOUT is required, verbose/debug output on STDERR can contain
    # wild character. STDIN is there just to round them all up.
    sys.stdin = io.TextIOWrapper(sys.stdin.detach(), encoding="utf-8")
    sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding="utf-8")
    sys.stderr = io.TextIOWrapper(sys.stderr.detach(), encoding="utf-8")

    parser = argparse.ArgumentParser(
        description="Convert a binary 'blueprint-storage.dat' file JSON.")
    parser.add_argument("-s", "--skip-bad", action="store_true", dest="skip",
        help="skip unparsable blueprints and exit with '2'"),
    parser.add_argument("-v", "--verbose", action="store_true", dest="v",
        help="verbose output on STDERR")
    parser.add_argument("-d", "--debug", action="store_true", dest="d",
        help="debug output on STDERR")
    parser.add_argument("-x", "--extended", action="store_true", dest="x",
        help="extended output: add voluminous stuff found in .dat but not used in .export"
        " Currently:\n - migrations\n - prototype index")
    parser.add_argument("filename", nargs="?", default="blueprint-storage.dat")
    opt = parser.parse_args()

    verbose(f"file: {opt.filename}")
    with open(opt.filename, "rb") as f:
        library = parse_blueprint_library(PrimitiveStream(f))
        json.dump(library, sys.stdout, indent=1, sort_keys=True, ensure_ascii=False)

    if skipped_blueprints:
        error(f"ERROR - summary: skipped {skipped_blueprints} unreadable blueprints.")
        exit(2)
