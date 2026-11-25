#!/usr/bin/env python3
"""Generate a messy synthetic photo library for testing PhotoManager's scanner and organiser.

It imitates years of copying memory cards around:
  * trips (several days, Canon RAW+JPEG pairs plus GPS-tagged phone shots in moving cities)
  * one-day events and everyday snaps
  * the same card dump copied into several backup folders, some files renamed "IMG_1 copy.JPG"
  * resized exports of some photos (near-duplicates: same EXIF, different bytes)
  * scans with no EXIF date, some with a date in the file name

Images are tiny (default 64x48) so tens of thousands of files generate quickly.
RAW files are TIFF data with a camera RAW extension; ImageIO reads their EXIF.

Usage:
  python3 tools/make_synthetic_library.py OUT_DIR --shots 20000 [--seed 1] [--size 64x48]
Writes OUT_DIR/expected.json with the ground truth (trips, unique shots, duplicates).
"""
import argparse
import json
import os
import random
import shutil
from datetime import datetime, timedelta

from PIL import Image, TiffImagePlugin

CITIES = {
    "Hong Kong": (22.2783, 114.1747),
    "Tokyo": (35.6762, 139.6503),
    "Kyoto": (35.0116, 135.7681),
    "Paris": (48.8566, 2.3522),
    "Lyon": (45.7640, 4.8357),
    "New York": (40.7128, -74.0060),
    "Reykjavik": (64.1466, -21.9426),
    "Sydney": (-33.8688, 151.2093),
}
HOME = ("Toronto", (43.6532, -79.3832))


def dms(value):
    value = abs(value)
    d = int(value)
    m = int((value - d) * 60)
    s = round(((value - d) * 60 - m) * 60, 2)
    return (TiffImagePlugin.IFDRational(d), TiffImagePlugin.IFDRational(m), TiffImagePlugin.IFDRational(int(s * 100), 100))


def make_exif(when, make, model, gps=None):
    exif = Image.Exif()
    stamp = when.strftime("%Y:%m:%d %H:%M:%S")
    exif[0x010F] = make
    exif[0x0110] = model
    exif[0x0132] = stamp
    sub = exif.get_ifd(0x8769)
    sub[0x9003] = stamp  # DateTimeOriginal
    sub[0x9004] = stamp  # DateTimeDigitized
    if gps:
        lat, lon = gps
        g = exif.get_ifd(0x8825)
        g[1] = "N" if lat >= 0 else "S"
        g[2] = dms(lat)
        g[3] = "E" if lon >= 0 else "W"
        g[4] = dms(lon)
    return exif


