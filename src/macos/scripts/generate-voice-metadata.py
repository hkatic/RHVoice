#!/usr/bin/env python3
"""Generate RHVoice/Resources/voice-metadata.json for the macOS app.

The package index the app downloads carries no license or creator information; that lives
in each voice repository (data/voices/<voice>/attrib.html, LICENSE, COPYRIGHT_NOTICE) and,
for voices whose packs carry nothing machine-readable, in scripts/voice-metadata.overrides.json.
This script merges both into one table keyed by package id so the app can show creators and
licenses before a voice is installed.

Usage: scripts/generate-voice-metadata.py [--check]
  --check   exit 1 when the generated file differs from the committed one (CI)
"""
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MACOS = os.path.dirname(HERE)
REPO = os.path.abspath(os.path.join(MACOS, "..", ".."))
VOICES_DIR = os.path.join(REPO, "data", "voices")
OVERRIDES = os.path.join(HERE, "voice-metadata.overrides.json")
OUTPUT = os.path.join(MACOS, "RHVoice", "Resources", "voice-metadata.json")
INDEX = os.path.join(MACOS, "RHVoice", "Resources", "packages-fallback.json")

LICENSES_BY_URL = [
    (r"publicdomain/zero/1\.0", ("CC0-1.0", "CC0 1.0 (public domain)", "https://creativecommons.org/publicdomain/zero/1.0/")),
    (r"licenses/by-nc-nd/4\.0", ("CC-BY-NC-ND-4.0", "CC BY-NC-ND 4.0", "https://creativecommons.org/licenses/by-nc-nd/4.0/")),
    (r"licenses/by-nc-sa/4\.0", ("CC-BY-NC-SA-4.0", "CC BY-NC-SA 4.0", "https://creativecommons.org/licenses/by-nc-sa/4.0/")),
    (r"licenses/by-nc/4\.0", ("CC-BY-NC-4.0", "CC BY-NC 4.0", "https://creativecommons.org/licenses/by-nc/4.0/")),
    (r"licenses/by-sa/4\.0", ("CC-BY-SA-4.0", "CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/")),
    (r"licenses/by/4\.0", ("CC-BY-4.0", "CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")),
    (r"gpl-3\.0", ("GPL-3.0-or-later", "GNU GPL 3.0", "https://www.gnu.org/licenses/gpl-3.0.html")),
    (r"lgpl-2\.1", ("LGPL-2.1-or-later", "GNU LGPL 2.1", "https://www.gnu.org/licenses/lgpl-2.1.html")),
]

LICENSES_BY_TEXT = [
    (r"CC0 1\.0|Creative Commons Legal Code\s+CC0", LICENSES_BY_URL[0][1]),
    (r"Attribution-NonCommercial-NoDerivatives 4\.0", LICENSES_BY_URL[1][1]),
    (r"Attribution-NonCommercial-ShareAlike 4\.0", LICENSES_BY_URL[2][1]),
    (r"Attribution-NonCommercial 4\.0", LICENSES_BY_URL[3][1]),
    (r"Attribution-ShareAlike 4\.0", LICENSES_BY_URL[4][1]),
    (r"Attribution 4\.0 International", LICENSES_BY_URL[5][1]),
    (r"GNU GENERAL PUBLIC LICENSE\s+Version 3", LICENSES_BY_URL[6][1]),
    (r"GNU LESSER GENERAL PUBLIC LICENSE\s+Version 2\.1", LICENSES_BY_URL[7][1]),
    (r"free for use for any purpose", (None, "CMU ARCTIC license (free for any use)", "http://festvox.org/cmu_arctic/")),
]


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_info(text):
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(";") or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def package_id(info):
    """Same rule as the engine and the package index: android_id, else lowercased name with '-' -> '_'."""
    if info.get("android_id"):
        return info["android_id"].lower()
    return info.get("name", "").lower().replace("-", "_")


def license_from_url(url):
    for pattern, lic in LICENSES_BY_URL:
        if re.search(pattern, url):
            return {"spdx": lic[0], "name": lic[1], "url": lic[2]}
    return None


def license_from_text(text):
    for pattern, lic in LICENSES_BY_TEXT:
        if re.search(pattern, text, re.IGNORECASE):
            return {"spdx": lic[0], "name": lic[1], "url": lic[2]}
    return None


