// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DailyReview",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DailyReview",
            path: "Sources/DailyReview",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/DailyReview/Resources/Info.plist"
                ])
            ]
        )
    ]
)
