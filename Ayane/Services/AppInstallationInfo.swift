import Foundation

/// Read-only metadata about the currently running installation.
///
/// The provisioning profile is only a local diagnostic source. Its CMS
/// signature is deliberately not verified here, and only the embedded XML
/// plist payload is inspected for the expiration date.
struct AppInstallationInfo: Equatable, Sendable {
    let marketingVersion: String?
    let bundleVersion: String?
    let expirationDate: Date?

    static let maximumProvisioningProfileSize = 1_048_576

    var marketingVersionText: String {
        marketingVersion ?? "未设置"
    }

    var bundleVersionText: String {
        bundleVersion ?? "未设置"
    }

    /// Loads non-secret version metadata from the app bundle. On iOS, the
    /// expiration date is shown only when the embedded profile can be read and
    /// its bounded XML plist contains an actual Date value for ExpirationDate.
    static func current(bundle: Bundle = .main) -> Self {
        let marketingVersion = normalizedString(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        let bundleVersion = normalizedString(
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )

        #if os(iOS)
        let expirationDate: Date?
        if let profileURL = bundle.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ), let profileData = readProvisioningProfile(at: profileURL) {
            expirationDate = Self.expirationDate(inProvisioningProfile: profileData)
        } else {
            expirationDate = nil
        }
        #else
        let expirationDate: Date? = nil
        #endif

        return Self(
            marketingVersion: marketingVersion,
            bundleVersion: bundleVersion,
            expirationDate: expirationDate
        )
    }

    /// Extracts ExpirationDate from an embedded.mobileprovision payload.
    ///
    /// CMS data is binary before and after the XML plist. Search for bounded
    /// byte ranges and parse only that slice; never decode the whole CMS blob
    /// as UTF-8. This method performs no signature validation.
    static func expirationDate(inProvisioningProfile data: Data) -> Date? {
        guard data.count <= maximumProvisioningProfileSize else { return nil }

        let xmlDeclaration = Data("<?xml".utf8)
        let plistStart = Data("<plist".utf8)
        let plistEnd = Data("</plist>".utf8)
        guard let start = data.range(of: xmlDeclaration)
                ?? data.range(of: plistStart) else {
            return nil
        }

        guard start.upperBound < data.endIndex,
              let end = data.range(
                of: plistEnd,
                options: [],
                in: start.upperBound..<data.endIndex
              ) else {
            return nil
        }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: &format
        ) as? [String: Any],
              format == .xml else {
            return nil
        }
        return plist["ExpirationDate"] as? Date
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    #if os(iOS)
    private static func readProvisioningProfile(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        do {
            let data = try handle.read(upToCount: maximumProvisioningProfileSize + 1) ?? Data()
            guard data.count <= maximumProvisioningProfileSize else { return nil }
            return data
        } catch {
            return nil
        }
    }
    #endif
}
