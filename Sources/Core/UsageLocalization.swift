import Foundation

enum UsageLocalization {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func text(_ key: String, bundle: Bundle = bundle) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ count: Int, bundle: Bundle = bundle) -> String {
        String(format: text(key, bundle: bundle), locale: Locale.current, Int64(count))
    }
}
