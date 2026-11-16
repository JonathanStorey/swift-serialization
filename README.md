# swift-serialization

Swift-first JSON for `Codable` types: a value tree that matches `JSONEncoder`,
and schemas that describe a type and tell you whether two versions of it can
read each other's data.

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

`JSONRepresentation` is `Codable`, `Hashable` and `Sendable`.

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

### Identity

`id` is a stable `UUID` computed from the schema alone. It is the same on every
platform, launch and Swift version, and equal schemas share it, so it works as
a version tag for stored data. Compatibility is not transitive, so use the
checks above rather than comparing ids when versions differ.

A schema stored with `Codable` reads back to an equal schema with the same
`id`.

## Requirements

- Swift 6.0 or later (Xcode 16+)
- macOS 10.15, iOS 13, tvOS 13, watchOS 6, visionOS 1

## Testing

Tests use [Swift Testing](https://github.com/swiftlang/swift-testing).

```sh
swift test
```
