//
//  DefaultDictionaryTests.swift
//
import Testing
@testable import BeancountSwift

struct DefaultDictionaryTests {
    // Simple reference type for testing reference semantics
    final class Box: Equatable, Hashable {
        var value: Int
        init(_ v: Int = 0) { self.value = v }
        static func == (lhs: Box, rhs: Box) -> Bool { lhs === rhs }
        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    @Test func initAndDefaultInsertion() {
        var dd = DefaultDictionary<String, Int>(default: 0)
        #expect(dd.isEmpty)

        // Accessing a missing key inserts the default
        #expect(dd["a"] == 0)
        #expect(dd.count == 1)

        // Setting a value updates storage
        dd["a"] = 42
        #expect(dd["a"] == 42)
        #expect(dd.count == 1)
    }

    @Test func peekDoesNotInsert() {
        var dd = DefaultDictionary<String, Int>(default: 0)
        #expect(dd.peek("missing") == nil)
        #expect(dd.isEmpty)

        // After ensure, peek returns value
        _ = dd.ensure("k")
        #expect(dd.peek("k") == 0)
        #expect(dd.count == 1)
    }

    @Test func ensureReturnsExistingOrCreates() {
        var dd = DefaultDictionary<String, Int>(default: 1)
        #expect(dd.ensure("x") == 1)
        dd["x"] = 7
        #expect(dd.ensure("x") == 7)
        #expect(dd.count == 1)
    }

    @Test func removeAndRemoveAll() {
        var dd = DefaultDictionary<String, Int>(["a": 1, "b": 2], default: { 0 })
        #expect(dd.count == 2)
        #expect(dd.removeValue(forKey: "a") == 1)
        #expect(dd.removeValue(forKey: "z") == nil)
        #expect(dd.count == 1)
        dd.removeAll()
        #expect(dd.isEmpty)
    }

    @Test func keysAndValuesReflectStorage() {
        var dd = DefaultDictionary<String, Int>(default: 0)
        dd["a"] = 1
        dd["b"] = 2
        let keys = Set(dd.keys)
        let values = Set(dd.values)
        #expect(keys == Set(["a", "b"]))
        #expect(values == Set([1, 2]))
    }

    @Test func mergeWithCombine() {
        var dd = DefaultDictionary<String, Int>(["a": 1, "b": 2], default: { 0 })
        let other: [String: Int] = ["b": 10, "c": 3]
        dd.merge(other, combine: +)
        // a unchanged, b combined, c inserted
        #expect(dd["a"] == 1)
        #expect(dd["b"] == 12)
        #expect(dd["c"] == 3)
    }

    @Test func mapValuesProducesDictionary() {
        let dd = DefaultDictionary<String, Int>(["a": 1, "b": 2], default: { 0 })
        let mapped = dd.mapValues { String($0) }
        #expect(mapped == ["a": "1", "b": "2"])
    }

    @Test func sequenceAndCollectionConformance() {
        var dd = DefaultDictionary<String, Int>(default: 0)
        dd["x"] = 1
        dd["y"] = 2

        // Sequence iteration
        let pairs = Dictionary(uniqueKeysWithValues: dd.map { ($0.key, $0.value) })
        #expect(pairs == ["x": 1, "y": 2])

        // Collection indices
        #expect(dd.startIndex == dd.storage.startIndex)
        #expect(dd.endIndex == dd.storage.endIndex)
        let first = dd[dd.startIndex]
        #expect([("x", 1), ("y", 2)].contains { $0.0 == first.key && $0.1 == first.value })
    }

    @Test func equatableAndHashableWhenValueSupportsIt() {
        let a = DefaultDictionary<String, Int>(["k": 1], default: { 0 })
        let b = DefaultDictionary<String, Int>(["k": 1], default: { 0 })
        let c = DefaultDictionary<String, Int>(["k": 2], default: { 0 })
        #expect(a == b)
        #expect(a != c)

        // Hashable conformance (Value: Hashable)
        let set: Set<DefaultDictionary<String, Int>> = [a, b]
        #expect(set.count == 1)
    }

    @Test func rrcConveniences() {
        var dd = DefaultDictionary<String, [Int]>(default: [])
        dd.append(1, to: "a")
        dd.append(contentsOf: [2, 3], to: "a")
        dd.append(4, to: "b")
        #expect(dd["a"] == [1, 2, 3])
        #expect(dd["b"] == [4])
    }

    @Test func defaultValueReferenceSemantics() {
        // Using the value overload with a reference type reuses the same instance.
        let shared = Box()
        var dd = DefaultDictionary<String, Box>(default: shared)
        dd["a"].value = 10
        // Different key gets the SAME instance
        #expect(dd["a"] === dd["b"]) // identity check
        #expect(dd["b"].value == 10)
    }

    @Test func factoryClosureCreatesFreshReferences() {
        // Using the closure overload can create a fresh instance per missing key.
        var dd = DefaultDictionary<String, Box>(default: Box())
        dd["a"].value = 7
        #expect(!(dd["a"] === dd["b"])) // different instances
        #expect(dd["b"].value == 0)
    }
}
