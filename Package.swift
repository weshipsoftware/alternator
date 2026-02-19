// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Alternator",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    .package(url: "https://github.com/JohnSundell/Ink",             from: "0.6.0")],
  targets: [
    .executableTarget(
      name: "Alternator",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Ink",            package: "Ink")],
      path: ".",
      exclude: ["README.md"],
      sources: ["Alternator.swift"])])