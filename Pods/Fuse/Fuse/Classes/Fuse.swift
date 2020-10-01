//
//  Fuse.swift
//  Pods
//
//  Created by Kirollos Risk on 5/2/17.
//
//

import Foundation

public struct FuseProperty {
    let name: String
    let weight: Double
    
    public init (name: String) {
        self.init(name: name, weight: 1)
    }
    
    public init (name: String, weight: Double) {
        self.name = name
        self.weight = weight
    }
}

public protocol Fuseable {
    var properties: [FuseProperty] { get }
}

public class Fuse {
    private var location: Int
    private var distance: Int
    private var threshold: Double
    private var maxPatternLength: Int
    private var isCaseSensitive: Bool
    private var tokenize: Bool
    
    public typealias Pattern = (text: String, len: Int, mask: Int, alphabet: [Character: Int])
    
    public typealias SearchResult = (index: Int, score: Double, ranges: [CountableClosedRange<Int>])
    
    public typealias FusableSearchResult = (
        index: Int,
        score: Double,
        results: [(
            key: String,
            score: Double,
            ranges: [CountableClosedRange<Int>]
        )]
    )
    
    fileprivate lazy var searchQueue: DispatchQueue = { [unowned self] in
        let label = "fuse.search.queue"
        return DispatchQueue(label: label, attributes: .concurrent)
        }()
    
    /// Creates a new instance of `Fuse`
    ///
    /// - Parameters:
    ///   - location: Approximately where in the text is the pattern expected to be found. Defaults to `0`
    ///   - distance: Determines how close the match must be to the fuzzy `location` (specified above). An exact letter match which is `distance` characters away from the fuzzy location would score as a complete mismatch. A distance of `0` requires the match be at the exact `location` specified, a `distance` of `1000` would require a perfect match to be within `800` characters of the fuzzy location to be found using a 0.8 threshold. Defaults to `100`
    ///   - threshold: At what point does the match algorithm give up. A threshold of `0.0` requires a perfect match (of both letters and location), a threshold of `1.0` would match anything. Defaults to `0.6`
    ///   - maxPatternLength: The maximum valid pattern length. The longer the pattern, the more intensive the search operation will be. If the pattern exceeds the `maxPatternLength`, the `search` operation will return `nil`. Why is this important? [Read this](https://en.wikipedia.org/wiki/Word_(computer_architecture)#Word_size_choice). Defaults to `32`
    ///   - isCaseSensitive: Indicates whether comparisons should be case sensitive. Defaults to `false`
    ///   - tokenize: When true, the search algorithm will search individual words **and** the full string, computing the final score as a function of both. Note that when `tokenize` is `true`, the `threshold`, `distance`, and `location` are inconsequential for individual tokens.
    public init (location: Int = 0, distance: Int = 100, threshold: Double = 0.6, maxPatternLength: Int = 32, isCaseSensitive: Bool = false, tokenize: Bool = false) {
        self.location = location
        self.distance = distance
        self.threshold = threshold
        self.maxPatternLength = maxPatternLength
        self.isCaseSensitive = isCaseSensitive
        self.tokenize = tokenize
    }
    
    /// Creates a pattern tuple.
    ///
    /// - Parameter aString: A string from which to create the pattern tuple
    /// - Returns: A tuple containing pattern metadata
    public func createPattern (from aString: String) -> Pattern? {
        let pattern = self.isCaseSensitive ? aString : aString.lowercased()
        let len = pattern.count
        
        if len == 0 {
            return nil
        }
        
        return (
            text: pattern,
            len: len,
            mask: 1 << (len - 1),
            alphabet: FuseUtilities.calculatePatternAlphabet(pattern)
        )
    }
    
