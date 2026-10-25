import XCTest
@testable import CodexMeterCore

final class PopoverContentConfigurationTests: XCTestCase {
    func testDefaultsShowEverySectionAndQuotaWindow() {
        let configuration = PopoverContentConfiguration.defaultValue
        let included = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 20)
        let auto = makeWindow(
            id: "cursor-auto",
            name: "Auto",
            duration: nil,
            used: 30
        )
        let api = makeWindow(
            id: "cursor-api",
            name: "API",
            duration: nil,
            used: 0
        )

        XCTAssertTrue(configuration.isSectionVisible(.quotaWindows))
        XCTAssertTrue(configuration.isSectionVisible(.resetCredits))
        XCTAssertTrue(configuration.isSectionVisible(.quotaHistory))
        XCTAssertTrue(configuration.isSectionVisible(.tokenActivity))
        XCTAssertEqual(
            configuration.sectionOrder,
            [.quotaWindows, .resetCredits, .quotaHistory, .tokenActivity]
        )
        XCTAssertTrue(configuration.isQuotaWindowVisible(included))
        XCTAssertTrue(configuration.isQuotaWindowVisible(auto))
        XCTAssertTrue(configuration.isQuotaWindowVisible(api))
        XCTAssertNil(configuration.menuBarQuotaWindowID)
    }

    func testQuotaWindowsCanBeHiddenIndependentlyByStableIdentity() {
        var configuration = PopoverContentConfiguration.defaultValue
        let included = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 20)
        let auto = makeWindow(id: "cursor-auto", name: "Auto", duration: nil, used: 30)

        configuration.setQuotaWindow(included, visible: false)

        XCTAssertFalse(configuration.isQuotaWindowVisible(included))
        XCTAssertTrue(configuration.isQuotaWindowVisible(auto))
        XCTAssertEqual(configuration.visibleQuotaWindows(from: [included, auto]), [auto])
    }

    func testSelectedMenuBarWindowUsesPersistedStableIdentity() {
        var configuration = PopoverContentConfiguration.defaultValue
        let included = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 80)
        let auto = makeWindow(id: "cursor-auto", name: "Auto", duration: nil, used: 20)

        configuration.menuBarQuotaWindowID = auto.historyID

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [included, auto]), auto)
    }

    func testMissingMenuBarSelectionFallsBackToLowestRemainingQuota() {
        var configuration = PopoverContentConfiguration.defaultValue
        configuration.menuBarQuotaWindowID = "duration:999:missing"
        let included = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 80)
        let auto = makeWindow(id: "cursor-auto", name: "Auto", duration: nil, used: 20)

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [auto, included]), included)
    }

    func testAutomaticSelectionUsesAutoWhenItHasLessRemaining() {
        let configuration = PopoverContentConfiguration.defaultValue
        let included = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 20)
        let auto = makeWindow(
            id: "cursor-auto",
            name: "Auto",
            duration: nil,
            used: 90
        )

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [included, auto]), auto)
    }

    func testAutomaticSelectionUsesLowestRemainingAcrossCursorPools() {
        let configuration = PopoverContentConfiguration.defaultValue
        let api = makeWindow(
            id: "cursor-api",
            name: "API",
            duration: nil,
            used: 90
        )
        let auto = makeWindow(
            id: "cursor-auto",
            name: "Auto",
            duration: nil,
            used: 76
        )

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [api, auto]), api)
    }

    func testHistoryDefaultPreservesFirstCursorPoolWhenDurationsAreUnknown() {
        let included = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 20)
        let auto = makeWindow(id: "cursor-auto", name: "Auto", duration: nil, used: 90)
        let api = makeWindow(id: "cursor-api", name: "API", duration: nil, used: 30)
        let windows = [included, auto, api]
        let historyWindows = windows.map {
            QuotaHistoryWindow(id: $0.historyID, name: $0.name,
                               windowDurationMins: $0.windowDurationMins, resetsAt: $0.resetsAt)
        }

        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: windows), included)
        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: historyWindows), historyWindows[0])
        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: [api, auto, included]), api)
        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: Array(historyWindows.reversed())), historyWindows[2])
    }

    func testHistoryDefaultPrefersLongestKnownDuration() {
        let unknown = makeWindow(id: "cursor-included", name: "Included", duration: nil, used: 90)
        let shorter = makeWindow(id: "shorter", name: "Shorter", duration: 60, used: 20)
        let longer = makeWindow(id: "longer", name: "Longer", duration: 120, used: 30)
        let windows = [unknown, shorter, longer]
        let historyWindows = windows.map {
            QuotaHistoryWindow(id: $0.historyID, name: $0.name,
                               windowDurationMins: $0.windowDurationMins, resetsAt: $0.resetsAt)
        }

        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: windows), longer)
        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: historyWindows), historyWindows[2])
    }

    func testMovingSectionChangesOnlyItsStoredOrder() {
        var configuration = PopoverContentConfiguration.defaultValue

        configuration.moveSection(.tokenActivity, by: -1)

        XCTAssertEqual(
            configuration.sectionOrder,
            [.quotaWindows, .resetCredits, .tokenActivity, .quotaHistory]
        )
        XCTAssertTrue(configuration.isSectionVisible(.resetCredits))
        XCTAssertTrue(configuration.isSectionVisible(.tokenActivity))
    }

    func testDecodingOlderEmptyPreferencesUsesCurrentDefaults() throws {
        let configuration = try JSONDecoder().decode(
            PopoverContentConfiguration.self,
            from: Data("{}".utf8)
        )

        XCTAssertEqual(configuration, .defaultValue)
    }

    private func makeWindow(
        id: String,
        name: String,
        duration: Int?,
        used: Int
    ) -> CodexUsageWindow {
        CodexUsageWindow(
            id: id,
            name: name,
            usedPercent: used,
            windowDurationMins: duration,
            resetsAt: nil
        )
    }
}
