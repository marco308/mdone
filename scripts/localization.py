#!/usr/bin/env python3
"""Move translations between the String Catalogs and one flat file per language.

The `.xcstrings` catalogs are the source of truth Xcode compiles, but they are
not something a person should type into: every translated string needs eight
lines of nesting, plurals need more, and one stray comma breaks the file. A
translator with no Mac (#163) should never have to see that structure.

So each language gets a flat file, `localization/<lang>.json`, of
`"English text" : "translation"` pairs. This script converts in both directions:

    scripts/localization.py export zh-Hans   # catalogs -> localization/zh-Hans.json
    scripts/localization.py import zh-Hans   # localization/zh-Hans.json -> catalogs
    scripts/localization.py import zh-Hans --check   # validate only, for CI

Export merges every catalog into one file, so a string that ships in both the
app and the widget extension appears once. Import writes it back to every
catalog that has the key, which is what makes the two-bundle rule in
docs/localization.md the maintainer's problem instead of the translator's.

Flat file entry shapes, chosen so the common case is one line:

    "Inbox" : "收件箱"                       plain string, also plurals in a
                                            language with one plural form
    "%lld tasks" : { "en" : { "one" : "%lld task", "other" : "%lld tasks" },
                     "plural" : { "one" : "...", "other" : "..." } }
                                            plurals, several forms
    "NSCalendars..." : { "en" : "mDone displays...", "value" : "..." }
                                            key is not the English text

`en` and `comment` are context written by export and ignored by import. An
empty translation means "not translated yet"; import leaves that key alone in
the catalogs, and removes a translation that was later blanked out.

Import validates format specifiers before writing anything, because a `%@`
dropped from a translation is a crash at runtime, not a typo.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FLAT_DIR = REPO / "localization"
CATALOGS = [
    REPO / "mDone" / "Localizable.xcstrings",
    REPO / "mDone" / "InfoPlist.xcstrings",
    REPO / "mDoneWidgets" / "Localizable.xcstrings",
]

# CLDR plural categories, by language. Anything not listed gets English's two;
# a translator whose language needs more can add categories to the flat file
# and import will write whatever it finds.
PLURAL_CATEGORIES = {
    "zh": ["other"], "ja": ["other"], "ko": ["other"], "vi": ["other"],
    "th": ["other"], "id": ["other"], "ms": ["other"],
    "fr": ["one", "many", "other"], "pt-BR": ["one", "many", "other"],
    "ru": ["one", "few", "many", "other"], "uk": ["one", "few", "many", "other"],
    "pl": ["one", "few", "many", "other"], "cs": ["one", "few", "many", "other"],
    "sk": ["one", "few", "many", "other"],
    "ar": ["zero", "one", "two", "few", "many", "other"],
}

NOTES = [
    "Every line is  \"English\" : \"\"  and you type the translation inside the empty quotes.",
    "Leave the English side exactly as it is; it is the key.",
    "Leave a translation as \"\" if you have not done it yet; it falls back to English.",
    "Keep every placeholder (%@ is text, %lld is a number) in the translation. You may",
    "reorder them with %1$@, %2$lld style indexes when word order differs, but then",
    "every placeholder in that string needs an index.",
    "A few entries are objects instead of strings: fill in every \"\" inside them.",
    "\"en\" and \"comment\" are context to help you translate; changing them does nothing.",
    "When done, open a PR with just this file. The maintainer runs",
    "scripts/localization.py import <lang> to write it into the String Catalogs.",
]

# printf-style specifiers, plus Foundation's `%#@name@` substitutions and the
# `%arg` placeholder used inside a substitution's own plural forms.
SPEC_RE = re.compile(
    r"%(?:#@[A-Za-z0-9_]+@|arg\b|(\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?"
    r"[@dDiuUxXoOfeEgGcCsSpaAF%])"
)


class FlatFileError(Exception):
    pass


# ---------------------------------------------------------------------------
# Catalog reading


def load_catalog(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_catalog(path: Path, catalog: dict) -> None:
    """Xcode's own style: 2-space indent, `" : "`, trailing newline."""
    path.write_text(
        json.dumps(catalog, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n",
        encoding="utf-8",
    )


def translatable(entry: dict) -> bool:
    return entry.get("extractionState") != "stale" and entry.get("shouldTranslate", True)


def has_words(key: str) -> bool:
    """`"%@, %@"` and `"·"` have nothing to translate; keep them out of the file."""
    return re.search(r"[^\W\d_]", key) is not None


def unit_value(unit: dict | None) -> str:
    return (unit or {}).get("stringUnit", {}).get("value", "")


def plural_forms(node: dict | None) -> dict[str, str] | None:
    """`{"one": "...", "other": "..."}` from a `variations.plural` block, or None."""
    plural = (node or {}).get("variations", {}).get("plural")
    if plural is None:
        return None
    return {cat: unit_value(unit) for cat, unit in plural.items()}


def source_shape(key: str, entry: dict, source_lang: str) -> dict:
    """What kind of string this is, from its source-language entry.

    Returns {"kind": "plain"|"plural"|"substitutions", "en": ..., ...}.
    """
    loc = entry.get("localizations", {}).get(source_lang)
    if loc and "variations" in loc:
        if "device" in loc["variations"]:
            raise FlatFileError(f"{key!r}: device variations are not supported")
        return {"kind": "plural", "en": plural_forms(loc)}
    if loc and "substitutions" in loc:
        subs = {}
        for name, sub in loc["substitutions"].items():
            subs[name] = {
                "argNum": sub.get("argNum"),
                "formatSpecifier": sub.get("formatSpecifier"),
                "en": plural_forms(sub) or {},
            }
        return {"kind": "substitutions", "en": unit_value(loc), "substitutions": subs}
    # No explicit source entry means the key is the English text.
    return {"kind": "plain", "en": unit_value(loc) if loc else key}


def existing_translation(entry: dict, lang: str, shape: dict) -> dict | str | None:
    loc = entry.get("localizations", {}).get(lang)
    if loc is None:
        return None
    if shape["kind"] == "plural":
        return plural_forms(loc) or {}
    if shape["kind"] == "substitutions":
        return {
            "value": unit_value(loc),
            "substitutions": {
                name: plural_forms(sub) or {} for name, sub in loc.get("substitutions", {}).items()
            },
        }
    return unit_value(loc)


# ---------------------------------------------------------------------------
# Export


def categories_for(lang: str) -> list[str]:
    return PLURAL_CATEGORIES.get(lang) or PLURAL_CATEGORIES.get(lang.split("-")[0]) or ["one", "other"]


def export(lang: str) -> Path:
    cats = categories_for(lang)
    single_form = len(cats) == 1
    strings: dict[str, object] = {}
    seen_shapes: dict[str, dict] = {}

    for catalog_path in CATALOGS:
        catalog = load_catalog(catalog_path)
        source_lang = catalog.get("sourceLanguage", "en")
        if lang == source_lang:
            raise FlatFileError(f"{lang} is the source language; nothing to export")
        for key, entry in catalog["strings"].items():
            if not translatable(entry) or not has_words(key):
                continue
            shape = source_shape(key, entry, source_lang)
            if key in seen_shapes and seen_shapes[key]["kind"] != shape["kind"]:
                raise FlatFileError(f"{key!r} has different shapes in different catalogs")
            seen_shapes[key] = shape
            current = existing_translation(entry, lang, shape)

            item: dict[str, object] = {}
            if entry.get("comment"):
                item["comment"] = entry["comment"]

            if shape["kind"] == "plural":
                forms = dict(current or {})
                if single_form and set(forms) <= set(cats):
                    # One plural form: the key is the English, the line is
                    # `"key" : ""` like everything else.
                    value = forms.get(cats[0], "")
                    if item:
                        item["value"] = value
                    else:
                        strings[key] = value
                        continue
                else:
                    item["en"] = shape["en"]
                    item["plural"] = {cat: forms.get(cat, "") for cat in cats} | {
                        cat: v for cat, v in forms.items() if cat not in cats
                    }
            elif shape["kind"] == "substitutions":
                cur = current or {"value": "", "substitutions": {}}
                item["value"] = cur["value"]
                item["substitutions"] = {}
                if single_form:
                    item["en"] = {"value": shape["en"]} | {
                        name: sub["en"].get("other", "") for name, sub in shape["substitutions"].items()
                    }
                    for name in shape["substitutions"]:
                        item["substitutions"][name] = cur["substitutions"].get(name, {}).get(cats[0], "")
                else:
                    item["en"] = shape["en"]
                    for name, sub in shape["substitutions"].items():
                        forms = cur["substitutions"].get(name, {})
                        item["substitutions"][name] = {
                            "en": sub["en"],
                            "plural": {cat: forms.get(cat, "") for cat in cats} | {
                                cat: v for cat, v in forms.items() if cat not in cats
                            },
                        }
            else:
                if shape["en"] != key:
                    item["en"] = shape["en"]
                value = current or ""
                if item:
                    item["value"] = value
                else:
                    strings[key] = value
                    continue
            # A key can already be present from an earlier catalog; keep the
            # richer of the two (a comment from one, a translation from another).
            if key in strings and isinstance(strings[key], dict):
                item = strings[key] | item  # type: ignore[operator]
            strings[key] = item

    FLAT_DIR.mkdir(exist_ok=True)
    out = FLAT_DIR / f"{lang}.json"
    flat = {
        "language": lang,
        "notes": NOTES,
        "strings": {k: strings[k] for k in sorted(strings)},
    }
    out.write_text(
        json.dumps(flat, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n",
        encoding="utf-8",
    )
    return out


# ---------------------------------------------------------------------------
# Import


def specifiers(text: str) -> tuple[list[str], bool]:
    """Normalised specifiers in `text` and whether any of them is positional.

    Flags and widths are dropped; `%1$@` and `%@` both become `@`. `%%` is a
    literal and is not a specifier.
    """
    found, positional = [], False
    for m in SPEC_RE.finditer(text):
        spec = m.group(0)
        if spec == "%%":
            continue
        if spec.startswith("%#@") or spec == "%arg":
            found.append(spec)
            continue
        if m.group(1):
            positional = True
        # Keep only length modifier + conversion: the part that must match.
        found.append(re.sub(r"^%(\d+\$)?[-+ #0]*\d*(?:\.\d+)?", "", spec))
    return sorted(found), positional


def check_specifiers(key: str, source: str, translation: str, where: str = "") -> list[str]:
    src, _ = specifiers(source)
    dst, positional = specifiers(translation)
    label = f"{key!r}{where}"
    problems = []
    if src != dst:
        problems.append(
            f"{label}: format specifiers differ.\n"
            f"    English:     {' '.join(src) or '(none)'}\n"
            f"    translation: {' '.join(dst) or '(none)'}"
        )
    elif positional:
        n_positional = sum(1 for m in SPEC_RE.finditer(translation) if m.group(1))
        n_all = len(dst)
        if n_positional != n_all:
            problems.append(f"{label}: mix of indexed (%1$@) and plain (%@) specifiers; index all or none")
    return problems


def plural_block(forms: dict[str, str]) -> dict:
    return {
        "variations": {
            "plural": {
                cat: {"stringUnit": {"state": "translated", "value": v}}
                for cat, v in forms.items()
            }
        }
    }


def read_forms(key: str, node: object, where: str) -> dict[str, str]:
    """A `plural` dict from the flat file. All empty means untranslated ({})."""
    if not isinstance(node, dict) or not all(isinstance(v, str) for v in node.values()):
        raise FlatFileError(f"{key!r}{where}: 'plural' must map plural categories to strings")
    filled = {cat: v for cat, v in node.items() if v != ""}
    if filled and len(filled) != len(node):
        raise FlatFileError(f"{key!r}{where}: fill every plural form or leave all of them empty")
    return filled


def build_localization(
    key: str, item: object, shape: dict, cats: list[str]
) -> tuple[dict | None, list[str]]:
    """Catalog `localizations[lang]` node for one flat-file entry, or None if untranslated."""
    problems: list[str] = []
    kind = shape["kind"]
    single_form = len(cats) == 1

    if isinstance(item, dict) and kind in ("plain", "plural") and "plural" not in item:
        # `{"comment": ..., "value": ...}`: unwrap to the string case.
        value = item.get("value", "")
        if not isinstance(value, str):
            raise FlatFileError(f"{key!r}: 'value' must be a string")
        item = value

    if isinstance(item, str):
        if item == "":
            return None, []
        if kind == "plural":
            if not single_form:
                raise FlatFileError(f"{key!r}: this string has plural forms; use an object with 'plural'")
            source = shape["en"].get("other") or next(iter(shape["en"].values()), "")
            problems += check_specifiers(key, source, item)
            return plural_block({cats[0]: item}), problems
        if kind != "plain":
            raise FlatFileError(f"{key!r}: expected an object with 'value' and 'substitutions'")
        problems += check_specifiers(key, shape["en"], item)
        return {"stringUnit": {"state": "translated", "value": item}}, problems

    if not isinstance(item, dict):
        raise FlatFileError(f"{key!r}: expected a string or an object")

    if kind == "plural":
        forms = read_forms(key, item["plural"], "")
        if not forms:
            return None, []
        source = shape["en"].get("other") or next(iter(shape["en"].values()), "")
        for cat, v in forms.items():
            problems += check_specifiers(key, source, v, f" [{cat}]")
        return plural_block(forms), problems

    # substitutions
    value = item.get("value", "")
    subs_in = item.get("substitutions", {})
    if not isinstance(value, str) or not isinstance(subs_in, dict):
        raise FlatFileError(f"{key!r}: needs 'value' (string) and 'substitutions' (object)")
    filled = {}
    for name in shape["substitutions"]:
        sub_item = subs_in.get(name, "")
        if isinstance(sub_item, str):
            if not single_form and sub_item != "":
                raise FlatFileError(f"{key!r} [{name}]: this language has several plural forms; use 'plural'")
            filled[name] = {cats[0]: sub_item} if sub_item else {}
        else:
            filled[name] = read_forms(key, (sub_item or {}).get("plural", {}), f" [{name}]")
    if value == "" and not any(filled.values()):
        return None, []
    if value == "" or not all(filled.values()):
        raise FlatFileError(f"{key!r}: fill 'value' and every substitution, or leave all empty")
    problems += check_specifiers(key, shape["en"], value)
    node = {"stringUnit": {"state": "translated", "value": value}, "substitutions": {}}
    for name, sub in shape["substitutions"].items():
        source = sub["en"].get("other") or next(iter(sub["en"].values()), "")
        for cat, v in filled[name].items():
            problems += check_specifiers(key, source, v, f" [{name}/{cat}]")
        node["substitutions"][name] = {
            "argNum": sub["argNum"],
            "formatSpecifier": sub["formatSpecifier"],
            **plural_block(filled[name]),
        }
    return node, problems


def import_(lang: str, check_only: bool) -> None:
    flat_path = FLAT_DIR / f"{lang}.json"
    if not flat_path.exists():
        raise FlatFileError(f"{flat_path.relative_to(REPO)} does not exist; run `export {lang}` first")
    try:
        flat = json.loads(flat_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise FlatFileError(f"{flat_path.relative_to(REPO)} is not valid JSON: {e}") from e
    if flat.get("language") != lang:
        raise FlatFileError(f"{flat_path.name} says language {flat.get('language')!r}, expected {lang!r}")
    strings = flat.get("strings")
    if not isinstance(strings, dict):
        raise FlatFileError(f"{flat_path.name}: 'strings' must be an object")

    cats = categories_for(lang)
    catalogs = [(p, load_catalog(p)) for p in CATALOGS]
    for _, catalog in catalogs:
        if catalog.get("sourceLanguage", "en") == lang:
            raise FlatFileError(f"{lang} is the source language; refusing to overwrite it")

    known_keys = {
        key for _, c in catalogs for key, entry in c["strings"].items()
        if translatable(entry) and has_words(key)
    }
    unknown = sorted(set(strings) - known_keys)
    problems: list[str] = []
    for key in unknown:
        problems.append(f"{key!r}: not in any catalog (renamed or removed in English?); re-run export")

    # Build every node first so a bad file writes nothing.
    nodes: dict[str, dict | None] = {}
    for key, item in strings.items():
        if key in unknown:
            continue
        for _, catalog in catalogs:
            entry = catalog["strings"].get(key)
            if entry is not None and translatable(entry):
                shape = source_shape(key, entry, catalog.get("sourceLanguage", "en"))
                break
        try:
            nodes[key], found = build_localization(key, item, shape, cats)
        except FlatFileError as e:
            nodes[key], found = None, [str(e)]
        problems += found

    if problems:
        raise FlatFileError(f"{len(problems)} problem(s) in {flat_path.relative_to(REPO)}:\n  " + "\n  ".join(problems))

    translated = sum(1 for n in nodes.values() if n is not None)
    missing_keys = sorted(known_keys - set(strings))
    written = removed = 0
    for path, catalog in catalogs:
        changed = False
        for key, entry in catalog["strings"].items():
            if key not in nodes:
                continue
            node = nodes[key]
            locs = entry.setdefault("localizations", {})
            if node is None:
                if lang in locs:
                    del locs[lang]
                    removed += 1
                    changed = True
            elif locs.get(lang) != node:
                locs[lang] = node
                written += 1
                changed = True
            if not locs:
                del entry["localizations"]
        if changed and not check_only:
            write_catalog(path, catalog)

    verb = "would write" if check_only else "wrote"
    print(f"{lang}: {translated}/{len(known_keys)} strings translated; "
          f"{verb} {written} catalog entries, removed {removed}")
    if missing_keys:
        print(f"note: {len(missing_keys)} catalog key(s) are not in the flat file; "
              f"re-run `export {lang}` to pick them up", file=sys.stderr)


# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p_export = sub.add_parser("export", help="write localization/<lang>.json from the catalogs")
    p_export.add_argument("lang", help="language code, e.g. zh-Hans")
    p_import = sub.add_parser("import", help="write localization/<lang>.json into the catalogs")
    p_import.add_argument("lang")
    p_import.add_argument("--check", action="store_true", help="validate without writing")
    args = parser.parse_args()

    try:
        if args.command == "export":
            out = export(args.lang)
            n = len(json.loads(out.read_text(encoding="utf-8"))["strings"])
            print(f"wrote {out.relative_to(REPO)} ({n} strings)")
        else:
            import_(args.lang, args.check)
    except FlatFileError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