class Generator:
    def __init__(self, out, size, rng):
        self.out = out
        self.size = size
        self.rng = rng
        self.counter = {"canon": 1000, "phone": 2000}
        self.truth = {"trips": [], "events": [], "unique_shots": 0, "files": 0, "duplicate_files": 0, "near_duplicates": 0}
        self.card_dumps = []  # (folder, [files]) for later duplication

    def image(self, seed):
        r = random.Random(seed)
        img = Image.new("RGB", self.size, (r.randrange(256), r.randrange(256), r.randrange(256)))
        # A few random blocks so content (and therefore the hash) differs per shot.
        for _ in range(4):
            x, y = r.randrange(self.size[0]), r.randrange(self.size[1])
            img.paste((r.randrange(256), r.randrange(256), r.randrange(256)), (x, y, min(self.size[0], x + 8), min(self.size[1], y + 8)))
        return img

    def write(self, path, img, exif, fmt, when, quality=85):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if fmt == "JPEG":
            img.save(path, "JPEG", quality=quality, exif=exif.tobytes() if exif else b"")
        else:
            img.save(path, "TIFF", exif=exif.tobytes() if exif else b"")
        ts = when.timestamp() + self.rng.randint(0, 3600)
        os.utime(path, (ts, ts))
        self.truth["files"] += 1

    def next_name(self, kind):
        self.counter[kind] += 1
        if self.counter[kind] > 9999:
            self.counter[kind] = 1  # card counter rollover: names repeat
        return f"IMG_{self.counter[kind]:04d}"

    def canon_shot(self, folder, when, raw=True, gps=None):
        name = self.next_name("canon")
        seed = self.rng.random()
        img = self.image(seed)
        exif = make_exif(when, "Canon", "Canon EOS R5", gps)
        files = [os.path.join(folder, name + ".JPG")]
        self.write(files[0], img, exif, "JPEG", when)
        if raw:
            files.append(os.path.join(folder, name + ".CR2"))
            self.write(files[1], img, exif, "TIFF", when)
        self.truth["unique_shots"] += 1
        return files

    def phone_shot(self, folder, when, gps):
        name = self.next_name("phone")
        jitter = (gps[0] + self.rng.uniform(-0.02, 0.02), gps[1] + self.rng.uniform(-0.02, 0.02))
        path = os.path.join(folder, name + ".JPG")
        self.write(path, self.image(self.rng.random()), make_exif(when, "Apple", "iPhone 15 Pro", jitter), "JPEG", when)
        self.truth["unique_shots"] += 1
        return [path]

    def trip(self, start, days, cities, shots_per_day):
        dump = os.path.join(self.out, f"DCIM dump {start:%Y-%m}", "100CANON")
        phone = os.path.join(self.out, "iPhone export", f"{start:%Y}")
        files = []
        for d in range(days):
            city = cities[min(len(cities) - 1, d * len(cities) // days)]
            gps = CITIES[city]
            day = start + timedelta(days=d)
            t = day.replace(hour=8, minute=0) + timedelta(minutes=self.rng.randint(0, 90))
            for _ in range(shots_per_day):
                t += timedelta(seconds=self.rng.choice([5, 20, 60, 180, 600]))
                if t.hour >= 22:
                    break
                if self.rng.random() < 0.3:
                    files += self.phone_shot(phone, t, gps)
                else:
                    files += self.canon_shot(dump, t, raw=self.rng.random() < 0.8)
        self.card_dumps.append((dump, [f for f in files if f.startswith(dump)]))
        self.truth["trips"].append({"start": start.isoformat(), "days": days, "cities": cities})

    def day_event(self, when, count, name):
        folder = os.path.join(self.out, "Camera", f"{when:%Y}", f"{when:%Y_%m_%d}")
        t = when.replace(hour=13)
        files = []
        for _ in range(count):
            t += timedelta(seconds=self.rng.choice([10, 30, 90]))
            files += self.canon_shot(folder, t, raw=self.rng.random() < 0.5)
        self.card_dumps.append((folder, files))
        self.truth["events"].append({"date": when.date().isoformat(), "shots": count, "name": name})

    def everyday(self, when):
        folder = os.path.join(self.out, "iPhone export", f"{when:%Y}")
        self.phone_shot(folder, when.replace(hour=self.rng.randint(8, 21), minute=self.rng.randint(0, 59)), HOME[1])

    def scans(self, n):
        folder = os.path.join(self.out, "Scans")
        for i in range(n):
            when = datetime(1990 + i % 15, 1 + i % 12, 1 + i % 27, 12)
            name = f"Scan_{when:%Y%m%d}_{i:03d}.tif" if i % 2 == 0 else f"scan{i:03d}.tif"
            path = os.path.join(folder, name)
            self.write(path, self.image(self.rng.random()), None, "TIFF", datetime(2023, 6, 1))
            self.truth["unique_shots"] += 1

    def make_mess(self):
        """Copy card dumps around the way people do."""
        for i, (folder, files) in enumerate(self.card_dumps):
            if not files:
                continue
            roll = self.rng.random()
            if roll < 0.5:
                # Whole-folder backup copy.
                dest = os.path.join(self.out, "Backup", "old laptop", "Pictures", f"import {i}")
                for f in files:
                    self._copy(f, os.path.join(dest, os.path.basename(f)))
            if roll < 0.3 or roll > 0.8:
                # JPEGs only, dragged to the Desktop with Finder-style renames for some.
                dest = os.path.join(self.out, "Desktop copy", f"photos {i}")
                for f in files:
                    if f.endswith(".JPG") and self.rng.random() < 0.6:
                        base = os.path.splitext(os.path.basename(f))[0]
                        name = f"{base} copy.JPG" if self.rng.random() < 0.3 else os.path.basename(f)
                        self._copy(f, os.path.join(dest, name))
            # A few resized exports: near-duplicates.
            for f in files:
                if f.endswith(".JPG") and self.rng.random() < 0.04:
                    dest = os.path.join(self.out, "exports", f"set {i}", os.path.basename(f).replace(".JPG", ".jpg"))
                    if os.path.exists(dest):
                        continue
                    with Image.open(f) as im:
                        exif = im.getexif()
                        small = im.resize((max(8, self.size[0] // 2), max(6, self.size[1] // 2)))
                        os.makedirs(os.path.dirname(dest), exist_ok=True)
                        small.save(dest, "JPEG", quality=70, exif=exif.tobytes())
                    self.truth["files"] += 1
                    self.truth["near_duplicates"] += 1

    def _copy(self, src, dest):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.exists(dest):
            return
        shutil.copy2(src, dest)
        self.truth["files"] += 1
        self.truth["duplicate_files"] += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--shots", type=int, default=5000, help="approximate number of distinct shots")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--size", default="64x48")
    args = ap.parse_args()
    w, h = (int(v) for v in args.size.split("x"))
    rng = random.Random(args.seed)
    if os.path.exists(args.out) and os.listdir(args.out):
        raise SystemExit(f"{args.out} is not empty")
    os.makedirs(args.out, exist_ok=True)
    gen = Generator(args.out, (w, h), rng)

    year = 2016
    t = datetime(year, 1, 5, 12)
    names = ["Birthday", "Wedding", "Hike", "Concert", "Graduation", "BBQ", "Ski day"]
    while gen.truth["unique_shots"] < args.shots - 40:
        r = rng.random()
        if r < 0.15:
            cities = rng.sample(list(CITIES), rng.randint(1, 3))
            days = rng.randint(3, 10)
            gen.trip(t, days, cities, rng.randint(20, 80))
            t += timedelta(days=days + rng.randint(5, 30))
        elif r < 0.45:
            gen.day_event(t, rng.randint(15, 120), rng.choice(names))
            t += timedelta(days=rng.randint(3, 20))
        else:
            for _ in range(rng.randint(1, 6)):
                gen.everyday(t)
            t += timedelta(days=rng.randint(1, 4))
    gen.scans(40)
    gen.make_mess()

    with open(os.path.join(args.out, "expected.json"), "w") as fh:
        json.dump(gen.truth, fh, indent=2)
    print(json.dumps({k: (len(v) if isinstance(v, list) else v) for k, v in gen.truth.items()}, indent=2))


if __name__ == "__main__":
    main()
