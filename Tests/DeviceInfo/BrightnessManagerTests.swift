import Testing
@testable import KontextKit

@MainActor
struct BrightnessManagerTests {

    /// `set` always returns the value it actually applied, post-clamp.
    /// Restored at end so other tests aren't affected.
    @Test func setReturnsClampedValue() {
        let original = BrightnessManager.get()
        defer { _ = BrightnessManager.set(original) }

        #expect(abs(BrightnessManager.set(50) - 50) < 0.01)
        #expect(abs(BrightnessManager.set(0) - 0) < 0.01)
        #expect(abs(BrightnessManager.set(100) - 100) < 0.01)
    }

    @Test func setClampsValuesBelowZero() {
        let original = BrightnessManager.get()
        defer { _ = BrightnessManager.set(original) }

        #expect(abs(BrightnessManager.set(-50) - 0) < 0.01)
        #expect(abs(BrightnessManager.set(-9999) - 0) < 0.01)
    }

    @Test func setClampsValuesAboveHundred() {
        let original = BrightnessManager.get()
        defer { _ = BrightnessManager.set(original) }

        #expect(abs(BrightnessManager.set(150) - 100) < 0.01)
        #expect(abs(BrightnessManager.set(9999) - 100) < 0.01)
    }

    @Test func getReturnsValueInValidRange() {
        let value = BrightnessManager.get()
        #expect(value >= 0)
        #expect(value <= 100)
    }

    // MARK: - Bridge variants

    @Test func getAsNumberMatchesGet() {
        let original = BrightnessManager.get()
        defer { _ = BrightnessManager.set(original) }

        _ = BrightnessManager.set(60)
        let bridge = BrightnessManager.getAsNumber().doubleValue
        #expect(abs(bridge - BrightnessManager.get()) < 0.01)
    }

    @Test func setAsNumberAppliesClampedValue() {
        let original = BrightnessManager.get()
        defer { _ = BrightnessManager.set(original) }

        let result = BrightnessManager.setAsNumber(150).doubleValue
        #expect(abs(result - 100) < 0.01)
    }
}
