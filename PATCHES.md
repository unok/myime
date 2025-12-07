# Patches for Windows Swift 6.2.1 Compatibility

This document describes the patches required to build MyIME on Windows with Swift 6.2.1.

## swift-tokenizers Patch

Due to a Swift 6.2.1 compiler bug (SIL memory lifetime failure), we need to patch swift-tokenizers.

### Setup

1. Clone swift-tokenizers:
```bash
cd src
git clone https://github.com/ensan-hcl/swift-tokenizers.git
```

2. Apply the patch to `Sources/Tokenizers/Trie.swift`:

```swift
// Change from:
lazy var iterator = text.makeIterator() as any IteratorProtocol<T>

// To:
var iterator: AnyIterator<T>

// Add explicit initializer:
init(node: TrieNode<T>, text: any Sequence<T>) {
    self.node = node
    self.text = text
    self.seq = []
    var textIterator = text.makeIterator()
    self.iterator = AnyIterator {
        textIterator.next()
    }
}
```

## AzooKeyKanaKanjiConverter Setup

1. Clone AzooKeyKanaKanjiConverter v0.11.1:
```bash
cd src
git clone https://github.com/azooKey/AzooKeyKanaKanjiConverter.git AzooKeyKanaKanjiConverter-local
cd AzooKeyKanaKanjiConverter-local
git checkout v0.11.1
```

2. Update `Package.swift` to use local swift-tokenizers:
```swift
// Change from:
.package(url: "https://github.com/ensan-hcl/swift-tokenizers", from: "0.0.1")

// To:
.package(path: "../swift-tokenizers")
```

## Building

Use `build-swift-standalone.bat` which references `Package-local.swift` configured to use the local patched dependencies.

## Note

These patches are necessary until:
1. Swift compiler bug is fixed in a future version
2. swift-tokenizers upstream accepts a fix for the issue