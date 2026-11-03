import XCTest
@testable import CodexUsageCore

final class LocalizationTests: XCTestCase {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(UsageLocalization.bundle.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testBothLanguagesHaveCompleteMatchingTranslations() throws {
        func strings(_ language: String) throws -> [String: String] {
            let url = try XCTUnwrap(try bundle(language).url(forResource: "Localizable", withExtension: "strings"))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let english = try strings("en"), chinese = try strings("zh-Hans")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for (key, value) in english {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertNil(value.range(of: "\\p{Han}", options: .regularExpression), key)
            XCTAssertEqual(UsageLocalization.text(key, bundle: try bundle("en")), value)
        }
        XCTAssertEqual(UsageLocalization.text("刷新额度", bundle: try bundle("en")), "Refresh usage")
        XCTAssertEqual(UsageLocalization.text("刷新额度", bundle: try bundle("zh-Hans")), "刷新额度")
    }

    func testWindowTitlesLocalizeAfterCacheRoundTrip() throws {
        let durations: [Int?] = [nil, 10080, 2880, 300, 15]
        let english = ["Usage window", "Weekly limit", "2-day limit", "5-hour limit", "15-minute limit"]
        let chinese = ["额度周期", "每周额度", "2 天额度", "5 小时额度", "15 分钟额度"]
        for (index, duration) in durations.enumerated() {
            let window = UsageWindow(usedPercent: 25, windowDurationMins: duration, resetsAt: nil)
            let data = try JSONEncoder().encode(window)
            let restored = try JSONDecoder().decode(UsageWindow.self, from: data)
            XCTAssertEqual(restored.localizedTitle(bundle: try bundle("en")), english[index])
            XCTAssertEqual(restored.localizedTitle(bundle: try bundle("zh-Hans")), chinese[index])
        }
    }

    func testPersistedFailureUsesCurrentLanguage() throws {
        for failure in [UsageFailure.cliMissing, .authentication, .rateLimited, .timeout, .unavailable, .incompatible, .storage] {
            let restored = try JSONDecoder().decode(UsageFailure.self, from: JSONEncoder().encode(failure))
            let english = restored.localizedMessage(bundle: try bundle("en"))
            let chinese = restored.localizedMessage(bundle: try bundle("zh-Hans"))
            XCTAssertNotEqual(english, chinese)
            XCTAssertNil(english.range(of: "\\p{Han}", options: .regularExpression))
            XCTAssertNotNil(chinese.range(of: "\\p{Han}", options: .regularExpression))
        }
    }
}
