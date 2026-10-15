// swift-tools-version: 6.0
// MonoKit — платформенно-независимое финансовое ядро MONO Finance.
// Собирается и тестируется на macOS (Xcode / `swift test`) и на Linux (`swift test`).
import PackageDescription

let package = Package(
    name: "MonoKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        // Один продукт для приложения: все модули подключаются одной зависимостью.
        .library(
            name: "MonoKit",
            targets: ["MonoCore", "MonoStorage", "MonoAnalytics", "MonoIntelligence", "MonoImport", "MonoBankSync"]
        )
    ],
    targets: [
        // На Apple-платформах используется системный модуль SQLite3.
        // На Linux — этот системный модуль поверх libsqlite3.
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(name: "MonoCore"),
        .target(
            name: "MonoStorage",
            dependencies: [
                "MonoCore",
                .target(name: "CSQLite", condition: .when(platforms: [.linux]))
            ]
        ),
        .target(name: "MonoAnalytics", dependencies: ["MonoCore"]),
        .target(name: "MonoIntelligence", dependencies: ["MonoCore", "MonoAnalytics"]),
        .target(name: "MonoImport", dependencies: ["MonoCore", "MonoIntelligence"]),
        .target(name: "MonoBankSync", dependencies: ["MonoCore"]),

        .testTarget(name: "MonoCoreTests", dependencies: ["MonoCore"]),
        .testTarget(name: "MonoStorageTests", dependencies: ["MonoStorage"]),
        .testTarget(name: "MonoAnalyticsTests", dependencies: ["MonoAnalytics"]),
        .testTarget(name: "MonoIntelligenceTests", dependencies: ["MonoIntelligence", "MonoStorage"]),
        .testTarget(name: "MonoImportTests", dependencies: ["MonoImport", "MonoStorage"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MonoBankSyncTests", dependencies: ["MonoBankSync"])
    ],
    swiftLanguageModes: [.v6]
)
