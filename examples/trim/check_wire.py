"""Independent JSON/Base64/raw-layout check; does not require Python zarr."""
import base64
import json
import struct
import sys
from pathlib import Path

root = Path(sys.argv[1])
for version in (2, 3):
    for width, code in ((8, "b"), (16, "h"), (32, "i"), (64, "q")):
        path = root / f"v{version}-int{width}"
        if version == 2:
            md = json.loads((path / ".zarray").read_text())
            scalar = f"{'|' if width == 8 else '<'}i{width // 8}"
            assert md["dtype"] == [["r", scalar], ["i", scalar]]
            assert struct.unpack("<" + code * 2, base64.b64decode(md["fill_value"])) == (9, -10)
            chunk = path / "0.0"
        else:
            md = json.loads((path / "zarr.json").read_text())
            assert md["data_type"] == {"name": "struct", "configuration": {
                "fields": [{"name": "r", "data_type": f"int{width}"},
                           {"name": "i", "data_type": f"int{width}"}]}}
            assert md["fill_value"] == {"r": 9, "i": -10}
            assert md["codecs"] == [{"name": "bytes", "configuration": {"endian": "little"}}]
            chunk = path / "c" / "0" / "0"
        assert md["shape"] == [2, 2]
        assert struct.unpack("<" + code * 8, chunk.read_bytes()) == (23, -2, 3, -4, -5, 6, 7, -8)
print("Validated JSON, fill and raw bytes of all 8 executable-generated stores")
