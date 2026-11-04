// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NutritionCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "NutritionCore", targets: ["NutritionCore"])],
    targets: [
        .target(name: "NutritionCore"),
        .testTarget(name: "NutritionCoreTests", dependencies: ["NutritionCore"])
    ]
)
