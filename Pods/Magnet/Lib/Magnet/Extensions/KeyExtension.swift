// 
//  KeyExtension.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Copyright © 2015-2020 Clipy Project.
//

import Foundation
import Sauce

public extension Key {
    var isFunctionKey: Bool {
        switch self {
        case .f1,
             .f2,
             .f3,
             .f4,
             .f5,
             .f6,
             .f7,
             .f8,
             .f9,
             .f10,
             .f11,
             .f12,
             .f13,
             .f14,
             .f15,
             .f16,
             .f17,
             .f18,
             .f19,
             .f20:
            return true
        default:
            return false
        }
    }
    var isAlphabet: Bool {
        switch self {
        case .a,
             .b,
             .c,
             .d,
             .e,
             .f,
             .g,
             .h,
             .i,
             .j,
             .k,
             .l,
             .m,
             .n,
             .o,
             .p,
             .q,
             .r,
             .s,
             .t,
             .u,
             .v,
             .w,
             .x,
             .y,
             .z:
            return true
        default:
            return false
        }
    }
}
