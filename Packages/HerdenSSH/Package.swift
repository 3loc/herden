// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HerdenSSH",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(name: "HerdenSSH", targets: ["HerdenSSH"]),
    ],
    targets: [
        .binaryTarget(
            name: "COpenSSL",
            path: "Artifacts/COpenSSL.xcframework"
        ),
        .binaryTarget(
            name: "CLibSSH2",
            path: "Artifacts/CLibSSH2.xcframework"
        ),
        .target(
            name: "CHerdenSSHSupport",
            dependencies: ["CLibSSH2"]
        ),
        .target(
            name: "HerdenSSH",
            dependencies: ["CLibSSH2", "COpenSSL", "CHerdenSSHSupport"]
        ),
        .testTarget(
            name: "HerdenSSHTests",
            dependencies: ["HerdenSSH"]
        ),
    ]
)
