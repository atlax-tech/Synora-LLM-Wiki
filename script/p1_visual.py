#!/usr/bin/env python3
"""Validate P1 screenshot dimensions and optionally compare an approved baseline."""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import zlib
from pathlib import Path


SIZES = {
    "compact": (1280, 720),
    "default": (1440, 900),
    "large": (1728, 1117),
}
SSIM_THRESHOLD = 0.95
CONTENT_RE = re.compile(
    r"(?P<width>\d+(?:\.\d+)?) by (?P<height>\d+(?:\.\d+)?) points, "
    r"(?P<scale>\d+(?:\.\d+)?)x scale"
)


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        if handle.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"not a PNG: {path}")
        length = struct.unpack(">I", handle.read(4))[0]
        chunk_type = handle.read(4)
        if chunk_type != b"IHDR" or length < 8:
            raise ValueError(f"missing PNG IHDR: {path}")
        width, height = struct.unpack(">II", handle.read(8))
        return width, height


def _png_luma(path: Path) -> tuple[int, int, list[float]]:
    """Decode the 8-bit RGB/RGBA PNGs produced by XCUIScreenshot."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")

    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        offset += length + 12
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", chunk
            )
        elif chunk_type == b"IDAT":
            compressed.extend(chunk)
        elif chunk_type == b"IEND":
            break

    if None in (width, height, bit_depth, color_type, interlace):
        raise ValueError(f"incomplete PNG header: {path}")
    if bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
        raise ValueError(f"unsupported PNG format in {path}")

    channels = 4 if color_type == 6 else 3
    row_bytes = width * channels
    raw = zlib.decompress(compressed)
    expected = height * (row_bytes + 1)
    if len(raw) != expected:
        raise ValueError(f"unexpected PNG payload size in {path}")

    rows: list[bytearray] = []
    cursor = 0
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + row_bytes]
        cursor += row_bytes
        row = bytearray(encoded)
        previous = rows[-1] if rows else None
        for index in range(row_bytes):
            left = row[index - channels] if index >= channels else 0
            up = previous[index] if previous else 0
            upper_left = previous[index - channels] if previous and index >= channels else 0
            if filter_type == 1:
                row[index] = (row[index] + left) & 0xFF
            elif filter_type == 2:
                row[index] = (row[index] + up) & 0xFF
            elif filter_type == 3:
                row[index] = (row[index] + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                estimate = left + up - upper_left
                distances = (abs(estimate - left), abs(estimate - up), abs(estimate - upper_left))
                predictor = (left, up, upper_left)[distances.index(min(distances))]
                row[index] = (row[index] + predictor) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"unsupported PNG filter {filter_type} in {path}")
        rows.append(row)

    luma: list[float] = []
    for row in rows:
        for index in range(0, row_bytes, channels):
            red, green, blue = row[index : index + 3]
            luma.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    return width, height, luma


def _tile_ssim(first: list[float], second: list[float], width: int, height: int) -> float:
    """Compute mean 8x8 luminance SSIM, keeping comparison bounded for large PNGs."""
    if len(first) != len(second):
        raise ValueError("images have different pixel counts")
    tile = 8
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    values: list[float] = []
    for top in range(0, height, tile):
        bottom = min(top + tile, height)
        for left in range(0, width, tile):
            right = min(left + tile, width)
            first_tile = []
            second_tile = []
            for row in range(top, bottom):
                start = row * width + left
                end = row * width + right
                first_tile.extend(first[start:end])
                second_tile.extend(second[start:end])
            count = len(first_tile)
            mean_first = sum(first_tile) / count
            mean_second = sum(second_tile) / count
            variance_first = sum((value - mean_first) ** 2 for value in first_tile) / count
            variance_second = sum((value - mean_second) ** 2 for value in second_tile) / count
            covariance = sum(
                (first_tile[index] - mean_first) * (second_tile[index] - mean_second)
                for index in range(count)
            ) / count
            numerator = (2 * mean_first * mean_second + c1) * (2 * covariance + c2)
            denominator = (mean_first**2 + mean_second**2 + c1) * (
                variance_first + variance_second + c2
            )
            values.append(numerator / denominator if denominator else 1.0)
    return sum(values) / len(values)


def compare_images(first_path: Path, second_path: Path) -> float:
    first_width, first_height, first = _png_luma(first_path)
    second_width, second_height, second = _png_luma(second_path)
    if (first_width, first_height) != (second_width, second_height):
        raise ValueError(
            f"PNG dimensions differ: {first_width}x{first_height} vs "
            f"{second_width}x{second_height}"
        )
    return _tile_ssim(first, second, first_width, first_height)


def read_metadata(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"metadata must be an object: {path}")
    return value


def observation(metadata: dict[str, object], name: str, image: Path) -> dict[str, object]:
    raw = metadata.get(name)
    item = dict(raw) if isinstance(raw, dict) else {}
    width, height = png_size(image)
    item["pngPixels"] = {"width": width, "height": height}
    content = item.get("contentValue")
    if isinstance(content, str):
        match = CONTENT_RE.fullmatch(content)
        if match:
            item["contentPoints"] = {
                "width": float(match.group("width")),
                "height": float(match.group("height")),
                "scale": float(match.group("scale")),
            }
    return item


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--require-baseline", action="store_true")
    args = parser.parse_args()

    metadata = read_metadata(args.metadata) if args.metadata else {}
    report: dict[str, object] = {
        "threshold": SSIM_THRESHOLD,
        "candidateDirectory": str(args.candidates),
        "baselineDirectory": str(args.baseline) if args.baseline else None,
        "sizes": {},
    }
    failures: list[str] = []
    compared = False

    for name, expected in SIZES.items():
        image = args.candidates / f"shell-{name}.png"
        entry: dict[str, object] = {"expectedContentPoints": {"width": expected[0], "height": expected[1]}}
        if not image.is_file():
            entry["status"] = "MISSING"
            failures.append(f"missing candidate: {image}")
            report["sizes"][name] = entry
            continue
        try:
            entry["candidate"] = observation(metadata, name, image)
        except (OSError, ValueError, struct.error, zlib.error) as error:
            entry["status"] = "INVALID"
            entry["error"] = str(error)
            failures.append(f"invalid candidate {name}: {error}")
            report["sizes"][name] = entry
            continue

        content = entry["candidate"].get("contentPoints")
        if isinstance(content, dict):
            width_delta = abs(float(content["width"]) - expected[0])
            height_delta = abs(float(content["height"]) - expected[1])
            entry["contentDeltaPoints"] = {"width": width_delta, "height": height_delta}
            if width_delta > 1 or height_delta > 1:
                entry["geometryStatus"] = "CLAMPED"
            else:
                entry["geometryStatus"] = "MATCH"
        else:
            entry["geometryStatus"] = "UNREPORTED"

        if args.baseline:
            baseline = args.baseline / f"shell-{name}.png"
            if not baseline.is_file():
                entry["status"] = "BASELINE_MISSING"
                failures.append(f"missing baseline: {baseline}")
            else:
                try:
                    score = compare_images(image, baseline)
                    entry["ssim"] = score
                    entry["status"] = "PASS" if score >= SSIM_THRESHOLD else "SSIM_BELOW_THRESHOLD"
                    compared = True
                    if score < SSIM_THRESHOLD:
                        failures.append(f"{name} SSIM {score:.4f} < {SSIM_THRESHOLD:.2f}")
                except (OSError, ValueError, struct.error, zlib.error) as error:
                    entry["status"] = "COMPARE_ERROR"
                    entry["error"] = str(error)
                    failures.append(f"comparison failed for {name}: {error}")
        else:
            entry["status"] = "NOT_COMPARED"
        report["sizes"][name] = entry

    if args.require_baseline and not args.baseline:
        failures.append("approved baseline is required but --baseline was not supplied")
    report["status"] = "FAIL" if failures else ("PASS" if compared else "NOT_COMPARED")
    report["failures"] = failures
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"P1 visual {report['status']}: {args.report}")
    for failure in failures:
        print(f"P1 visual: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