    /// Searches for a pattern in a given string.
    ///
    ///     let fuse = Fuse()
    ///     let pattern = fuse(from: "some text")
    ///     fuse(pattern, in: "some string")
    ///
    /// - Parameters:
    ///   - pattern: The pattern to search for. This is created by calling `createPattern`
    ///   - aString: The string in which to search for the pattern
    /// - Returns: A tuple containing a `score` between `0.0` (exact match) and `1` (not a match), and `ranges` of the matched characters. If no match is found will return nil.
    public func search(_ pattern: Pattern?, in aString: String) -> (score: Double, ranges: [CountableClosedRange<Int>])? {
        guard let pattern = pattern else {
            return nil
        }
        
        //If tokenize is set we will split the pattern into individual words and take the average which should result in more accurate matches
        if tokenize {
            //Split this pattern by the space character
            let wordPatterns = pattern.text.split(separator: " ").compactMap { createPattern(from: String($0)) }
            
            //Get the result for testing the full pattern string. If 2 strings have equal individual word matches this will boost the full string that matches best overall to the top
            let fullPatternResult = _search(pattern, in: aString)
            
            //Reduce all the word pattern matches and the full pattern match into a totals tuple
            let results = wordPatterns.reduce(into: fullPatternResult) { (totalResult, pattern) in
                let result = _search(pattern, in: aString)
                totalResult = (totalResult.score + result.score, totalResult.ranges + result.ranges)
            }
            
            //Average the total score by dividing the summed scores by the number of word searches + the full string search. Also remove any range duplicates since we are searching full string and words individually.
            let averagedResult = (score: results.score / Double(wordPatterns.count + 1), ranges: Array<CountableClosedRange<Int>>(Set<CountableClosedRange<Int>>(results.ranges)))
            
            //If the averaged score is 1 then there were no matches so return nil. Otherwise return the average result
            return averagedResult.score == 1 ? nil : averagedResult
            
        } else {
            let result = _search(pattern, in: aString)

            //If the averaged score is 1 then there were no matches so return nil. Otherwise return the average result
            return result.score == 1 ? nil : result
            
        }
    }
    
