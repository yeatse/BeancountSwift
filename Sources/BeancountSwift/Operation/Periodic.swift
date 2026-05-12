//
//  Periodic.swift
//
//
//  Created by OpenAI on 2026/5/12.
//

import Foundation
import OrderedCollections

private enum PeriodicError: Error, LocalizedError {
    case invalidConfig(String)
    case invalidPluginConfig(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let config):
            return "Invalid periodic config: \(config)"
        case .invalidPluginConfig(let config):
            return "Invalid periodic plugin config: \(config)"
        }
    }
}

private struct PeriodicPluginConfig {
    var generateUntil: Date?

    init(_ config: String?) throws {
        guard let config, config.isEmpty == false else { return }
        guard let keyRange = config.range(of: "generate_until") else { return }
        let tail = config[keyRange.upperBound...]
        guard let colon = tail.firstIndex(of: ":") else {
            throw PeriodicError.invalidPluginConfig(config)
        }
        let afterColon = tail[tail.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let quote = afterColon.first, quote == "'" || quote == "\"" else {
            throw PeriodicError.invalidPluginConfig(config)
        }
        let valueStart = afterColon.index(after: afterColon.startIndex)
        guard let valueEnd = afterColon[valueStart...].firstIndex(of: quote) else {
            throw PeriodicError.invalidPluginConfig(config)
        }
        let value = String(afterColon[valueStart..<valueEnd])
        if value == "today" {
            generateUntil = Calendar.current.startOfDay(for: Date())
        } else if let date = Date.fromDateString(value) {
            generateUntil = date
        } else {
            throw PeriodicError.invalidPluginConfig(config)
        }
    }
}

private struct PeriodicConfig {
    var total: Decimal
    var start: Date
    var duration: Int
    var steps: [(days: Int, ratio: Decimal)]
    var equalAmount: Bool
    var salvageValue: Decimal
    var formula: String
}

private struct PeriodicConfigParser {
    private static let day: TimeInterval = 24 * 60 * 60

    static func parse(
        _ rawConfig: String,
        defaultTotal: Decimal,
        defaultStart: Date,
        defaultDuration: String = "M",
        defaultStep: String = "D",
        defaultValue: Decimal = 0,
        defaultFormula: String = "line"
    ) throws -> PeriodicConfig {
        let config = rawConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = config[...]

        let total = parseTotal(from: &remainder) ?? defaultTotal
        let durationPart = parseDurationPart(from: &remainder)
        let stepPart = parseStepPart(from: &remainder)
        let formula = parseFormula(from: &remainder) ?? defaultFormula
        let salvageValue = parseValue(from: &remainder, total: total) ?? defaultValue

        guard remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PeriodicError.invalidConfig(rawConfig)
        }

        let start = durationPart.start ?? defaultStart
        let duration: Int
        if let end = durationPart.end {
            duration = days(from: start, to: end)
        } else if let amount = durationPart.amount {
            duration = durationDays(from: start, amount: amount.value, unit: amount.unit)
        } else {
            let fallback = try parseDuration(defaultDuration)
            duration = durationDays(from: start, amount: fallback.value, unit: fallback.unit)
        }

        let step = try stepPart ?? parseStep(defaultStep)
        let steps = stepDays(from: start, duration: duration, amount: step.value, unit: step.unit)

        return PeriodicConfig(
            total: total,
            start: start,
            duration: duration,
            steps: steps,
            equalAmount: step.realDays == false,
            salvageValue: salvageValue,
            formula: formula
        )
    }

    private struct AmountUnit {
        var value: Decimal
        var unit: Character?
    }

    private struct StepUnit {
        var value: Int
        var unit: Character?
        var realDays: Bool
    }

    private struct DurationPart {
        var amount: AmountUnit?
        var start: Date?
        var end: Date?
    }

