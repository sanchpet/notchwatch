//
//  ClaudeModelPin.swift
//  Notchwatch
//
//  Opens the settings files `NotchwatchKit.ClaudeModelPin` names.
//

import Foundation
import NotchwatchKit

extension ClaudeModelPin {
    /// Whether the effective model pin for `projectDirectory` opts in to the 1M
    /// context window.
    ///
    /// Which files are consulted, and in what order, is decided in the kit; this
    /// only reads them.
    static func declaresLongWindow(projectDirectory: String?, configRoot: URL?) -> Bool {
        declaresLongWindow(
            projectDirectory: projectDirectory,
            configRoot: configRoot,
            readModel: model(in:)
        )
    }

    private static func model(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String,
              !model.isEmpty else { return nil }
        return model
    }
}
