"""Decode a runtime .riv into a flat list of typed objects.

Rive runtime format (major 7):
  "RIVE" varuint major, varuint minor, varuint fileId
  table of contents: varuint property keys until 0, then 2-bit field types
    packed 4 per uint32 LE (0 uint, 1 string/bytes, 2 float32, 3 color)
  objects: varuint typeKey, then (varuint propKey, value)* until propKey 0

Type and property names come from tool/rive_schema.json (dump_schema.py).
Usage: python riv_decode.py file.riv  -> prints a type census + writes .json
"""
import json
import os
import struct
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))


def load_schema():
    with open(os.path.join(HERE, "rive_schema.json"), encoding="utf-8") as f:
        schema = json.load(f)
    by_type_key = {}
    prop_by_key = {}
    for name, s in schema.items():
        if s.get("typeKey") is not None:
            by_type_key[s["typeKey"]] = name
        for p in s["properties"]:
            prop_by_key.setdefault(p["key"], p)
    return schema, by_type_key, prop_by_key


class Reader:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def eof(self):
        return self.i >= len(self.d)

    def varuint(self):
        r = shift = 0
        while True:
            b = self.d[self.i]
            self.i += 1
            r |= (b & 0x7F) << shift
            if b < 0x80:
                return r
            shift += 7

    def f32(self):
        v = struct.unpack_from("<f", self.d, self.i)[0]
        self.i += 4
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.i)[0]
        self.i += 4
        return v

    def blob(self):
        n = self.varuint()
        b = self.d[self.i:self.i + n]
        self.i += n
        return b


# wire field type for a schema property type
WIRE = {
    "double": 2, "Color": 3,
    "String": 1, "Bytes": 1, "List<Id>": 1,
}


# Keys the runtime still writes but the CLI schema no longer lists.
# Artboard 9/10 are its position on the editor stage (doubles).
LEGACY = {
    9: {"name": "stageX", "type": "double", "key": 9},
    10: {"name": "stageY", "type": "double", "key": 10},
}


def decode(path):
    schema, by_type_key, prop_by_key = load_schema()
    r = Reader(open(path, "rb").read())
    assert r.d[:4] == b"RIVE", "not a .riv"
    r.i = 4
    major, minor, file_id = r.varuint(), r.varuint(), r.varuint()
    keys = []
    while True:
        k = r.varuint()
        if k == 0:
            break
        keys.append(k)
    toc = {}
    cur = 0
    for n, k in enumerate(keys):
        # 2 bits per key, but only 4 keys per uint32 (runtime reads a fresh
        # uint32 every 8 bits of shift). Reading 16 per word misaligns all
        # objects after the header.
        if n % 4 == 0:
            cur = r.u32()
        toc[k] = (cur >> (2 * (n % 4))) & 3

    objects = []
    unknown_types = Counter()
    while not r.eof():
        tk = r.varuint()
        tname = by_type_key.get(tk, f"?type{tk}")
        if tname.startswith("?"):
            unknown_types[tk] += 1
        props = {}
        while True:
            pk = r.varuint()
            if pk == 0:
                break
            meta = prop_by_key.get(pk) or LEGACY.get(pk)
            wire = toc.get(pk)
            if wire is None:
                if meta is None:
                    raise ValueError(
                        f"object #{len(objects)} {tname}: property key {pk} is "
                        "neither in the schema nor the ToC; its width is unknown")
                wire = WIRE.get(meta["type"], 0)
            if wire == 0:
                v = r.varuint()
            elif wire == 1:
                b = r.blob()
                ptype = meta["type"] if meta else "Bytes"
                if ptype == "String":
                    v = b.decode("utf-8", "replace")
                elif ptype == "List<Id>":
                    rr = Reader(b)
                    v = []
                    while not rr.eof():
                        v.append(rr.varuint())
                else:
                    v = {"bytes": len(b), "_raw": b.hex()}
            elif wire == 2:
                v = r.f32()
            else:
                v = r.u32()
            name = meta["name"] if meta else f"?p{pk}"
            if meta and meta["type"] == "bool":
                v = bool(v)
            props[name] = {"k": pk, "v": v}
        objects.append({"type": tname, "typeKey": tk, "props": props})
    return {"major": major, "minor": minor, "fileId": file_id,
            "objects": objects, "unknownTypes": dict(unknown_types)}


def main(path):
    doc = decode(path)
    census = Counter(o["type"] for o in doc["objects"])
    print(f"v{doc['major']}.{doc['minor']}  objects={len(doc['objects'])}  "
          f"unknown={doc['unknownTypes']}")
    for t, n in census.most_common():
        print(f"  {n:5d} {t}")
    out = os.path.splitext(path)[0] + ".decoded.json"
    for o in doc["objects"]:
        for p in o["props"].values():
            if isinstance(p["v"], dict):
                p["v"].pop("_raw", None)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
    print("->", out)


if __name__ == "__main__":
    main(sys.argv[1])
