import XCTest
@testable import QuotaNotchCore

final class NotchEventPresentationTests: XCTestCase {
    private let pin = QuotaPin(providerID: "claude", windowID: "five_hour")

    func testSystemControlsPreserveEveryPrimaryCombinationAndClickTarget() {
        for event in SneakContentType.allCases where event.isSystemControl {
            for quota in [false, true] {
                for music in [false, true] {
                    let pins = QuotaPins(selected: quota ? pin : nil)
                    let baseline = pins.presentation(enabled: true, hidden: false, replacingPrimary: false, musicPlaying: music)
                    let state = NotchEventPresentation(expanded: nil, notification: event)
                    let during = pins.presentation(enabled: true, hidden: false,
                        replacingPrimary: state.replacesPrimary, musicPlaying: music)
                    XCTAssertEqual(during, baseline)
                    XCTAssertEqual(state.accessory, event)
                    for pointer in [-1.0, 1.0] {
                        XCTAssertEqual(during.openingPage(pointerX: pointer, midpointX: 0, isOpen: false),
                                       baseline.openingPage(pointerX: pointer, midpointX: 0, isOpen: false))
                    }
                }
            }
        }
    }

    func testMediaInformationAlsoSupplementsPrimary() {
        let state = NotchEventPresentation(expanded: .music, notification: .music)
        XCTAssertFalse(state.replacesPrimary)
        XCTAssertEqual(state.accessory, .music)
    }

    func testPlaybackCanChangeWhileControlRemainsVisible() {
        let pins = QuotaPins(selected: pin)
        let state = NotchEventPresentation(expanded: nil, notification: .volume)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: state.replacesPrimary, musicPlaying: true), .combined)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: state.replacesPrimary, musicPlaying: false), .quota)
        XCTAssertEqual(state.accessory, .volume)
    }

    func testControlRemovalDoesNotRestoreAnOutdatedPrimaryMode() {
        let pins = QuotaPins(selected: pin)
        for event: SneakContentType? in [.volume, .brightness, nil] {
            let state = NotchEventPresentation(expanded: nil, notification: event)
            XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: state.replacesPrimary, musicPlaying: false), .quota)
        }
    }

    func testReplacementAndGreetingKeepTheirExplicitPriority() {
        for event in [SneakContentType.battery, .download] {
            let state = NotchEventPresentation(expanded: event, notification: .volume)
            XCTAssertTrue(state.replacesPrimary)
            XCTAssertEqual(state.accessory, .volume)
        }
        let greeting = NotchEventPresentation(expanded: nil, notification: .volume, greeting: true)
        XCTAssertTrue(greeting.replacesPrimary)
        XCTAssertNil(greeting.accessory)
    }

    func testHiddenPrimaryStaysHiddenEvenDuringSystemControls() {
        let pins = QuotaPins(selected: pin)
        let state = NotchEventPresentation(expanded: nil, notification: .volume)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: true,
            replacingPrimary: state.replacesPrimary, musicPlaying: true), .none)
        XCTAssertEqual(state.accessory, .volume)
    }
}
