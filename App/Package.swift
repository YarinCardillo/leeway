// swift-tools-version: 6.0
import PackageDescription
import Foundation

let package = Package(
    name: "LeewayAppModel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppModel", targets: ["AppModel"]),
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    dependencies: [.package(name: "LeewayCore", path: ProcessInfo.processInfo.environment["LEEWAY_CORE_PACKAGE"] ?? "..")],
    targets: [
        .target(name: "AppModel", dependencies: [.product(name: "LeewayCore", package: "LeewayCore")]),
        .target(name: "LeewayPresentation", dependencies: ["AppModel"], path: "Sources/LeewayApp",
                exclude: ["AccountsSettings.swift", "LeewayApp.swift", "LoginController.swift", "SettingsView.swift", "UpdateController.swift", "GeneralSettings.swift", "UpdatesSettings.swift", "SettingsLayout.swift"], sources: ["Localizer.swift", "UsageMenu.swift", "AccountMenuRow.swift", "AccountDetail.swift", "DetailInsets.swift", "WeeklyChart.swift", "UsageChartDescriptor.swift", "NativeUsageMeter.swift", "ForecastMeter.swift", "SettingsWindow.swift", "NativeStatusItem.swift", "TargetRangeControl.swift", "AccountNameField.swift"], resources: [.process("Resources")]),
        .target(name: "AppCore", dependencies: ["AppModel", .product(name: "LeewayCore", package: "LeewayCore")]),
        .testTarget(name: "AppModelTests", dependencies: ["AppModel", "AppCore", "LeewayPresentation", .product(name: "LeewayCore", package: "LeewayCore")], path: "Tests")
    ]
)
