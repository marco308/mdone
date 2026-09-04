# Localization

mDone's user-facing text lives in String Catalogs (`.xcstrings`). English is
the source language: the English text *is* the key, so adding a language never
touches Swift.

## Adding a language

Translators never edit the catalogs directly. Each language has one flat file,
`localization/<lang>.json`, of `"English text" : "translation"` pairs, and
`scripts/localization.py` moves translations between that file and the
catalogs. The flat file needs no Mac and no Xcode: it is plain JSON, one line
per string, and a PR that touches only that file is a complete contribution.

```bash
./scripts/localization.py export zh-Hans          # catalogs -> localization/zh-Hans.json
./scripts/localization.py import zh-Hans          # localization/zh-Hans.json -> catalogs
./scripts/localization.py import zh-Hans --check  # validate only, writes nothing
```

To start a language, run `export` once and commit the file it writes. The
translator fills in the right-hand sides, in any order, over as many PRs as
they like. A translation left as `""` falls back to English. The maintainer
runs `import` on each PR, which is what puts the language in the built bundle;
if the translator only sends the flat file, that is expected.

Most entries are one line:

```json
"Inbox" : "收件箱",
```

For a language with a single plural form, such as Chinese, a string with a
count is the same one line, with the placeholder kept:

```json
"%lld hours before due" : "%lld 小时前到期",
```

For a language with several plural forms, export writes one slot per form the
language uses and shows the English forms as context:

```json
"%lld hours before due" : {
  "en" : { "one" : "%lld hour before due", "other" : "%lld hours before due" },
  "plural" : { "one" : "", "other" : "" }
},
```

`en` and `comment` fields are context written by `export` and ignored by
`import`. The two InfoPlist keys are the one place the key is not the English
text, so those carry an `en` field too. Keys with no words in them, like
`"%@, %@"`, are left out of the file because there is nothing to translate.

`import` validates before it writes anything. It refuses a file where a
translation drops or changes a format specifier (`%@`, `%lld`), mixes indexed
(`%1$@`) and plain specifiers in one string, fills only some of a string's
plural forms, or names a key that no catalog has. A dropped `%@` is a crash at
runtime, not a typo, which is why this is an error and not a warning.

`export` is safe to re-run at any time: it keeps every translation already in
the catalogs and adds the keys that new copy introduced. `import` writes a
translation to every catalog that has the key, which is what makes the
two-bundle rule below the maintainer's problem rather than the translator's.

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

After refreshing, re-run `./scripts/localization.py export <lang>` for each
language in `localization/` so translators see the new keys.

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