    private static func parseTotal(from input: inout Substring) -> Decimal? {
        consumeSpaces(&input)
        guard let match = input.prefixMatch(of: #/(\d+(?:\.\d+)?)\s*-/#) else { return nil }
        input.removeFirst(match.0.count)
        return Decimal(string: String(match.1))
    }

    private static func parseDurationPart(from input: inout Substring) -> DurationPart {
        var part = DurationPart()
        consumeSpaces(&input)

        if let match = input.prefixMatch(
            of: #/(\d+(?:\.\d+)?)?\s*(Days?|Weeks?|Months?|Quarters?|Years?|[DWMQY])?/#
        ) {
            let token = String(match.0).trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty == false {
                let amount = Decimal(string: match.1.map(String.init) ?? "1") ?? 1
                part.amount = AmountUnit(value: amount, unit: unitLetter(match.2.map(String.init)))
                input.removeFirst(match.0.count)
            }
        }

        consumeSpaces(&input)
        if let match = input.prefixMatch(of: #/@\s*(\d{4}-\d{2}-\d{2})/#) {
            part.start = Date.fromDateString(String(match.1))
            input.removeFirst(match.0.count)
        }

        consumeSpaces(&input)
        if let match = input.prefixMatch(of: #/~\s*(\d{4}-\d{2}-\d{2})/#) {
            part.end = Date.fromDateString(String(match.1))
            input.removeFirst(match.0.count)
        }

        return part
    }

    private static func parseStepPart(from input: inout Substring) -> StepUnit? {
        consumeSpaces(&input)
        guard input.first == "/" else { return nil }
        input.removeFirst()
        consumeSpaces(&input)
        guard
            let match = input.prefixMatch(
                of:
                    #/(?:(\d+)\s*(Days?!?|Weeks?!?|Months?!?|Quarters?!?|Years?!?|[DWMQY]!?)?|(Daily!?|Weekly!?|Monthly!?|Quarterly!?|Yearly!?))/#
            )
        else {
            return nil
        }

        input.removeFirst(match.0.count)
        let named = match.3.map(String.init)
        let unitText = named ?? match.2.map(String.init)
        let realDays = unitText?.hasSuffix("!") == true
        let cleanUnit = unitText?.trimmingCharacters(in: CharacterSet(charactersIn: "!"))

        return StepUnit(
            value: Int(match.1.map(String.init) ?? "1") ?? 1,
            unit: unitLetter(cleanUnit),
            realDays: realDays
        )
    }

    private static func parseFormula(from input: inout Substring) -> String? {
        consumeSpaces(&input)
        guard
            let match = input.prefixMatch(
                of:
                    #/\*(linear|straight|line|load|work-load|accelerated-sum|sum|accelerated-declining)/#
            )
        else {
            return nil
        }
        input.removeFirst(match.0.count)
        return String(match.1)
    }

    private static func parseValue(from input: inout Substring, total: Decimal) -> Decimal? {
        consumeSpaces(&input)
        guard let match = input.prefixMatch(of: #/[+=]\s*(\d+(?:\.\d+)?%?)/#) else {
            return nil
        }
        input.removeFirst(match.0.count)
        let value = String(match.1)
        if value.hasSuffix("%") {
            let percent = Decimal(string: String(value.dropLast())) ?? 0
            return percent / 100 * total
        }
        return Decimal(string: value)
    }

    private static func parseDuration(_ input: String) throws -> AmountUnit {
        var substring = input[...]
        let part = parseDurationPart(from: &substring)
        guard let amount = part.amount else { throw PeriodicError.invalidConfig(input) }
        return amount
    }

    private static func parseStep(_ input: String) throws -> StepUnit {
        let source = "/" + input
        var substring = source[...]
        guard let step = parseStepPart(from: &substring) else {
            throw PeriodicError.invalidConfig(input)
        }
        return step
    }

    private static func unitLetter(_ text: String?) -> Character? {
        guard let first = text?.first else { return nil }
        return Character(String(first).uppercased())
    }

    private static func durationDays(from start: Date, amount: Decimal, unit: Character?) -> Int {
        switch unit {
        case "D":
            return NSDecimalNumber(decimal: amount).intValue
        case "W":
            return NSDecimalNumber(decimal: amount * 7).intValue
        case "M":
            return monthDuration(from: start, months: amount)
        case "Q":
            return monthDuration(from: start, months: amount * 3)
        case "Y":
            return monthDuration(from: start, months: amount * 12)
        default:
            return NSDecimalNumber(decimal: amount).intValue
        }
    }

    private static func monthDuration(from start: Date, months: Decimal) -> Int {
        let wholeMonths = NSDecimalNumber(decimal: months.rounded(0, .down)).intValue
        let wholeDuration = days(
            from: start,
            to: Calendar.current.date(byAdding: .month, value: wholeMonths, to: start) ?? start
        )
        let fractional = months - Decimal(wholeMonths)
        return wholeDuration + NSDecimalNumber(decimal: fractional * 30).intValue
    }

    private static func stepDays(
        from start: Date,
        duration: Int,
        amount: Int,
        unit: Character?
    ) -> [(days: Int, ratio: Decimal)] {
        switch unit {
        case "D":
            return simpleSteps(duration: duration, step: amount)
        case "W":
            return simpleSteps(duration: duration, step: amount * 7)
        case "M":
            return calendarSteps(from: start, duration: duration) {
                Calendar.current.date(byAdding: .month, value: $0 * amount, to: start) ?? start
            }
        case "Q":
            return calendarSteps(from: start, duration: duration) {
                Calendar.current.date(byAdding: .month, value: $0 * amount * 3, to: start) ?? start
            }
        case "Y":
            return calendarSteps(from: start, duration: duration) {
                Calendar.current.date(byAdding: .year, value: $0 * amount, to: start) ?? start
            }
        default:
            return simpleSteps(duration: duration, step: amount)
        }
    }

    private static func simpleSteps(duration: Int, step: Int) -> [(days: Int, ratio: Decimal)] {
        guard step > 0 else { return [] }
        var steps: [(Int, Decimal)] = []
        var remainder = duration
        while remainder > 0 {
            let days = min(step, remainder)
            steps.append((days, days == step ? 1 : Decimal(days) / Decimal(step)))
            remainder -= days
        }
        return steps
    }

    private static func calendarSteps(
        from startDate: Date,
        duration: Int,
        tailDate: (Int) -> Date
    ) -> [(days: Int, ratio: Decimal)] {
        var steps: [(Int, Decimal)] = []
        var start = startDate
        var remainder = duration
        var index = 1

        while remainder > 0 {
            let tail = tailDate(index)
            let delta = days(from: start, to: tail)
            guard delta > 0 else { break }

            if delta <= remainder {
                steps.append((delta, 1))
                start = tail
                remainder -= delta
            } else {
                steps.append((remainder, Decimal(remainder) / Decimal(delta)))
                remainder = 0
            }
            index += 1
        }
        return steps
    }

    private static func consumeSpaces(_ input: inout Substring) {
        while input.first?.isWhitespace == true {
            input.removeFirst()
        }
    }

    private static func days(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day
            ?? Int(end.timeIntervalSince(start) / day)
    }
}

private enum PeriodicSupport {
    static func metaString(_ meta: MetaData?, key: String) -> String? {
        guard case .string(let value) = meta?[key] else { return nil }
        return value
    }

