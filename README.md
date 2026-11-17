# swift-serialization

Swift-first JSON for `Codable` types: a value tree that matches `JSONEncoder`,
schemas that describe a type and tell you whether two versions of it can read
each other's data, and differences between two values that can be applied,
inverted and stored.

## Installation

```swift
.package(url: "https://github.com/JonathanStorey/swift-serialization", from: "0.1.0")
```

Then add the product to a target:

```swift
.product(name: "Serialization", package: "swift-serialization")
```

```swift
import Serialization
```

## JSONRepresentation

`JSONRepresentation` is a JSON value as an enum: `null`, `bool`, `number`,
`string`, `array` and `object`. Numbers keep their exact text, so a 64-bit
integer never loses precision, and objects keep their key order while
comparing equal regardless of it.

```swift
struct Settings: Codable {
    var theme: String
    var fontSize: Int
    var tags: [String]
}

let json = try JSONRepresentation(Settings(theme: "dark", fontSize: 14, tags: ["a"]))
print(json)                      // {"theme":"dark","fontSize":14,"tags":["a"]}
json["theme"]                    // Optional(.string("dark"))
json["tags"]?[0]                 // Optional(.string("a"))

let settings = try json.decode(Settings.self)
```

`init(_:)` produces the same value as a default `JSONEncoder()`, built
directly as a tree. `decode(_:)` reads it back with `JSONDecoder` after
checking that every number is valid JSON and no object repeats a key.

Values can also be written as literals:

```swift
let value: JSONRepresentation = ["name": "Ada", "scores": [1, 2.5], "nickname": nil]
```

`JSONRepresentation` is `Codable`, `Hashable` and `Sendable`. Encoding a
representation with `JSONEncoder` writes the same bytes as encoding the
original value, as long as both use `.sortedKeys`. Without it, `JSONEncoder`
does not promise a key order.

### Paths

A `JSONRepresentation.Path` locates a value inside another. It is a
collection of `.key` and `.index` segments, written as array literals and
described in JSONPath notation.

```swift
var json: JSONRepresentation = ["rooms": [["name": "A"], ["name": "B"]]]
let path: JSONRepresentation.Path = ["rooms", 1, "name"]
print(path)                      // $.rooms[1].name
json[path]                       // Optional(.string("B"))
json[path] = "C"                 // replaces the value at the path
JSONRepresentation.Path("$.rooms[0].name") // parses the description back
```

Each segment is a `CodingKey`, so a `DecodingError`'s `codingPath` converts
to a path that points at the failing value.

## JSONSchema

`JSONSchema(for:)` describes the JSON a default `JSONEncoder()` writes for a
`Decodable` type. Property names come from `CodingKeys`, optional properties
are marked optional, and `String` and `Int` raw-value enums list their cases.

```swift
let schema = try JSONSchema(for: Settings.self)
print(schema)                    // standard JSON Schema text
schema.json(.strict)             // every property required, nullable optionals,
                                 // and "additionalProperties": false
```

### Compatibility

The three checks follow the rules `JSONDecoder` actually applies: extra keys
are ignored, an optional property may be missing or `null`, an integer is
accepted where a number is expected, and enum cases must cover what the other
side can send.

```swift
let saved = try JSONSchema(for: SettingsV1.self)
let current = try JSONSchema(for: SettingsV2.self)

current.isSuperset(of: saved)    // V2 can read everything V1 wrote
current.isSubset(of: saved)      // V1 can read everything V2 writes
current.isCompatible(with: saved) // both directions
```

`contains(_:)` asks the same question of a single value: whether the type
behind the schema can decode it.

```swift
current.contains(storedJSON)     // V2 can decode this stored value
```

### Identity

`id` is a stable `UUID` computed from the schema alone. It is the same on every
platform, launch and Swift version, and equal schemas share it, so it works as
a version tag for stored data. Compatibility is not transitive, so use the
checks above rather than comparing ids when versions differ.

A schema stored with `Codable` reads back to an equal schema with the same
`id`.

## JSONDifference

`difference(from:)` lists the changes that turn one value into another.
Changes are deep, so an edit inside a nested object is reported at its own
path, and numbers compare by value, so `1` and `1.0` are not a change.

```swift
let old: JSONRepresentation = ["keep": 1, "drop": "x", "change": "A"]
let new: JSONRepresentation = ["keep": 1, "change": "B", "add": true]

let difference = new.difference(from: old)
print(difference)
// - $.drop: "x"
// ~ $.change: "A" → "B"
// + $.add: true

old.applying(difference) == new             // true
new.applying(difference.inverted()) == old  // true
```

A `JSONDifference` is a collection of `Change` values, removals first, each
either `.remove` or `.insert` with a `path`, an `element` and an optional
`associatedWith` segment. A linked removal and insertion form a replacement
(`~`) when their elements differ, or a move (`>`) when they are the same.
Moves are inferred, so a reordered array or a renamed key is reported as
moves rather than as removals and insertions:

```text
> $[2] → $[0]: "z"
> $.nickname → $.alias: {"first":"Ada"}
```

