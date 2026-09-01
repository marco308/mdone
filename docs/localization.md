# Localization

mDone's user-facing text lives in String Catalogs (`.xcstrings`). English is
the source language: the English text *is* the key, so adding a language never
touches Swift.

## Adding a language

Add a translation for each key in the catalogs listed below. That is the whole
job: no project settings to change, no Swift to touch. The catalogs are the
source of truth, and a language appears in the built bundle as soon as it has
translations in them.

It needs no Mac and no Xcode either. A `.xcstrings` file is JSON, so a
translator can add their language in any text editor and open a PR against
those files alone.

A `zh-Hans` entry looks like this:

```json
"Inbox" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : { "state" : "translated", "value" : "收件箱" }
    }
  }
}
```

and a plural like this, with one `stringUnit` per category the language uses
(Chinese uses only `other`; English uses `one` and `other`):

```json
"%lld hours before due" : {
  "localizations" : {
    "zh-Hans" : {
      "variations" : {
        "plural" : {
          "other" : { "stringUnit" : { "state" : "translated", "value" : "..." } }
        }
      }
    }
  }
}
```

## Where the strings are

| Catalog | Ships in | Covers |
|---|---|---|
| `mDone/Localizable.xcstrings` | iOS and macOS apps | Every screen, alert, error, and accessibility label |
| `mDone/InfoPlist.xcstrings` | iOS and macOS apps | The permission prompts (calendar, local network) |
| `mDoneWidgets/Localizable.xcstrings` | Widget extension | Widgets, the Live Activity, widget configuration |

There are two `Localizable` catalogs because there are two bundles. This is the
one non-obvious rule in here, and it is worth reading before adding a string:

> **`mDoneShared/` compiles into both the app and the widget extension.**
> `String(localized:)` resolves against `Bundle.main`, which inside the
> extension is the *extension's* bundle, not the app's. A string used from
> `mDoneShared/` therefore has to exist in **both** catalogs. The extraction
> script handles this automatically, because it extracts per target. If you
> hand-edit a catalog instead, a missing entry fails silently by falling back
> to English.

`InfoPlist.xcstrings` is the exception to all of this: nothing extracts it, so
its entries are marked `manual` and are kept in step with `mDone/Info.plist` by
hand. If you add or reword a usage description, edit both.

## Refreshing the catalogs after changing copy

```bash
./scripts/update-string-catalogs.sh
```

This builds both platforms and merges the newly extracted strings into the
catalogs. It never discards translations: a key the compiler no longer finds
is marked `stale` rather than deleted, since the string may simply be behind a
platform or `#if` branch that this run did not compile.

Xcode's IDE does this sync on every build. `xcodebuild` does not, which is why
the script exists: it reads the same `.stringsdata` the IDE reads.

## Writing localizable Swift

Most SwiftUI initializers take a `LocalizedStringKey`, so a plain literal is
already localizable and gets extracted with no extra work:

```swift
Text("No tasks due today")           // extracted
Button("Add Task") { ... }           // extracted
.navigationTitle("Inbox")            // extracted
.accessibilityLabel("Show board")    // extracted
```

A `String` is **not**. Anywhere you build a `String` that a person will read,
wrap it:

```swift
var label: String {
    switch self {
    case .compact: String(localized: "Compact")   // extracted
    case .standard: "Standard"                    // NOT extracted, ships as English
    }
}
```

The same applies to `LocalizedError.errorDescription`, computed display
properties, and anything passed to a view that takes `String` rather than
`LocalizedStringKey`.

Two things worth doing while you are there:

- **Don't concatenate sentences.** Word order differs between languages, so a
  prefix glued onto a sentence cannot be translated correctly. Write each
  variant as its own complete key, even when that repeats words in English.
- **Let the catalog handle plurals.** Write one key with the count interpolated
  and add a plural variation in the catalog, rather than a `count == 1 ? :`
  ternary in Swift. English has two plural forms and Chinese has one; other
  languages have up to six, and only the catalog can express that.

```swift
// Good: one key, plural variations live in the catalog.
String(localized: "You're offline. \(pending) changes will sync when you reconnect.")

// Bad: hard-codes the assumption that a language has exactly two plural forms.
pending == 1 ? "1 change will sync" : "\(pending) changes will sync"
```

## Enums whose raw value was also their display text

Several display enums used their `String` raw value as UI copy. Those now keep
the raw value as stable identity and expose a separate localized `label`, so
translating the UI cannot quietly change sorting, filtering, or persistence.
Use `.label` for display and `.rawValue` for logic.

## What is not in the catalogs

- **Vikunja filter DSL strings** (`priority = 3 && done = false`). Server
  syntax, not user copy.
- **SF Symbol names**, widget `kind` identifiers, and API field names.
- **Data from the server**: task titles, project names, and label names are the
  user's own content and are shown as-is.
- **App Store metadata**. Listing text, keywords, and screenshots are localized
  in App Store Connect, not here.

## Known gaps

- `DefaultDueTimePreference` renders its options as literal strings
  (`"9:00 AM"`) rather than formatting a time for the locale. Translators can
  render these correctly, but formatting them properly would be better and
  would drop six keys.
- The widget extension's `CFBundleDisplayName` ("mDone Focus", set in
  `project.yml`) is not localized. It would need its own
  `mDoneWidgets/InfoPlist.xcstrings`.
- `ProjectBoardView`'s column accessibility label interpolates an
  already-formatted count string (`"3"` or `"3/5"`), so it cannot carry a
  plural variation.