    //// Searches for a pattern in a given string.
    ///
    ///     _search(pattern, in: "some string")
    ///
    /// - Parameters:
    ///   - pattern: The pattern to search for. This is created by calling `createPattern`
    ///   - aString: The string in which to search for the pattern
    /// - Returns: A tuple containing a `score` between `0.0` (exact match) and `1` (not a match), and `ranges` of the matched characters. If no match is found will return a tuple with score of 1 and empty array of ranges.
    private func _search(_ pattern: Pattern, in aString: String) -> (score: Double, ranges: [CountableClosedRange<Int>]) {
        
        var text = aString
        
        if !self.isCaseSensitive {
            text = text.lowercased()
        }
        
        let textLength = text.count
        
        // Exact match
        if (pattern.text == text) {
            return (0, [0...textLength - 1])
        }
        
        let location = self.location
        let distance = self.distance
        var threshold = self.threshold
        
        var bestLocation: Int? = {
            if let index = text.index(of: pattern.text, startingFrom: location) {
                return text.distance(from: text.startIndex, to: index)
            }
            return nil
        }()
        
        // A mask of the matches. We'll use to determine all the ranges of the matches
        var matchMaskArr = [Int](repeating: 0, count: textLength)
        
        // Get all exact matches, here for speed up
        var index = text.index(of: pattern.text, startingFrom: bestLocation)
        while (index != nil) {
            let i = text.distance(from: text.startIndex, to: index!)
            let score = FuseUtilities.calculateScore(pattern.len,
                                                     e: 0,
                                                     x: i,
                                                     loc: location,
                                                     distance: distance)
            threshold = min(threshold, score)
            bestLocation = i + pattern.len
            index = text.index(of: pattern.text, startingFrom: bestLocation)
            
            var idx = 0
            while (idx < pattern.len) {
              matchMaskArr[i + idx] = 1
              idx += 1
            }
        }
        
        // Reset the best location
        bestLocation = nil
        
        var score = 1.0
        var binMax: Int = pattern.len + textLength
        var lastBitArr = [Int]()
        
        let textCount = text.count
        
        // Magic begins now
        for i in 0..<pattern.len {
            
            // Scan for the best match; each iteration allows for one more error.
            // Run a binary search to determine how far from the match location we can stray at this error level.
            var binMin = 0
            var binMid = binMax
            
            while binMin < binMid {
                if FuseUtilities.calculateScore(pattern.len, e: i, x: location, loc: location + binMid, distance: distance) <= threshold {
                    binMin = binMid
                } else {
                    binMax = binMid
                }
                binMid = ((binMax - binMin) / 2) + binMin
            }
            
            // Use the result from this iteration as the maximum for the next.
            binMax = binMid
            var start = max(1, location - binMid + 1)
            let finish = min(location + binMid, textLength) + pattern.len
            
            // Initialize the bit array
            var bitArr = [Int](repeating: 0, count: finish + 2)
            bitArr[finish + 1] = (1 << i) - 1
            
            if start > finish {
                continue
            }
            
            var currentLocationIndex: String.Index? = nil

            for j in (start...finish).reversed() {
                let currentLocation = j - 1
                
                // Need to check for `nil` case, since `patternAlphabet` is a sparse hash
                let charMatch: Int = {
                    if currentLocation < textCount {
                        currentLocationIndex = currentLocationIndex.map{text.index(before: $0)} ?? text.index(text.startIndex, offsetBy: currentLocation)
                        let char = text[currentLocationIndex!]
                        if let result = pattern.alphabet[char] {
                            return result
                        }
                    }
                    return 0
                }()
                
                // A match is found
                if charMatch != 0 {
                    matchMaskArr[currentLocation] = 1
                }
                
                // First pass: exact match
                bitArr[j] = ((bitArr[j + 1] << 1) | 1) & charMatch
                
                // Subsequent passes: fuzzy match
                if i > 0 {
                    bitArr[j] |= (((lastBitArr[j + 1] | lastBitArr[j]) << 1) | 1) | lastBitArr[j + 1]
                }
                
                if (bitArr[j] & pattern.mask) != 0 {
                    score = FuseUtilities.calculateScore(pattern.len, e: i, x: location, loc: currentLocation, distance: distance)
                    
                    // This match will almost certainly be better than any existing match. But check anyway.
                    if score <= threshold {
                        // Indeed it is
                        threshold = score
                        bestLocation = currentLocation

                        guard let bestLocation = bestLocation else {
                            break
                        }
                        
                        if bestLocation > location  {
                            // When passing `bestLocation`, don't exceed our current distance from the expected `location`.
                            start = max(1, 2 * location - bestLocation)
                        } else {
                            // Already passed `location`. No point in continuing.
                            break
                        }
                    }
                }
            }
            
            // No hope for a better match at greater error levels
            if FuseUtilities.calculateScore(pattern.len, e: i + 1, x: location, loc: location, distance: distance) > threshold {
                break
            }
            
            lastBitArr = bitArr
        }
        
        return (score, FuseUtilities.findRanges(matchMaskArr))
    }
}

extension Fuse {
    /// Searches for a text pattern in a given string.
    ///
    ///     let fuse = Fuse()
    ///     fuse.search("some text", in: "some string")
    ///
    /// **Note**: if the same text needs to be searched across many strings, consider creating the pattern once via `createPattern`, and then use the other `search` function. This will improve performance, as the pattern object would only be created once, and re-used across every search call:
    ///
    ///     let fuse = Fuse()
    ///     let pattern = fuse.createPattern(from: "some text")
    ///     fuse.search(pattern, in: "some string")
    ///     fuse.search(pattern, in: "another string")
    ///     fuse.search(pattern, in: "yet another string")
    ///
    /// - Parameters:
    ///   - text: the text string to search for.
    ///   - aString: The string in which to search for the pattern
    /// - Returns: A tuple containing a `score` between `0.0` (exact match) and `1` (not a match), and `ranges` of the matched characters.
    public func search(_ text: String, in aString: String) -> (score: Double, ranges: [CountableClosedRange<Int>])? {
        return self.search(self.createPattern(from: text), in: aString)
    }
    
    /// Searches for a text pattern in an array of srings
    ///
    /// - Parameters:
    ///   - text: The pattern string to search for
    ///   - aList: The list of string in which to search
    /// - Returns: A tuple containing the `item` in which the match is found, the `score`, and the `ranges` of the matched characters
    public func search(_ text: String, in aList: [String]) -> [SearchResult] {
        let pattern = self.createPattern(from: text)
        
        var items = [SearchResult]()
        
        for (index, item) in aList.enumerated() {
            if let result = self.search(pattern, in: item) {
                items.append((index, result.score, result.ranges))
            }
        }
        
        return items.sorted { $0.score < $1.score }
    }
    
