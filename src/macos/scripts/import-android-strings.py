#!/usr/bin/env python3
"""Build RHVoice/Resources/Localizable.xcstrings from the Android app's translations.

The Android app (src/android/RHVoice-core/src/main/res/values*/strings.xml) is translated
into about twenty languages. The macOS app uses the same English wording as its localization
keys for the strings both apps share, so those translations can be reused directly.
Strings that exist only in the macOS app stay English until translated in the catalog.

Usage: scripts/import-android-strings.py [--check]
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
MACOS = os.path.dirname(HERE)
REPO = os.path.abspath(os.path.join(MACOS, "..", ".."))
RES = os.path.join(REPO, "src", "android", "RHVoice-core", "src", "main", "res")
OUTPUT = os.path.join(MACOS, "RHVoice", "Resources", "Localizable.xcstrings")

# Android string key -> macOS localization key (the English text used in the SwiftUI code).
KEYS = {
    "install": "Install",
    "uninstall": "Uninstall",
    "play": "Play",
    "stop": "Stop",
    "cancel": "Cancel",
    "languages": "Languages",
    "version": "Version",
    "settings": "Settings",
    "speech_quality": "Speech quality",
    "voice_remove_question": "Are you sure you want to uninstall this voice?",
    "pseudo_english_title": "English words",
    "user_dicts": "User dictionaries",
    "config_file": "Configuration file",
}
ARRAY_KEYS = {
    "quality_labels": ["Best possible performance", "Standard quality", "Best possible quality"],
}


def unescape(value):
    value = value.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n")
    return re.sub(r"\s+", " ", value).strip()


def load_strings(path):
    strings, arrays = {}, {}
    if not os.path.exists(path):
        return strings, arrays
    root = ET.parse(path).getroot()
    for element in root:
        name = element.get("name")
        if element.tag == "string" and name:
            strings[name] = unescape("".join(element.itertext()))
        elif element.tag == "string-array" and name:
            arrays[name] = [unescape("".join(item.itertext())) for item in element.findall("item")]
    return strings, arrays


def android_locale_to_apple(folder):
    qualifier = folder[len("values-"):]
    if "-r" in qualifier:
        language, region = qualifier.split("-r", 1)
        return f"{language}-{region}"
    return qualifier


def main():
    english, english_arrays = load_strings(os.path.join(RES, "values", "strings.xml"))
    catalog = {}
    for key, source in KEYS.items():
        if key in english:
            catalog[source] = {"localizations": {}}
    for key, sources in ARRAY_KEYS.items():
        for source in sources:
            catalog[source] = {"localizations": {}}

    folders = sorted(f for f in os.listdir(RES) if f.startswith("values-") and os.path.exists(os.path.join(RES, f, "strings.xml")))
    for folder in folders:
        locale = android_locale_to_apple(folder)
        strings, arrays = load_strings(os.path.join(RES, folder, "strings.xml"))
        for key, source in KEYS.items():
            if key in strings and source in catalog and strings[key]:
                catalog[source]["localizations"][locale] = {"stringUnit": {"state": "translated", "value": strings[key]}}
        for key, sources in ARRAY_KEYS.items():
            values = arrays.get(key, [])
            if len(values) == len(sources):
                for source, value in zip(sources, values):
                    catalog[source]["localizations"][locale] = {"stringUnit": {"state": "translated", "value": value}}

    document = {"sourceLanguage": "en", "version": "1.0", "strings": dict(sorted(catalog.items()))}
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        current = open(OUTPUT, encoding="utf-8").read() if os.path.exists(OUTPUT) else None
        if current != output:
            print(f"{OUTPUT} is out of date; run scripts/import-android-strings.py", file=sys.stderr)
            sys.exit(1)
        print("Localizable.xcstrings is up to date")
        return
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write(output)
    languages = sorted({loc for entry in catalog.values() for loc in entry["localizations"]})
    print(f"wrote {OUTPUT}: {len(catalog)} strings, {len(languages)} languages: {' '.join(languages)}")


if __name__ == "__main__":
    main()
