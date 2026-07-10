import XCTest
@testable import Echoelmusic

final class ProGateTests: XCTestCase {

    // MARK: - Core is never gated

    func testAlwaysFreeFeatures_WithoutPurchase_Unlocked() {
        for feature in ProGate.alwaysFree {
            XCTAssertTrue(
                ProGate.isUnlocked(feature, proPurchased: false),
                "\(feature) must be free without a purchase — core is never gated"
            )
        }
    }

    func testAlwaysFreeFeatures_WithPurchase_Unlocked() {
        for feature in ProGate.alwaysFree {
            XCTAssertTrue(ProGate.isUnlocked(feature, proPurchased: true))
        }
    }

    func testAlwaysFree_ContainsBioSoundSafetyAccessibility() {
        XCTAssertTrue(ProGate.alwaysFree.contains(.bioMeasurement))
        XCTAssertTrue(ProGate.alwaysFree.contains(.soundGeneration))
        XCTAssertTrue(ProGate.alwaysFree.contains(.safety))
        XCTAssertTrue(ProGate.alwaysFree.contains(.accessibility))
    }

    // MARK: - Pro gates extensions only

    func testProFeatures_WithoutPurchase_Locked() {
        for feature in ProGate.proFeatures {
            XCTAssertFalse(
                ProGate.isUnlocked(feature, proPurchased: false),
                "\(feature) is a Pro extension and must be locked without purchase"
            )
        }
    }

    func testProFeatures_WithPurchase_Unlocked() {
        for feature in ProGate.proFeatures {
            XCTAssertTrue(ProGate.isUnlocked(feature, proPurchased: true))
        }
    }

    // MARK: - Policy integrity

    func testProAndFreeSets_AreDisjoint() {
        XCTAssertTrue(
            ProGate.proFeatures.isDisjoint(with: ProGate.alwaysFree),
            "A feature cannot be both Pro-gated and always free"
        )
    }

    func testEveryFeature_IsClassified() {
        for feature in ProFeature.allCases {
            XCTAssertTrue(
                ProGate.proFeatures.contains(feature) || ProGate.alwaysFree.contains(feature),
                "\(feature) is unclassified — every feature needs an explicit free/Pro decision"
            )
        }
    }

    // MARK: - Product identity

    func testProductID_IsTheOneTimeUnlock() {
        XCTAssertEqual(ProGate.productID, "com.echoelmusic.app.pro")
        XCTAssertFalse(ProGate.productID.contains("monthly"))
        XCTAssertFalse(ProGate.productID.contains("yearly"))
    }
}
