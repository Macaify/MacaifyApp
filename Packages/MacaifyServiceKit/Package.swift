// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacaifyServiceKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MacaifyServiceKit",
            targets: ["MacaifyServiceKit"]
        ),
        .executable(
            name: "MacaifyServiceKitRunner",
            targets: ["MacaifyServiceKitRunner"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Moya/Moya.git", from: "15.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MacaifyServiceKit",
            dependencies: [
                .product(name: "Moya", package: "Moya")
            ]
        ),
        .testTarget(
            name: "MacaifyServiceKitTests",
            dependencies: [
                "MacaifyServiceKit",
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .executableTarget(
            name: "MacaifyServiceKitRunner",
            dependencies: [
                "MacaifyServiceKit",
                .product(name: "Alamofire", package: "Alamofire")
            ]
        )
    ]
)
