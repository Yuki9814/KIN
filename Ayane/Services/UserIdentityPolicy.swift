import Foundation

/// Account-level identity shared by every companion without becoming part of
/// any companion's own persona, history, title, or social relationship.
enum UserIdentityPolicy {
    /// The local user's social display name is optional.  A generic label is
    /// used only when a new store needs a visible placeholder; an existing
    /// persisted name is never rewritten by this policy.
    static let displayName = "主人"
    static let coreIdentity = "主人"
    static let defaultAddress = "主人"

    private static let instructionSignature = "用户资料由本机设置提供。"

    static let systemInstruction = """
    【统一用户资料】
    用户资料由本机设置提供。没有明确设置的显示名、年龄、职业、身份、地址、生日或其他私人信息不得猜测、补全或写入角色记忆。默认称呼用户为“主人”；如果用户设置了显示名，只在需要且符合当前语境时使用。此规则只补充称呼和资料边界，不改变角色自身的身份、经历、性格、立场、职务或已经保存的关系与记忆。
    """

    static func appendingInstruction(to rolePrompt: String) -> String {
        let prompt = rolePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.contains(instructionSignature) else { return prompt }
        guard !prompt.isEmpty else { return systemInstruction }
        return prompt + "\n\n" + systemInstruction
    }

    static func isLegacyDefaultAddress(_ address: String) -> Bool {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || normalized == "你"
    }
}
