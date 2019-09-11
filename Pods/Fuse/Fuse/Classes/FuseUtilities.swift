//
//  FuseUtilities.swift
//  Pods
//
//  Created by Kirollos Risk on 5/2/17.
//
//

import Foundation


class FuseUtilities {
    /// Computes the score for a match with `e` errors and `x` location.
    ///
    /// - Parameter pattern: Pattern being sought.
    /// - Parameter e: Number of errors in match.
    /// - Parameter x: Location of match.
    /// - Parameter loc: Expected location of match.
    /// - Parameter scoreTextLength: Coerced version of text's length.
    /// - Returns: Overall score for match (0.0 = good, 1.0 = bad).
    static func calculateScore(_ pattern: String, e: Int, x: Int, loc: Int, distance: Int) -> Double {
        let len = pattern.count
        let accuracy = Double(e) / Double(len)
        let proximity = abs(x - loc)
        if (distance == 0) {
            return Double(proximity != 0 ? 1 : accuracy)
        }
        return Double(accuracy) + (Double(proximity) / Double(distance))
    }
    
    /// Initializes the alphabet for the Bitap algorithm
    ///
    /// - Parameter pattern: The text to encode.
    /// - Returns: Hash of character locations.
    static func calculatePatternAlphabet(_ pattern: String) -> [Character: Int] {
        let len = pattern.count
        var mask = [Character: Int]()
        for char in pattern {
            mask[char] = 0
        }
        for i in 0...len-1 {
            let c = pattern[pattern.index(pattern.startIndex, offsetBy: i)]
            mask[c] =  mask[c]! | (1 << (len - i - 1))
        }
        return mask
    }
    
    /// Returns an array of `CountableClosedRange<Int>`, where each range represents a consecutive list of `1`s.
    ///
    ///     let arr = [0, 1, 1, 0, 1, 1, 1 ]
    ///     let ranges = findRanges(arr)
    ///     // [{startIndex 1, endIndex 2}, {startIndex 4, endIndex 6}
    ///
    /// - Parameter mask: A string representing the value to search for.
    ///
    /// - Returns: `CountableClosedRange<Int>` array.
    static func findRanges(_ mask: [Int]) -> [CountableClosedRange<Int>] {
        var ranges = [CountableClosedRange<Int>]()
        var start: Int = -1
        var end: Int = -1
        for (n, bit) in mask.enumerated() {
            if bit == 1 && start == -1 {
                start = n
            } else if bit == 0 && start != -1 {
                end = n - 1
                ranges.append(CountableClosedRange<Int>(start...end))
                start = -1
            }
        }
        if mask.last == 1 {
            ranges.append(CountableClosedRange<Int>(start...mask.count - 1))
        }
        return ranges
    }
}
