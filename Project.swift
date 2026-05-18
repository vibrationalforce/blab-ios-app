import ProjectDescription

/// Echoelmusic - Bio-Reactive Audio-Visual Platform
/// Complete Tuist project definition for all Apple platforms
let project = Project(
    name: "Echoelmusic",
    organizationName: "Echoelmusic Technologies",
    options: .options(
        automaticSchemesOptions: .enabled(
            codeCoverageEnabled: true,
            testingOptions: [.parallelizable, .randomExecutionOrdering]
        ),
        disableBundleAccessors: false,
        disableSynthesizedResourceAccessors: false,
        textSettings: .textSettings(
            usesTabs: false,
            indentWidth: 4,
            tabWidth: 4
        )
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ENABLE_PREVIEWS": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "WATCHOS_DEPLOYMENT_TARGET": "10.0",
            "TVOS_DEPLOYMENT_TARGET": "17.0",
            "XROS_DEPLOYMENT_TARGET": "1.0",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "ENABLE_TESTABILITY": "YES",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "$(DEVELOPMENT_TEAM)",
        ],
        configurations: [
            .debug(name: "Debug", settings: [
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                "GCC_OPTIMIZATION_LEVEL": "0",
                "ONLY_ACTIVE_ARCH": "YES",
            ]),
            .release(name: "Release", settings: [
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "GCC_OPTIMIZATION_LEVEL": "s",
                "SWIFT_COMPILATION_MODE": "wholemodule",
                "VALIDATE_PRODUCT": "YES",
            ])
        ],
        defaultSettings: .recommended
    ),
    targets: [
        // MARK: - Main iOS App Target
        Target(
            name: "Echoelmusic",
            platform: .iOS,
            product: .app,
            bundleId: "com.echoelmusic.app",
            deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone, .ipad]),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic",
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)",
                "UILaunchScreen": [:],
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false
                ],
                "UIBackgroundModes": [
                    "audio",
                    "processing",
                    "bluetooth-central",
                    "bluetooth-peripheral",
                    "fetch",
                    "remote-notification"
                ],
                "NSHealthShareUsageDescription": "Echoelmusic uses your heart rate and HRV data to create bio-reactive audio-visual experiences. This data never leaves your device.",
                "NSHealthUpdateUsageDescription": "Echoelmusic may update your Mindful Minutes during meditation sessions.",
                "NSCameraUsageDescription": "Echoelmusic uses your camera for facial expression tracking to control audio-visual parameters.",
                "NSMicrophoneUsageDescription": "Echoelmusic uses your microphone for voice-to-sound synthesis and pitch detection.",
                "NSBluetoothAlwaysUsageDescription": "Echoelmusic connects to MIDI controllers, heart rate monitors, and audio devices via Bluetooth.",
                "NSLocalNetworkUsageDescription": "Echoelmusic uses local network for OSC, Art-Net, DMX lighting control, and multi-device collaboration.",
                "NSMotionUsageDescription": "Echoelmusic uses motion data for gesture-based audio control.",
                "NSFaceIDUsageDescription": "Echoelmusic uses Face ID for secure authentication.",
                "NSLocationWhenInUseUsageDescription": "Echoelmusic may use location to find nearby collaboration sessions.",
                "UIRequiredDeviceCapabilities": [
                    "armv7",
                    "arm64"
                ],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight"
                ],
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight"
                ],
                "ITSAppUsesNonExemptEncryption": false,
                "NSAppTransportSecurity": [
                    "NSAllowsArbitraryLoads": false,
                    "NSAllowsLocalNetworking": true
                ],
                "UIUserInterfaceStyle": "Automatic",
                "UISupportsDocumentBrowser": true
            ]),
            sources: [
                "Sources/Echoelmusic/**/*.swift",
                "Sources/Echoelmusic/**/*.metal"
            ],
            resources: [
                "Resources/**",
                "Sources/Echoelmusic/Resources/**"
            ],
            entitlements: .file(path: "Echoelmusic.entitlements"),
            dependencies: [
                .target(name: "EchoelmusicAUv3"),
                .target(name: "EchoelVoice"),
                .target(name: "EchoelmusicWidgets"),
                .target(name: "EchoelmusicWatch"),
                .target(name: "EchoelmusicTV")
            ],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "SUPPORTS_MACCATALYST": "YES",
                    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "YES",
                    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.music",
                    "ENABLE_BITCODE": "NO",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
                    "MTL_FAST_MATH": "YES",
                    "CLANG_ENABLE_MODULES": "YES",
                    "SWIFT_EMIT_LOC_STRINGS": "YES"
                ],
                configurations: [
                    .debug(name: "Debug"),
                    .release(name: "Release")
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - Widget Extension
        Target(
            name: "EchoelmusicWidgets",
            platform: .iOS,
            product: .appExtension,
            bundleId: "com.echoelmusic.app.widgets",
            deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone, .ipad]),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic Widgets",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ],
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)"
            ]),
            sources: [
                "Sources/Echoelmusic/Widgets/**/*.swift"
            ],
            resources: [
                "Sources/Echoelmusic/Widgets/Assets.xcassets"
            ],
            entitlements: .file(path: "EchoelmusicWidgets.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app.widgets",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "SKIP_INSTALL": "YES"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - watchOS App
        Target(
            name: "EchoelmusicWatch",
            platform: .watchOS,
            product: .watch2App,
            bundleId: "com.echoelmusic.app.watchkitapp",
            deploymentTarget: .watchOS(targetVersion: "10.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic",
                "WKApplication": true,
                "WKCompanionAppBundleIdentifier": "com.echoelmusic.app",
                "WKWatchOnly": false,
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)",
                "NSHealthShareUsageDescription": "Echoelmusic Watch uses your heart rate and HRV data for bio-reactive experiences.",
                "NSHealthUpdateUsageDescription": "Echoelmusic Watch may update your Mindful Minutes."
            ]),
            sources: [
                "Sources/Echoelmusic/WatchOS/**/*.swift"
            ],
            resources: [
                "Sources/Echoelmusic/WatchOS/Assets.xcassets"
            ],
            entitlements: .file(path: "EchoelmusicWatch.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app.watchkitapp",
                    "TARGETED_DEVICE_FAMILY": "4",
                    "SKIP_INSTALL": "YES",
                    "WATCHOS_DEPLOYMENT_TARGET": "10.0"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - tvOS App
        Target(
            name: "EchoelmusicTV",
            platform: .tvOS,
            product: .app,
            bundleId: "com.echoelmusic.app",
            deploymentTarget: .tvOS(targetVersion: "17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic",
                "UILaunchScreen": [:],
                "UIUserInterfaceStyle": "Automatic",
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)",
                "UIBackgroundModes": ["audio"],
                "NSMicrophoneUsageDescription": "Echoelmusic TV uses your microphone for voice-to-sound synthesis.",
                "NSBluetoothAlwaysUsageDescription": "Echoelmusic TV connects to MIDI controllers and audio devices."
            ]),
            sources: [
                "Sources/Echoelmusic/tvOS/**/*.swift"
            ],
            resources: [
                "Sources/Echoelmusic/tvOS/Assets.xcassets"
            ],
            entitlements: .file(path: "EchoelmusicTV.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app",
                    "TARGETED_DEVICE_FAMILY": "3",
                    "TVOS_DEPLOYMENT_TARGET": "17.0",
                    "ENABLE_BITCODE": "NO"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - visionOS App
        Target(
            name: "EchoelmusicVision",
            platform: .visionOS,
            product: .app,
            bundleId: "com.echoelmusic.app",
            deploymentTarget: .visionOS(targetVersion: "1.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic",
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": true,
                    "UISceneConfigurations": [:]
                ],
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)",
                "UIBackgroundModes": ["audio"],
                "NSCameraUsageDescription": "Echoelmusic Vision uses camera for eye tracking and hand gestures.",
                "NSFaceIDUsageDescription": "Echoelmusic Vision uses facial tracking for expression-based control."
            ]),
            sources: [
                "Sources/Echoelmusic/VisionOS/**/*.swift"
            ],
            resources: [
                "Sources/Echoelmusic/VisionOS/Assets.xcassets"
            ],
            entitlements: .file(path: "EchoelmusicVision.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app",
                    "TARGETED_DEVICE_FAMILY": "7",
                    "XROS_DEPLOYMENT_TARGET": "1.0",
                    "ENABLE_PREVIEWS": "YES"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - AUv3 Audio Unit Plugin
        Target(
            name: "EchoelmusicAUv3",
            platform: .iOS,
            product: .appExtension,
            bundleId: "com.echoelmusic.app.auv3",
            deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone, .ipad]),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic AUv3",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.AudioUnit-UI",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).AudioUnitViewController",
                    "AudioComponents": [
                        [
                            "name": "Echoelmusic Technologies: Echoelmusic",
                            "description": "Bio-Reactive Audio Processor",
                            "factoryFunction": "EchoelmusicAudioUnitFactory",
                            "manufacturer": "Echo",
                            "type": "aufx",
                            "subtype": "echl",
                            "version": 10000,
                            "sandboxSafe": true,
                            "tags": ["Effects", "Bio-Reactive"]
                        ]
                    ]
                ],
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)"
            ]),
            sources: [
                "Sources/EchoelmusicAUv3/**/*.swift"
            ],
            entitlements: .file(path: "EchoelmusicAUv3.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app.auv3",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "SKIP_INSTALL": "YES",
                    "SUPPORTS_MACCATALYST": "YES"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - EchoelVoice AUv3 Plugin (Bio-Reactive Vocal Processor)
        Target(
            name: "EchoelVoice",
            platform: .iOS,
            product: .appExtension,
            bundleId: "com.echoelmusic.app.voice",
            deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone, .ipad]),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "EchoelVoice",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.AudioUnit-UI",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).EchoelVoiceViewController",
                    "AudioComponents": [
                        [
                            "name": "Echoelmusic Technologies: EchoelVoice",
                            "description": "Bio-Reactive Vocal Processor",
                            "factoryFunction": "EchoelVoiceAudioUnitFactory",
                            "manufacturer": "Echo",
                            "type": "aufx",
                            "subtype": "evoc",
                            "version": 10000,
                            "sandboxSafe": true,
                            "tags": ["Effects", "Vocal", "Pitch Correction", "Bio-Reactive"]
                        ]
                    ]
                ],
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleVersion": "1"
            ]),
            sources: [
                "Sources/EchoelVoice/**/*.swift"
            ],
            entitlements: .file(path: "EchoelVoice.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app.voice",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "SKIP_INSTALL": "YES",
                    "SUPPORTS_MACCATALYST": "YES"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - macOS App
        Target(
            name: "EchoelmusicMac",
            platform: .macOS,
            product: .app,
            bundleId: "com.echoelmusic.app",
            deploymentTarget: .macOS(targetVersion: "14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Echoelmusic",
                "LSApplicationCategoryType": "public.app-category.music",
                "CFBundleShortVersionString": "7.0.0",
                "CFBundleVersion": "$(BUILD_NUMBER:=1)",
                "NSCameraUsageDescription": "Echoelmusic uses your camera for facial expression tracking.",
                "NSMicrophoneUsageDescription": "Echoelmusic uses your microphone for voice-to-sound synthesis.",
                "NSBluetoothAlwaysUsageDescription": "Echoelmusic connects to MIDI controllers and audio devices.",
                "NSLocalNetworkUsageDescription": "Echoelmusic uses local network for OSC and lighting control."
            ]),
            sources: [
                "Sources/Echoelmusic/**/*.swift",
                "Sources/Echoelmusic/**/*.metal"
            ],
            resources: [
                "Resources/**",
                "Sources/Echoelmusic/Resources/**"
            ],
            entitlements: .file(path: "EchoelmusicMac.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.app",
                    "MACOSX_DEPLOYMENT_TARGET": "14.0",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "ENABLE_PREVIEWS": "YES"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - Unit Tests
        Target(
            name: "EchoelmusicTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "com.echoelmusic.tests",
            deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone, .ipad]),
            infoPlist: .default,
            sources: [
                "Tests/EchoelmusicTests/**/*.swift"
            ],
            dependencies: [
                .target(name: "Echoelmusic")
            ],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.tests",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "ENABLE_TESTABILITY": "YES",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Echoelmusic.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Echoelmusic",
                    "BUNDLE_LOADER": "$(TEST_HOST)"
                ],
                defaultSettings: .recommended
            )
        ),

        // MARK: - UI Tests
        Target(
            name: "EchoelmusicUITests",
            platform: .iOS,
            product: .uiTests,
            bundleId: "com.echoelmusic.uitests",
            deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone, .ipad]),
            infoPlist: .default,
            sources: [
                "Tests/EchoelmusicUITests/**/*.swift"
            ],
            dependencies: [
                .target(name: "Echoelmusic")
            ],
            settings: .settings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.echoelmusic.uitests",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                    "TEST_TARGET_NAME": "Echoelmusic"
                ],
                defaultSettings: .recommended
            )
        )
    ],
    schemes: [
        // MARK: - iOS App Scheme
        Scheme(
            name: "Echoelmusic",
            shared: true,
            buildAction: .buildAction(targets: ["Echoelmusic"]),
            testAction: .targets(
                ["EchoelmusicTests", "EchoelmusicUITests"],
                configuration: "Debug",
                options: .options(
                    coverage: true,
                    codeCoverageTargets: ["Echoelmusic"]
                )
            ),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Echoelmusic"
            ),
            archiveAction: .archiveAction(
                configuration: "Release"
            ),
            profileAction: .profileAction(
                configuration: "Release",
                executable: "Echoelmusic"
            ),
            analyzeAction: .analyzeAction(
                configuration: "Debug"
            )
        ),

        // MARK: - macOS App Scheme
        Scheme(
            name: "EchoelmusicMac",
            shared: true,
            buildAction: .buildAction(targets: ["EchoelmusicMac"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "EchoelmusicMac"
            ),
            archiveAction: .archiveAction(
                configuration: "Release"
            )
        ),

        // MARK: - watchOS App Scheme
        Scheme(
            name: "EchoelmusicWatch",
            shared: true,
            buildAction: .buildAction(targets: ["EchoelmusicWatch"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "EchoelmusicWatch"
            ),
            archiveAction: .archiveAction(
                configuration: "Release"
            )
        ),

        // MARK: - tvOS App Scheme
        Scheme(
            name: "EchoelmusicTV",
            shared: true,
            buildAction: .buildAction(targets: ["EchoelmusicTV"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "EchoelmusicTV"
            ),
            archiveAction: .archiveAction(
                configuration: "Release"
            )
        ),

        // MARK: - visionOS App Scheme
        Scheme(
            name: "EchoelmusicVision",
            shared: true,
            buildAction: .buildAction(targets: ["EchoelmusicVision"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "EchoelmusicVision"
            ),
            archiveAction: .archiveAction(
                configuration: "Release"
            )
        ),

        // MARK: - All Platforms Scheme
        Scheme(
            name: "Echoelmusic-AllPlatforms",
            shared: true,
            buildAction: .buildAction(
                targets: [
                    "Echoelmusic",
                    "EchoelmusicMac",
                    "EchoelmusicWatch",
                    "EchoelmusicTV",
                    "EchoelmusicVision",
                    "EchoelmusicWidgets",
                    "EchoelmusicAUv3"
                ]
            ),
            testAction: .targets(
                ["EchoelmusicTests"],
                configuration: "Debug",
                options: .options(coverage: true)
            )
        )
    ],
    fileHeaderTemplate: .string(
        """
        //
        //  __FILENAME__
        //  Echoelmusic
        //
        //  Created on __DATE__.
        //  Copyright © __YEAR__ Echoelmusic Technologies. All rights reserved.
        //
        //  Bio-Reactive Audio-Visual Platform
        //  Phase 10000.1 ULTRA MODE - Production Ready
        //
        """
    ),
    additionalFiles: [
        "README.md",
        "CLAUDE.md",
        "XCODE_HANDOFF.md",
        "ARCHITECTURE_SCIENTIFIC.md",
        "RESEARCH_EVIDENCE.md",
        "Package.swift",
        "CMakeLists.txt",
        ".swiftlint.yml",
        ".swiftformat"
    ],
    resourceSynthesizers: [
        .assets(),
        .strings(),
        .plists(),
        .fonts(),
        .custom(
            name: "MetalShaders",
            parser: .json,
            extensions: ["metal"]
        )
    ]
)