    static func metadata(_ meta: MetaData, deleting keys: [String]) -> MetaData {
        var result = meta
        for key in keys {
            result.removeValue(forKey: key)
        }
        return result
    }

    static func optionalMetadata(_ meta: MetaData?, deleting keys: [String]) -> MetaData? {
        guard let meta else { return nil }
        var result = meta
        for key in keys {
            result.removeValue(forKey: key)
        }
        return result
    }

    static func entry(
        from original: Directive<Cost>,
        date: Date,
        meta: MetaData,
        narration: String?,
        postings: [Posting<Cost>]
    ) -> Directive<Cost> {
        guard case .transaction(let transaction) = original.content else {
            return original
        }
        return Directive(
            meta: meta,
            date: date,
            comment: original.comment,
            content: .transaction(
                Transaction(
                    flag: transaction.flag,
                    payee: transaction.payee,
                    narration: narration,
                    tags: transaction.tags,
                    links: transaction.links,
                    postings: postings
                )
            )
        )
    }

    static func makeStepPostings(
        posting: Posting<Cost>,
        account: Account,
        metaKey: String,
        amount: Decimal
    ) -> [Posting<Cost>] {
        let cleanMeta = optionalMetadata(posting.meta, deleting: [metaKey, "narration"])
        return [
            Posting(
                account: account,
                units: Amount(number: -amount, currency: posting.units.currency),
                cost: posting.cost,
                price: posting.price,
                flag: posting.flag,
                meta: posting.meta,
                comment: posting.comment
            ),
            Posting(
                account: posting.account,
                units: Amount(number: amount, currency: posting.units.currency),
                cost: posting.cost,
                price: posting.price,
                flag: posting.flag,
                meta: cleanMeta,
                comment: posting.comment
            ),
        ]
    }

