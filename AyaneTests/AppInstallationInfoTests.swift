import Foundation
import XCTest
@testable import Ayane

final class AppInstallationInfoTests: XCTestCase {
    func testExpirationDateExtractsXMLPlistFromBinaryEnvelope() throws {
        let expiration = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2027-01-15T08:30:00Z")
        )
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Name": "KIN",
                "ExpirationDate": expiration
            ],
            format: .xml,
            options: 0
        )

        var profileData = Data([0x30, 0x82, 0x01, 0x00, 0x00])
        profileData.append(plistData)
        profileData.append(Data([0x00, 0xFF, 0xD0, 0x0A]))

        XCTAssertEqual(
            AppInstallationInfo.expirationDate(inProvisioningProfile: profileData),
            expiration
        )
    }

    func testExpirationDateRejectsMissingOrCorruptPlist() {
        XCTAssertNil(
            AppInstallationInfo.expirationDate(
                inProvisioningProfile: Data([0x30, 0x82, 0x01, 0x00])
            )
        )

        let corrupt = Data("binary<?xml version=\"1.0\"?><plist><dict>".utf8)
        XCTAssertNil(
            AppInstallationInfo.expirationDate(inProvisioningProfile: corrupt)
        )
    }

    func testExpirationDateIsNilWhenPlistHasNoExpirationDate() throws {
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["Name": "KIN"],
            format: .xml,
            options: 0
        )

        XCTAssertNil(
            AppInstallationInfo.expirationDate(inProvisioningProfile: plistData)
        )
    }
}
