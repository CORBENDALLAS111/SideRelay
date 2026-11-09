import Foundation

/// App language follows iOS's per-app language preference.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let value = Bundle.main.localizedString(forKey:key,value:key,table:nil)
    return arguments.isEmpty ? value : String(format:value,locale:.current,arguments:arguments)
}

enum RelayText {
    /// The core sends only controlled user-facing strings; preserve diagnostic codes.
    static func core(_ message: String) -> String {
        let translated = L(message)
        if translated != message { return translated }

        guard let marker = message.range(of:" Код: ",options:.backwards) else { return message }
        let before = String(message[..<marker.lowerBound])
        let after = message[marker.upperBound...]
        guard let dot = after.firstIndex(of:".") else { return message }
        let code = String(after[..<dot])
        guard !code.isEmpty, code.utf8.count <= 64,
              code.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 })
        else { return message }

        let tail = String(after[dot...])
        if tail != "." {
            return L(before + " Код: %@" + tail,code)
        }

        guard let separator = before.range(of:". ") else { return message }
        let phase = String(before[..<separator.lowerBound])
        let advice = String(before[separator.upperBound...])
        return L("%@. %@ Код: %@.",L(phase),L(advice),code)
    }
}