    static func buildSteps(
        metaKey: String,
        entry: Directive<Cost>,
        configs: [(config: PeriodicConfig, posting: Posting<Cost>, account: Account)],
        positive: Bool,
        suffix: String,
        generateUntil: Date?
    ) -> [Directive<Cost>] {
        guard case .transaction(let transaction) = entry.content else { return [] }

        let narration: String?
        let entryMeta: MetaData
        if configs.count == 1 {
            let posting = configs[0].posting
            narration = metaString(posting.meta, key: "narration") ?? transaction.narration
            entryMeta = metadata(entry.meta, deleting: [metaKey])
        } else {
            narration = transaction.narration
            entryMeta = metadata(entry.meta, deleting: [metaKey])
        }

        let template = (narration.map { $0 + " " } ?? "") + suffix
        var entries: [Directive<Cost>] = []

        for (config, posting, account) in configs {
            let total = config.total - config.salvageValue
            var amountRemainder = total
            var startDate = config.start
            let place =
                config.equalAmount
                ? smartScale(reference: total, divisor: Decimal(config.steps.count))
                : smartScale(reference: total, divisor: Decimal(config.duration))
            var roundingRemainder: Decimal = 0
            let ratioTotal = config.steps.reduce(Decimal(0)) { $0 + $1.ratio }

            for (index, step) in config.steps.enumerated() {
                if let generateUntil, startDate > generateUntil {
                    break
                }

                let stepAmount: Decimal
                if index < config.steps.count - 1 {
                    let raw =
                        config.equalAmount
                        ? step.ratio * total / ratioTotal
                        : Decimal(step.days) / Decimal(config.duration) * total
                    var rounded = raw.rounded(place, .bankers)
                    let remainder = raw - rounded
                    let roundedCarry = roundingRemainder.rounded(place, .bankers)
                    if abs(NSDecimalNumber(decimal: roundedCarry).doubleValue) > 0 {
                        rounded += roundedCarry
                        roundingRemainder -= roundedCarry
                    }
                    roundingRemainder += remainder
                    amountRemainder -= rounded
                    stepAmount = rounded
                } else {
                    stepAmount = amountRemainder
                }

                let signedAmount = positive ? stepAmount : -stepAmount
                let newPostings = makeStepPostings(
                    posting: posting,
                    account: account,
                    metaKey: metaKey,
                    amount: signedAmount
                )
                let newNarration = String(
                    format: template,
                    locale: Locale(identifier: "en_US_POSIX"),
                    index + 1,
                    config.steps.count
                )

                if entries.indices.contains(index) {
                    append(postings: newPostings, to: &entries[index], combining: account)
                } else {
                    entries.append(
                        PeriodicSupport.entry(
                            from: entry,
                            date: startDate,
                            meta: entryMeta,
                            narration: newNarration,
                            postings: newPostings
                        )
                    )
                }

                startDate =
                    Calendar.current.date(byAdding: .day, value: step.days, to: startDate)
                    ?? startDate
            }
        }

        return entries
    }

