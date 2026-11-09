// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Dictee",
    platforms: [.macOS(.v26)],
    targets: [
        // Logique pure (sans interface, sans micro) : testable à part.
        .target(name: "DicteeCore"),
        // Garde-fou Objective-C : rattrape les exceptions NSException d'AVFoundation (Swift ne le peut pas).
        .target(name: "VerbeObjC"),
        // L'app elle-même. Mode Swift 5 : les rappels d'AppKit / CoreGraphics / AVFoundation
        // (tap clavier, tap micro) arrivent sur des fils que la vérification stricte de Swift 6 ne sait pas suivre.
        .executableTarget(
            name: "Dictee",
            dependencies: ["DicteeCore", "VerbeObjC"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Contrôles de logique : `swift run DicteeControles`.
        .executableTarget(name: "DicteeControles", dependencies: ["DicteeCore"]),
    ]
)
