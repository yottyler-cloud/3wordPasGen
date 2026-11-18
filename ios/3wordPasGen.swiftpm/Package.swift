// swift-tools-version: 5.9

// Swift Playgrounds（iPad / Mac）と Xcode のどちらでも開ける App パッケージです。

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "3wordPasGen",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "3wordPasGen",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.ThreeWordPasGen",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .keyboard),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