    private static func append(
        postings: [Posting<Cost>],
        to entry: inout Directive<Cost>,
        combining account: Account
    ) {
        guard case .transaction(var transaction) = entry.content else { return }
        if let existingIndex = transaction.postings.firstIndex(where: { $0.account == account }) {
            for posting in postings {
                let existing = transaction.postings[existingIndex]
                if posting.account == account,
                    posting.units.currency == existing.units.currency,
                    posting.cost == existing.cost,
                    posting.price == existing.price
                {
                    transaction.postings[existingIndex].units.number += posting.units.number
                } else {
                    transaction.postings.append(posting)
                }
            }
        } else {
            transaction.postings.append(contentsOf: postings)
        }
        entry.content = .transaction(transaction)
    }

    private static func smartScale(reference: Decimal, divisor: Decimal) -> Int {
        let exponent = max(-reference.exponent, 0)
        let divisorValue = abs(NSDecimalNumber(decimal: divisor).doubleValue)
        let added = divisorValue > 0 ? Int(round(log10(divisorValue))) + 1 : 0
        return min(max(exponent + added, 2), 6)
    }
}

private func selectedPostingGroups(
    entry: Directive<Cost>,
    transaction: Transaction<Cost>,
    metaKey: String
) throws -> [[(index: Int, config: PeriodicConfig, configString: String)]] {
    var groups: OrderedDictionary<String, [(Int, PeriodicConfig, String)]> = [:]
    let entryConfigString = PeriodicSupport.metaString(entry.meta, key: metaKey)
    var entryConfig: PeriodicConfig?

    if let entryConfigString {
        entryConfig = try PeriodicConfigParser.parse(
            entryConfigString,
            defaultTotal: 0,
            defaultStart: entry.date
        )
        groups[entryConfigString] = []
    }

    for (index, posting) in transaction.postings.enumerated() {
        if let configString = PeriodicSupport.metaString(posting.meta, key: metaKey) {
            let config = try PeriodicConfigParser.parse(
                configString,
                defaultTotal: posting.units.number,
                defaultStart: entry.date
            )
            groups[configString, default: []].append((index, config, configString))
        } else if let entryConfigString, let entryConfig {
            var config = entryConfig
            config.total = posting.units.number
            groups[entryConfigString, default: []].append((index, config, entryConfigString))
        }
    }

    return groups.values.map { $0 }
}

struct PeriodicRecurPlugin: BeancountPlugin {
    static let name = "beancount_periodic.recur"

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        let pluginConfig = try PeriodicPluginConfig(config)
        var result: [Directive<Cost>] = []
        var generated: [Directive<Cost>] = []
        var errors: [Error] = []

        for entry in entries {
            guard case .transaction(let transaction) = entry.content,
                let configString = PeriodicSupport.metaString(entry.meta, key: "recur")
            else {
                result.append(entry)
                continue
            }

            do {
                let periodic = try PeriodicConfigParser.parse(
                    configString,
                    defaultTotal: 0,
                    defaultStart: entry.date
                )
                let entryMeta = PeriodicSupport.metadata(
                    entry.meta, deleting: ["recur", "narration"])
                let template = (transaction.narration.map { $0 + " " } ?? "") + "Recurring(%d/%d)"
                var start = periodic.start

                for (index, step) in periodic.steps.enumerated() {
                    if let generateUntil = pluginConfig.generateUntil, start > generateUntil {
                        break
                    }
                    generated.append(
                        PeriodicSupport.entry(
                            from: entry,
                            date: start,
                            meta: entryMeta,
                            narration: String(
                                format: template,
                                locale: Locale(identifier: "en_US_POSIX"),
                                index + 1,
                                periodic.steps.count
                            ),
                            postings: transaction.postings
                        )
                    )
                    start =
                        Calendar.current.date(byAdding: .day, value: step.days, to: start) ?? start
                }
            } catch {
                errors.append(error)
                result.append(entry)
            }
        }

