//
//  InputSource.swift
//
//  Sauce
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Foundation
import Carbon

public final class InputSource {

    // MARK: - Properties
    public let id: String
    public let modeID: String?
    public let isASCIICapable: Bool
    public let isEnableCapable: Bool
    public let isSelectCapable: Bool
    public let isEnabled: Bool
    public let isSelected: Bool
    public let localizedName: String?
    public let source: TISInputSource

    // MARK: - Initialize
    init(source: TISInputSource) {
        self.id = source.value(forProperty: kTISPropertyInputSourceID, type: String.self)!
        self.modeID = source.value(forProperty: kTISPropertyInputModeID, type: String.self)
        self.isASCIICapable = source.value(forProperty: kTISPropertyInputSourceIsASCIICapable, type: Bool.self) ?? false
        self.isEnableCapable = source.value(forProperty: kTISPropertyInputSourceIsEnableCapable, type: Bool.self) ?? false
        self.isSelectCapable = source.value(forProperty: kTISPropertyInputSourceIsSelectCapable, type: Bool.self) ?? false
        self.isEnabled = source.value(forProperty: kTISPropertyInputSourceIsEnabled, type: Bool.self) ?? false
        self.isSelected = source.value(forProperty: kTISPropertyInputSourceIsSelected, type: Bool.self) ?? false
        self.localizedName = source.value(forProperty: kTISPropertyLocalizedName, type: String.self)
        self.source = source
    }

}

// MARK: - Hashable
extension InputSource: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(modeID)
    }
}

// MARK: - Equatable
extension InputSource: Equatable {
    public static func == (lhs: InputSource, rhs: InputSource) -> Bool {
        return lhs.id == rhs.id &&
            lhs.modeID == rhs.modeID
    }
}
