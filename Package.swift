// swift-tools-version: 6.0
// 明目 (Iris) — a native macOS eye-care reminder app.
//
// 兼容性说明：
// - 代码里所有 API 都按 macOS 11 (Big Sur) 的可用性编写（见 Design/Compat.swift），
//   新系统的能力在运行时按 #available 启用。
// - Swift 6.4 工具链本身把最低部署目标钳制在 12.0，因此实际产物为 macOS 12+；
//   换用较旧的工具链编译即可下探到 11。
// - 已在 macOS 26/27 上编译验证。
//
// 语言模式显式使用 Swift 5：本 App 是 AppKit + Combine + SwiftUI 混编，
// 全部运行在主线程，不必与 Swift 6 严格并发检查缠斗。
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Iris",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "Iris", targets: ["Iris"]),
        .executable(name: "IrisSnapshot", targets: ["IrisSnapshot"]),
    ],
    targets: [
        .target(
            name: "IrisKit",
            path: "Sources/IrisKit",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "Iris",
            dependencies: ["IrisKit"],
            path: "Sources/Iris",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "IrisOverlayBench",
            dependencies: ["IrisKit"],
            path: "Sources/IrisOverlayBench",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "IrisSnapshot",
            dependencies: ["IrisKit"],
            path: "Sources/IrisSnapshot",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "IrisKitTests",
            dependencies: ["IrisKit"],
            path: "Tests/IrisKitTests",
            swiftSettings: swift5
        ),
    ]
)