        result.append(contentsOf: generated)
        return (result.sorted(), errors)
    }
}

struct PeriodicSplitPlugin: BeancountPlugin {
    static let name = "beancount_periodic.split"

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        let pluginConfig = try PeriodicPluginConfig(config)
        var result: [Directive<Cost>] = []
        var generated: [Directive<Cost>] = []
        var errors: [Error] = []

        for entry in entries {
            guard case .transaction(let transaction) = entry.content,
                let configString = PeriodicSupport.metaString(entry.meta, key: "split")
            else {
                result.append(entry)
                continue
            }

            do {
                let periodic = try PeriodicConfigParser.parse(
                    configString,
                    defaultTotal: 0,
                    defaultStart: entry.date
                )
                let entryMeta = PeriodicSupport.metadata(
                    entry.meta, deleting: ["split", "narration"])
                let totalDays = Decimal(periodic.steps.reduce(0) { $0 + $1.days })
                let template = (transaction.narration.map { $0 + " " } ?? "") + "Split(%d/%d)"
                var start = periodic.start

                for (index, step) in periodic.steps.enumerated() {
                    if let generateUntil = pluginConfig.generateUntil, start > generateUntil {
                        break
                    }
                    let multiplier = Decimal(step.days) / totalDays
                    let postings = transaction.postings.map { posting in
                        Posting(
                            account: posting.account,
                            units: Amount(
                                number: posting.units.number * multiplier,
                                currency: posting.units.currency
                            ),
                            cost: posting.cost,
                            price: posting.price,
                            flag: posting.flag,
                            meta: posting.meta,
                            comment: posting.comment
                        )
                    }
                    generated.append(
                        PeriodicSupport.entry(
                            from: entry,
                            date: start,
                            meta: entryMeta,
                            narration: String(
                                format: template,
                                locale: Locale(identifier: "en_US_POSIX"),
                                index + 1,
                                periodic.steps.count
                            ),
                            postings: postings
                        )
                    )
                    start =
                        Calendar.current.date(byAdding: .day, value: step.days, to: start) ?? start
                }
            } catch {
                errors.append(error)
                result.append(entry)
            }
        }

        result.append(contentsOf: generated)
        return (result.sorted(), errors)
    }
}

struct PeriodicAmortizePlugin: BeancountPlugin {
    static let name = "beancount_periodic.amortize"

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        let pluginConfig = try PeriodicPluginConfig(config)
        var result = entries
        var generated: [Directive<Cost>] = []
        var errors: [Error] = []

        for entryIndex in result.indices {
            guard case .transaction(var transaction) = result[entryIndex].content else { continue }

            do {
                let groups = try selectedPostingGroups(
                    entry: result[entryIndex],
                    transaction: transaction,
                    metaKey: "amortize"
                )
                var inserts: [(Int, Posting<Cost>)] = []

                for group in groups {
                    var buildConfigs: [(PeriodicConfig, Posting<Cost>, Account)] = []
                    for item in group {
                        let posting = transaction.postings[item.index]
                        guard
                            posting.account.type(config: options.accountNames) == .expenses
                                || posting.account.type(config: options.accountNames) == .income
                        else { continue }

                        let root =
                            posting.account.type(config: options.accountNames) == .expenses
                            ? options.accountNames.equity + ":Amortization"
                            : options.accountNames.equity + ":Received"
                        let account = Account(id: root + ":" + posting.account.sansRoot)
                        let total = item.config.total - item.config.salvageValue
                        let cleanMeta = PeriodicSupport.optionalMetadata(
                            posting.meta,
                            deleting: ["amortize", "narration"]
                        )

                        if total == posting.units.number {
                            transaction.postings[item.index].account = account
                        } else {
                            transaction.postings[item.index].units.number -= total
                            inserts.append(
                                (
                                    item.index + 1,
                                    Posting(
                                        account: account,
                                        units: Amount(
                                            number: total,
                                            currency: posting.units.currency
                                        ),
                                        cost: posting.cost,
                                        price: posting.price,
                                        flag: posting.flag,
                                        meta: cleanMeta,
                                        comment: posting.comment
                                    )
                                )
                            )
                        }

                        buildConfigs.append((item.config, posting, account))
                    }

                    generated.append(
                        contentsOf: PeriodicSupport.buildSteps(
                            metaKey: "amortize",
                            entry: result[entryIndex],
                            configs: buildConfigs,
                            positive: true,
                            suffix: "Amortized(%d/%d)",
                            generateUntil: pluginConfig.generateUntil
                        )
                    )
                }

                for insert in inserts.sorted(by: { $0.0 > $1.0 }) {
                    transaction.postings.insert(insert.1, at: insert.0)
                }
                result[entryIndex].content = .transaction(transaction)
            } catch {
                errors.append(error)
            }
        }

