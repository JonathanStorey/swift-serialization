# swift-serialization

BSON and extended JSON serialization for Swift.

## Installation

```swift
.package(url: "https://github.com/JonathanStorey/swift-serialization", branch: "main")
```

Then add the product to a target:

```swift
.product(name: "Serialization", package: "swift-serialization")
```

```swift
import Serialization
```

## Requirements

- Swift 6.0 or later (Xcode 16+)
- macOS 10.15, iOS 13, tvOS 13, watchOS 6, visionOS 1

## Testing

Tests use [Swift Testing](https://github.com/swiftlang/swift-testing).

```sh
swift test
```