def strip_tags(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def parse_attrib(text):
    """attrib.html is a list of <p> fragments: a © line, a license link, 'Developed by' or a Team list."""
    entry = {}
    creators = []
    paragraphs = re.findall(r"<p[^>]*>(.*?)</p>", text, re.IGNORECASE | re.DOTALL)
    for raw in paragraphs:
        plain = strip_tags(raw)
        links = re.findall(r'href="([^"]+)"', raw)
        if not plain:
            continue
        if plain.startswith("©") or plain.lower().startswith("copyright"):
            entry["copyright"] = plain
            continue
        if plain.startswith("- "):
            creators.append(plain[2:].split(" - ")[0].strip().rstrip("."))
            continue
        lowered = plain.lower()
        if lowered.startswith("developed by"):
            creators.append(plain[len("developed by"):].strip().split(". ")[0].rstrip("."))
            if links and "homepage" not in entry:
                entry["homepage"] = links[0]
            continue
        for link in links:
            lic = license_from_url(link)
            if lic:
                entry["license"] = lic
                break
        if "license" not in entry and ("license" in lowered or "public domain" in lowered):
            lic = license_from_text(plain)
            if lic:
                entry["license"] = lic
    if creators:
        entry["creators"] = creators
    return entry


def collect_from_repo():
    result = {}
    if not os.path.isdir(VOICES_DIR):
        return result
    for directory in sorted(os.listdir(VOICES_DIR)):
        path = os.path.join(VOICES_DIR, directory)
        info_text = read(os.path.join(path, "voice.info"))
        if not info_text:
            continue
        info = parse_info(info_text)
        pid = package_id(info)
        entry = {"name": info.get("name", directory)}
        attrib = read(os.path.join(path, "attrib.html"))
        if attrib:
            entry.update(parse_attrib(attrib))
            entry["source"] = "attrib.html"
        if "license" not in entry:
            for name in ("LICENSE", "license", "LICENSE.txt", "license.txt", "COPYING", "LICENSE.md"):
                text = read(os.path.join(path, name))
                if text:
                    lic = license_from_text(text)
                    if lic:
                        entry["license"] = lic
                        entry["source"] = entry.get("source") or name
                    break
        notice = read(os.path.join(path, "COPYRIGHT_NOTICE"))
        if notice and "copyright" not in entry:
            first = notice.strip().splitlines()[0].strip() if notice.strip() else ""
            if first:
                entry["copyright"] = first
        result[pid] = entry
    return result


def apply_overrides(table):
    data = json.load(open(OVERRIDES, encoding="utf-8"))
    licenses = data.get("licenses", {})
    for pid, override in data.get("voices", {}).items():
        entry = table.setdefault(pid, {})
        for key, value in override.items():
            if key == "license" and isinstance(value, str):
                value = licenses[value]
            entry[key] = value
        entry["source"] = "override" if "source" not in entry else entry["source"] + "+override"
    return table


def report_missing(table):
    try:
        index = json.load(open(INDEX, encoding="utf-8"))
    except OSError:
        return
    missing = []
    for language in index.get("languages", []):
        for voice in language.get("voices", []):
            pid = voice.get("id") or voice["name"].lower().replace("-", "_")
            if pid not in table or "license" not in table[pid]:
                missing.append(f"{voice['name']} ({language['name']}, id {pid})")
    if missing:
        print(f"note: {len(missing)} voices in the package index have no license information:", file=sys.stderr)
        for item in missing:
            print(f"  - {item}", file=sys.stderr)


def main():
    table = apply_overrides(collect_from_repo())
    ordered = {pid: {k: table[pid][k] for k in sorted(table[pid])} for pid in sorted(table)}
    output = json.dumps({"voices": ordered}, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        current = read(OUTPUT)
        if current != output:
            print(f"{OUTPUT} is out of date; run scripts/generate-voice-metadata.py", file=sys.stderr)
            sys.exit(1)
        print("voice-metadata.json is up to date")
        return
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write(output)
    print(f"wrote {OUTPUT}: {len(ordered)} voices")
    report_missing(table)


if __name__ == "__main__":
    main()
