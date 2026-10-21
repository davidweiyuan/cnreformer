// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CNReformerCore", products: [.library(name: "CNReformerCore", targets: ["CNReformerCore"])], targets: [.target(name: "CNReformerCore", path: "Sources", exclude: ["CNReformerApp.swift", "LibraryStore.swift", "BibleReadingView.swift", "BlogLibraryView.swift"], sources: ["LibraryModel.swift", "BibleSource.swift", "BlogPost.swift"]), .testTarget(name: "CNReformerCoreTests", dependencies: ["CNReformerCore"], path: "Tests")])
