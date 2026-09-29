// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Maccelerate",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Maccelerate", targets: ["Maccelerate"]),
        .executable(name: "ISSCli", targets: ["ISSCli"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "ISS",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "Maccelerate",
            dependencies: ["ISS", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "ISSCli",
            dependencies: ["ISS"],
            path: "Sources/ISSCli"
        ),
        .testTarget(
            name: "ISSTests",
            dependencies: ["ISS"]
        ),
        .testTarget(
            name: "MaccelerateTests",
            dependencies: ["Maccelerate"]
        )
    ]
)
