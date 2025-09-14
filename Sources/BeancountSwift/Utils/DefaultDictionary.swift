// DefaultDictionary.swift

/// A dictionary that auto-initializes missing keys with a default value,
/// similar to Python's `collections.defaultdict`.
struct DefaultDictionary<Key: Hashable, Value> {
    @usableFromInline
    var storage: [Key: Value]

    /// Factory used to construct default values for missing keys.
    /// It’s a closure so defaults can be lazily created and support reference types.
    internal let factory: () -> Value

    // MARK: - Init

    /// Create an empty defaulting dictionary.
    init(default factory: @escaping () -> Value) {
        self.storage = [:]
        self.factory = factory
    }

    /// Create with an initial dictionary and a default factory.
    init(_ dictionary: [Key: Value] = [:], default factory: @escaping () -> Value) {
        self.storage = dictionary
        self.factory = factory
    }

    /// Convenience: pass a value to be copied as the default each time.
    /// For value types this copies; for reference types this reuses the same instance.
    /// Prefer the closure init if you need fresh reference instances.
    init(default value: @autoclosure @escaping () -> Value) {
        self.init(default: value)
    }

    // MARK: - Subscripts

    /// Defaulting access. Reading a missing key **inserts** a new default value.
    subscript(key: Key) -> Value {
        mutating get {
            if let v = storage[key] { return v }
            let v = factory()
            storage[key] = v
            return v
        }
        set {
            storage[key] = newValue
        }
    }

    /// Non-inserting read access. Returns the value or `nil` but **does not** create/insert.
    func peek(_ key: Key) -> Value? {
        storage[key]
    }

    /// Get-or-create without exposing mutation of the whole dictionary.
    @discardableResult
    mutating func ensure(_ key: Key) -> Value {
        if let v = storage[key] { return v }
        let v = factory()
        storage[key] = v
        return v
    }

    // MARK: - Basic dictionary operations

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }
    var keys: Dictionary<Key, Value>.Keys { storage.keys }
    var values: Dictionary<Key, Value>.Values { storage.values }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        storage.removeValue(forKey: key)
    }

    mutating func removeAll(keepingCapacity keep: Bool = false) {
        storage.removeAll(keepingCapacity: keep)
    }

    /// Merge another dictionary: existing values are kept unless you provide a combine closure.
    mutating func merge<S: Sequence>(
        _ other: S,
        combine: (Value, Value) -> Value
    ) where S.Element == (key: Key, value: Value) {
        for (k, v) in other {
            if let old = storage[k] {
                storage[k] = combine(old, v)
            } else {
                storage[k] = v
            }
        }
    }

    /// Map values, preserving keys, returning a plain Dictionary.
    func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> [Key: T] {
        try storage.mapValues(transform)
    }
}

// MARK: - Sequence / Collection conformity (read-only)

extension DefaultDictionary: Sequence {
    typealias Element = (key: Key, value: Value)
    func makeIterator() -> Dictionary<Key, Value>.Iterator {
        storage.makeIterator()
    }
}

extension DefaultDictionary: Collection {
    typealias Index = Dictionary<Key, Value>.Index
    var startIndex: Index { storage.startIndex }
    var endIndex: Index { storage.endIndex }
    func index(after i: Index) -> Index { storage.index(after: i) }
    subscript(position: Index) -> Element { storage[position] }
}

// MARK: - Conditional conformances

extension DefaultDictionary: Equatable where Value: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage == rhs.storage
    }
}

extension DefaultDictionary: Hashable where Value: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(storage)
    }
}

// MARK: - Conveniences for common collections

extension DefaultDictionary where Value: RangeReplaceableCollection {
    /// Append an element, auto-creating the collection.
    mutating func append(_ element: Value.Element, to key: Key) {
        self[key].append(element)
    }

    /// Extend a collection at key by a sequence.
    mutating func append<S: Sequence>(contentsOf elements: S, to key: Key)
    where S.Element == Value.Element {
        self[key].append(contentsOf: elements)
    }
}
