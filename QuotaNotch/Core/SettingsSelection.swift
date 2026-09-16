// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Shared insertion semantics for click and drop. Filling a layout never overwrites
/// another control without an explicit destination, and each control appears once.
enum SettingsSelection {
    static func inserting<Value: Equatable>(_ value: Value, into slots: [Value], empty: Value, destination: Int? = nil) -> [Value]? {
        let target: Int
        if let destination {
            guard slots.indices.contains(destination) else { return nil }
            target = destination
        } else if slots.contains(value) {
            return slots
        } else if let available = slots.firstIndex(of: empty) {
            target = available
        } else {
            return nil
        }
        var result = slots.map { $0 == value ? empty : $0 }
        result[target] = value
        return result
    }
}

extension QuotaPins {
    /// Saved candidates remain editable while a service is paused or data is missing.
    func editableCandidates(available: [QuotaPin]) -> [QuotaPin] {
        (available + candidates).reduce(into: []) { result, pin in
            if !result.contains(pin) { result.append(pin) }
        }
    }
}