    /// Asynchronously searches for a text pattern in an array of srings.
    ///
    /// - Parameters:
    ///   - text: The pattern string to search for
    ///   - aList: The list of string in which to search
    ///   - chunkSize: The size of a single chunk of the array. For example, if the array has `1000` items, it may be useful to split the work into 10 chunks of 100. This should ideally speed up the search logic. Defaults to `100`.
    ///   - completion: The handler which is executed upon completion
    public func search(_ text: String, in aList: [String], chunkSize: Int = 100, completion: @escaping ([SearchResult]) -> Void) {
        let pattern = self.createPattern(from: text)
        
        var items = [SearchResult]()
        
        // Serialize writes to `items`, for thread safety.
        // This label is non-unique but that should be fine as we don't expect
        // to need to debug work items running on this queue.
        let itemsQueue = DispatchQueue(label: "fuse.items.queue")
        
        let group = DispatchGroup()
        let count = aList.count
        
        stride(from: 0, to: count, by: chunkSize).forEach { offset in
            let chunk = Array(aList[offset..<min(offset + chunkSize, count)])
            group.enter()
            self.searchQueue.async {
                var chunkItems = [SearchResult]()
                
                for (index, item) in chunk.enumerated() {
                    if let result = self.search(pattern, in: item) {
                        chunkItems.append((offset + index, result.score, result.ranges))
                    }
                }
                
                itemsQueue.async {
                    items.append(contentsOf: chunkItems)
                    group.leave()
                }
            }
        }
    
        group.notify(queue: self.searchQueue) {
            // This read does not need to be protected by the queue given that
            // there's no longer concurrent access at this point.
            let sorted = items.sorted { $0.score < $1.score }
            DispatchQueue.main.async {
                completion(sorted)
            }
        }
    }
    
    /// Searches for a text pattern in an array of `Fuseable` objects.
    ///
    /// Each `FuseSearchable` object contains a `properties` accessor which returns `FuseProperty` array. Each `FuseProperty` is a tuple containing a `key` (the value of the property which should be included in the search), and a `weight` (how much "weight" to assign to the score)
    ///
    /// ## Example
    ///
    /// Ensure the object conforms to `Fuseable`:
    ///
    ///     struct Book: Fuseable {
    ///         let title: String
    ///         let author: String
    ///
    ///         var properties: [FuseProperty] {
    ///             return [
    ///                 FuseProperty(name: title, weight: 0.3),
    ///                 FuseProperty(name: author, weight: 0.7),
    ///             ]
    ///         }
    ///     }
    ///
    /// Searching:
    ///
    ///     let books: [Book] = [
    ///         Book(author: "John X", title: "Old Man's War fiction"),
    ///         Book(author: "P.D. Mans", title: "Right Ho Jeeves")
    ///     ]
    ///
    ///     let fuse = Fuse()
    ///     let results = fuse.search("Man", in: books)
    ///
    /// - Parameters:
    ///   - text: The pattern string to search for
    ///   - aList: The list of `Fuseable` objects in which to search
    /// - Returns: A list of `CollectionResult` objects
    public func search(_ text: String, in aList: [Fuseable]) -> [FusableSearchResult] {
        let pattern = self.createPattern(from: text)
        
        var collectionResult = [FusableSearchResult]()
        
        for (index, item) in aList.enumerated() {
            var scores = [Double]()
            var totalScore = 0.0
            
            var propertyResults = [(key: String, score: Double, ranges: [CountableClosedRange<Int>])]()

            item.properties.forEach { property in
                let value = property.name
                
                if let result = self.search(pattern, in: value) {
                    let weight = property.weight == 1 ? 1 : 1 - property.weight
                    let score = (result.score == 0 && weight == 1 ? 0.001 : result.score) * weight
                    totalScore += score
                    
                    scores.append(score)
                    
                    propertyResults.append((key: property.name, score: score, ranges: result.ranges))
                }
            }
            
            if scores.count == 0 {
                continue
            }
            
            collectionResult.append((
                index: index,
                score: totalScore / Double(scores.count),
                results: propertyResults
            ))
            
        }
        
        return collectionResult.sorted { $0.score < $1.score }
    }
    
