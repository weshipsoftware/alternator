// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name      : "alternator",
  platforms : [.macOS(.v13)],

  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser",     from: "1.5.0"),
    .package(url: "https://github.com/jarrodtaylor/fs-diff-stream.git", from: "1.0.0"),
    .package(url: "https://github.com/johnsundell/ink.git",             from: "0.6.0"),
    .package(url: "git@github.com:simonbs/Prettier.git",                from: "0.1.0")
  ],

  targets: [
    .executableTarget(
      name: "alternator",
      dependencies: [
        .product(name: "ArgumentParser",  package: "swift-argument-parser"),
        .product(name: "FSDiffStream",    package: "fs-diff-stream"),
        .product(name: "Ink",             package: "ink"),
        .product(name: "Prettier",        package: "Prettier"),
        .product(name: "PrettierBabel",   package: "Prettier"),
        .product(name: "PrettierHTML",    package: "Prettier"),
        .product(name: "PrettierPostCSS", package: "Prettier")
      ]
)])