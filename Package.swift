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
        .target(name: "StatisticsModel"),
        .executableTarget(
            name: "Maccelerate",
            dependencies: ["ISS", "StatisticsModel", .product(name: "Sparkle", package: "Sparkle")],
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
        .testTarget(name: "StatisticsModelTests", dependencies: ["StatisticsModel"]),
        .testTarget(
            name: "MaccelerateTests",
            dependencies: ["Maccelerate", "ISS", "StatisticsModel"]
        )
    ]
)