    /// Asynchronously searches for a text pattern in an array of `Fuseable` objects.
    ///
    /// Each `FuseSearchable` object contains a `properties` accessor which returns `FuseProperty` array. Each `FuseProperty` is a tuple containing a `key` (the value of the property which should be included in the search), and a `weight` (how much "weight" to assign to the score)
    ///
    /// ## Example
    ///
    /// Ensure the object conforms to `Fuseable`:
    ///
    ///     struct Book: Fuseable {
    ///         let title: String
    ///         let author: String
    ///
    ///         var properties: [FuseProperty] {
    ///             return [
    ///                 FuseProperty(name: title, weight: 0.3),
    ///                 FuseProperty(name: author, weight: 0.7),
    ///             ]
    ///         }
    ///     }
    ///
    /// Searching:
    ///
    ///     let books: [Book] = [
    ///         Book(author: "John X", title: "Old Man's War fiction"),
    ///         Book(author: "P.D. Mans", title: "Right Ho Jeeves")
    ///     ]
    ///
    ///     let fuse = Fuse()
    ///     fuse.search("Man", in: books, completion: { results in
    ///         print(results)
    ///     })
    ///
    /// - Parameters:
    ///   - text: The pattern string to search for
    ///   - aList: The list of `Fuseable` objects in which to search
    ///   - chunkSize: The size of a single chunk of the array. For example, if the array has `1000` items, it may be useful to split the work into 10 chunks of 100. This should ideally speed up the search logic. Defaults to `100`.
    ///   - completion: The handler which is executed upon completion
    public func search(_ text: String, in aList: [Fuseable], chunkSize: Int = 100, completion: @escaping ([FusableSearchResult]) -> Void) {
        let pattern = self.createPattern(from: text)
        
        let group = DispatchGroup()
        let count = aList.count
        
        var collectionResult = [FusableSearchResult]()
        
        // Serialize writes to `collectionResult`, for thread safety.
        // This label is non-unique but that should be fine as we don't expect
        // to need to debug work items running on this queue.
        let collectionResultQueue = DispatchQueue(label: "fuse.result.queue")
        
        stride(from: 0, to: count, by: chunkSize).forEach { offset in
            let chunk = Array(aList[offset..<min(offset + chunkSize, count)])
            group.enter()
            self.searchQueue.async {
                var chunkResult = [FusableSearchResult]()
                
                for (index, item) in chunk.enumerated() {
                    var scores = [Double]()
                    var totalScore = 0.0
                    
                    var propertyResults = [(key: String, score: Double, ranges: [CountableClosedRange<Int>])]()

                    item.properties.forEach { property in

                        let value = property.name
                        
                        if let result = self.search(pattern, in: value) {
                            let weight = property.weight == 1 ? 1 : 1 - property.weight
                            let score = result.score * weight
                            totalScore += score
                            
                            scores.append(score)
                            
                            propertyResults.append((key: property.name, score: score, ranges: result.ranges))
                        }
                    }
                    
                    if scores.count == 0 {
                        continue
                    }
                    
                    chunkResult.append((
                        index: offset + index,
                        score: totalScore / Double(scores.count),
                        results: propertyResults
                    ))
                }
                
                collectionResultQueue.async {
                    collectionResult.append(contentsOf: chunkResult)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: self.searchQueue) {
            // This read does not need to be protected by the queue given that
            // there's no longer concurrent access at this point.
            let sorted = collectionResult.sorted { $0.score < $1.score }
            DispatchQueue.main.async {
                completion(sorted)
            }
        }
    }
}

#if swift(>=4.2)
#else
extension CountableClosedRange: Hashable where Element: Hashable {
    public var hashValue: Int { return String(describing: self).hashValue }
}
#endif