        result.append(contentsOf: generated)
        return (result.sorted(), errors)
    }
}

struct PeriodicDepreciatePlugin: BeancountPlugin {
    static let name = "beancount_periodic.depreciate"

    func process(entries: [Directive<Cost>], options: Options, config: String?) throws -> (
        entries: [Directive<Cost>], errors: [Error]
    ) {
        let pluginConfig = try PeriodicPluginConfig(config)
        var result = entries
        var generated: [Directive<Cost>] = []
        var errors: [Error] = []
        var openedAccounts = Set(
            result.compactMap { entry -> Account? in
                if case .open(let open) = entry.content {
                    return open.account
                }
                return nil
            })

        let openMetaByAccount = Dictionary(
            uniqueKeysWithValues: result.compactMap { entry -> (Account, MetaData)? in
                if case .open(let open) = entry.content {
                    return (open.account, entry.meta)
                }
                return nil
            }
        )

        for entry in result {
            guard case .transaction(let transaction) = entry.content else { continue }
            do {
                let groups = try selectedPostingGroups(
                    entry: entry,
                    transaction: transaction,
                    metaKey: "depreciate"
                )

                for group in groups {
                    var buildConfigs: [(PeriodicConfig, Posting<Cost>, Account)] = []
                    for item in group {
                        let posting = transaction.postings[item.index]
                        guard posting.account.type(config: options.accountNames) == .assets else {
                            continue
                        }

                        let account = depreciationAccount(
                            for: posting.account,
                            openMetaByAccount: openMetaByAccount,
                            options: options
                        )

                        if openedAccounts.contains(account) == false {
                            generated.append(
                                Directive(
                                    meta: entry.meta,
                                    date: entry.date,
                                    content: .open(
                                        Open(
                                            account: account,
                                            currencies: [posting.units.currency],
                                            booking: nil
                                        )
                                    )
                                )
                            )
                            openedAccounts.insert(account)
                        }

                        buildConfigs.append((item.config, posting, account))
                    }

                    generated.append(
                        contentsOf: PeriodicSupport.buildSteps(
                            metaKey: "depreciate",
                            entry: entry,
                            configs: buildConfigs,
                            positive: false,
                            suffix: "Depreciated(%d/%d)",
                            generateUntil: pluginConfig.generateUntil
                        )
                    )
                }
            } catch {
                errors.append(error)
            }
        }

        result.append(contentsOf: generated)
        return (result.sorted(), errors)
    }

    private func depreciationAccount(
        for account: Account,
        openMetaByAccount: [Account: MetaData],
        options: Options
    ) -> Account {
        if case .string(let override) = openMetaByAccount[account]?["depreciate_account"] {
            return Account(id: override)
        }
        return Account(id: options.accountNames.expenses + ":Depreciation:" + account.sansRoot)
    }
}
