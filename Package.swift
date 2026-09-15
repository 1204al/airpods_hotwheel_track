// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "airpods-hotwheels-track",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PodTrackCore", targets: ["PodTrackCore"]),
        .executable(name: "PodTrack", targets: ["PodTrack"])
    ],
    targets: [
        .target(name: "PodTrackCore"),
        .executableTarget(name: "PodTrack", dependencies: ["PodTrackCore"], resources: [.process("Resources")], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Resources/Info.plist"])
        ]),
        .testTarget(name: "PodTrackCoreTests", dependencies: ["PodTrackCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PodTrackAppTests", dependencies: ["PodTrack", "PodTrackCore"])
    ]
)
