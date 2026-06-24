// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ReduxCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReduxCore",
            targets: ["ReduxCore"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "509.0.0"
        )
    ],
    targets: [
        // Macro compiler plugin — runs at build time only, zero runtime overhead
        .macro(
            name: "ReduxCoreMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        // Main library — exports the macro declaration alongside the runtime types
        .target(
            name: "ReduxCore",
            dependencies: ["ReduxCoreMacros"]
        ),
        .testTarget(
            name: "ReduxCoreTests",
            dependencies: ["ReduxCore"]
        ),
        .testTarget(
            name: "ReduxCoreMacroTests",
            dependencies: [
                "ReduxCoreMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ]
)