`applying(_:)` returns `nil` when the difference does not fit, such as when a
removed value is not where the difference expects it.

### Differences a type can see

`difference(from:as:)` compares two values the way a `Decodable` type reads
them. Keys the type does not declare are ignored, and an optional property
that is missing or `null` counts as unchanged. This suits stored data, where
the question is what changed for the current version of the type.

```swift
let stored: JSONRepresentation = ["theme": "dark", "fontSize": 14, "tags": ["a"], "legacy": true]
let current = try JSONRepresentation(Settings(theme: "light", fontSize: 14, tags: ["a"]))

print(current.difference(from: stored))
// ~ $.theme: "dark" → "light"
// - $.legacy: true

print(try current.difference(from: stored, as: Settings.self))
// ~ $.theme: "dark" → "light"
```

Applying it to `stored` gives a value that `Settings` decodes the same as
`current`. It throws when `JSONSchema(for:)` cannot describe the type.

### Storing a difference

`JSONDifference` is `Codable`, `Hashable` and `Sendable`. It encodes as an
array of changes, and its `description` is the readable form shown above.

## CloudKit records

### References

`@Reference` stores a link to another `Identifiable` model as that model's
`id`, ready for CloudKit's `CKRecord.Reference`. The generic target is
inferred from the type you pass.

```swift
struct Folder: Codable, Identifiable {
    var id: UUID
}

struct Note: Codable, Identifiable {
    var id: UUID
    @Reference(to: Folder.self, action: .deleteSelf) var folder: Folder.ID? = nil
}

var note = Note(id: UUID(), folder: folder.id)
note.folder                      // Optional(folder.id)
note.$folder.action              // .deleteSelf
```

The wrapper encodes a `RecordRepresentation.Reference`, the target's record
name with its action, so `JSONEncoder` writes
`{"folder":{"action":"deleteSelf","recordName":"..."},"id":"..."}`. A `nil`
reference is left out, and a missing key decodes as `nil`. The target's `id`
must be a `UUID`, and the record name is its `uuidString`, which is always a
valid CloudKit record name and reads back exactly.

A decoded reference keeps the action it was saved with. Swift does not pass
the attribute's arguments to `init(from:)`, so a reference decoded as `nil`
has the action `.none` until you set `$folder.action`.

### Reference lists

`@References` holds a short list of references stored on the record itself.
It works like `@Reference`, with one action for every element.

```swift
@References(to: Tag.self) var tags: [UUID] = []
```

An empty list is left out, and a missing key decodes as an empty list.

### Relationships

`@Relationship` holds a to-many relationship stored as link records instead
of a field, so it has no size limit. Each link is a
`RecordRepresentation.Relationship` named by the declaring side, as in
`"Note.tags"`, with the declaring record's id and then the target's. Its id
is a stable hash of those three values, so the same link always maps to the
same record, and the target never has to declare an inverse.

```swift
struct Note: Codable, Identifiable {
    var id: UUID
    @Relationship(to: Tag.self) var tags: [UUID] = []
}

note.$tags.append(newTag)               // a new tag, created with the note
note.tags.append(existing.id)           // an existing tag, linked by id
note.$tags.inserted                     // [newTag]
note.$tags.added                        // [newTag.id, existing.id]
note.$tags.removed                      // ids unlinked since the last save
```

The wrapper tracks changes since the last save, so the next save can create
the inserted tags and add or delete their links. Each link stores an integer
`order` that keeps its value while the orders still increase, so a delete
writes nothing else, an append writes one link, and a move writes only the
links that no longer sort. A held tag is only created,
never updated, so a stale copy cannot overwrite an edit. It encodes as
`{"ids":[...]}`, plus the pending changes while there are any.

### Encrypted values

`@Encrypted` marks a property that CloudKit stores encrypted end to end. It
encodes exactly as its value does, so JSON is unchanged.

```swift
@Encrypted var body: String = ""
@Encrypted var pin: Int? = nil
```

CloudKit can encrypt strings, numbers, dates, data, locations and lists of
them, but not references or assets. Encrypted fields cannot be queried,
sorted or indexed.

### Assets

`@Asset` holds a file that CloudKit stores as a `CKAsset`. The property reads
and writes `Data`, and its projected value is the file's URL, for APIs that
work with files.

```swift
struct Note: Codable {
    @Asset var attachment: Data? = nil
}

note.attachment = bytes                 // writes a temporary file
note.$attachment = fileURL              // or points at a file you own
let pdf = PDFDocument(url: note.$attachment!)
```

Reading `attachment` maps the file into memory, so bytes load only as they
are used. The wrapper encodes the URL, not the bytes. A URL is local to one
device, and CloudKit hands back a new one each time a record is fetched.

## Requirements

- Swift 6.0 or later (Xcode 16+)
- macOS 10.15, iOS 13, tvOS 13, watchOS 6, visionOS 1

## Testing

Tests use [Swift Testing](https://github.com/swiftlang/swift-testing).

```sh
swift test
```
