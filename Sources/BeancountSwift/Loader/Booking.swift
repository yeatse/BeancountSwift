//
//  File.swift
//
//
//  Created by Yeatse on 2023/12/24.
//

import Foundation

extension Dictionary {
    mutating func putIfAbsent(key: Key, value: Value) {
        if !keys.contains(key) {
            self[key] = value
        }
    }
}

enum CategorizationError: Error {
    case failedToCategorize(txn: Transaction<CostSpec>, index: Int)
    case extraAutoPostings(txn: Transaction<CostSpec>)
    case cannotResolve(txn: Transaction<CostSpec>, name: String)
}

extension DirectiveContent<CostSpec> {
    func resolved() -> DirectiveContent<Cost> {
        switch self {
            case .open(let open): .open(open)
            case .close(let close): .close(close)
            case .commodity(let commodity): .commodity(commodity)
            case .pad(let pad): .pad(pad)
            case .balance(let balance): .balance(balance)
            case .transaction(_): fatalError()
            case .note(let note): .note(note)
            case .event(let event): .event(event)
            case .query(let query): .query(query)
            case .price(let price): .price(price)
            case .document(let document): .document(document)
            case .custom(let custom): .custom(custom)
        }
    }
}

struct Booker {
    func book(ledger: ParsedLedger<CostSpec>) -> ParsedLedger<Cost> {
        let method = ledger.options
            .first { $0.key == "booking_method" }
            .flatMap { Booking(rawValue: $0.value) }
        var bookings: [Account: Booking] = [:]
        for directive in ledger.directives {
            if case .open(let open) = directive.content, let booking = open.booking {
                bookings[open.account] = booking
            }
        }
        let bookingStore = BookingMethodStore(mappings: bookings,
                                              defaultMethod: method ?? .STRICT)
        
        
        var newEntries = [Directive<Cost>]()
        var errors = [Error]()
        
        var balances = [Account: Inventory]()
        for directive in ledger.directives {
            let newEntry: Directive<Cost>
            if case .transaction(let txn) = directive.content {
                // Group postings by currency.
                let (referGroups, catErrors) = categorizeByCurrency(transaction: txn, balances: balances)
                guard catErrors.isEmpty else {
                    errors += catErrors
                    continue
                }
                let postingGroups = replaceCurrencies(postings: txn.postings, referGroups: referGroups)
                
                // Get the list of tolerances.
                let tolerances = Interpolate().inferTolerances(postings: txn.postings, options: [:])
                
                // Resolve reductions to a particular lot in their inventory balance.
                var replPostings = [Posting<Cost>]()
                for (currency, groupPostings) in postingGroups {
                    let (bookedPostings, bookingErrors) = bookReductions(entry: directive,
                                                                         groupPostings: groupPostings,
                                                                         balances: balances,
                                                                         methods: bookingStore)
                    
                    guard bookingErrors.isEmpty else {
                        errors += bookingErrors
                        continue
                    }
                    
                    let (interPostings, interErrors) = interpolateGroup(postings: bookedPostings, currency: currency, tolerances: tolerances)
                    if !interErrors.isEmpty {
                        errors += interErrors
                    }
                    replPostings += interPostings
                }
                
                newEntry = .init(
                    meta: directive.meta,
                    date: directive.date,
                    comment: directive.comment,
                    content: .transaction(.init(
                        flag: txn.flag,
                        payee: txn.payee,
                        narration: txn.narration,
                        tags: txn.tags,
                        links: txn.links,
                        postings: replPostings
                    ))
                )
                
                for posting in replPostings {
                    let balance = balances[posting.account, default: Inventory()]
                    balance.addPosition(.init(posting: posting))
                    balances[posting.account] = balance
                }
            } else {
                newEntry = .init(meta: directive.meta,
                                 date: directive.date,
                                 comment: directive.comment,
                                 content: directive.content.resolved())
            }
            newEntries.append(newEntry)
        }
        
        return .init(options: ledger.options,
                     plugins: ledger.plugins,
                     directives: newEntries,
                     errors: ledger.errors + errors)
    }
    
    typealias Refer = (index: Int, unitsCurrency: Currency?, costCurrency: Currency?, priceCurrency: Currency?)
    
    func getBucketCurrency(refer: Refer) -> Currency? {
        if let costCurrency = refer.costCurrency, costCurrency != .missing {
            return costCurrency
        } else if let priceCurrency = refer.priceCurrency, priceCurrency != .missing {
            return priceCurrency
        } else if refer.costCurrency == nil, refer.priceCurrency == nil,
                  let unitsCurrency = refer.unitsCurrency, unitsCurrency != .missing {
            return unitsCurrency
        }
        return nil
    }
    
    func categorizeByCurrency(transaction: Transaction<CostSpec>, balances: [Account: Inventory]) -> ([(Currency, [Refer])], [Error]) {
        var errors = [Error]()
        
        var groups = [Currency: [Refer]]()
        var sortDict = [Currency: Int]()
        var autoPostings = [Refer]()
        var unknown = [Refer]()
        
        for (index, posting) in transaction.postings.enumerated() {
            let units = posting.units
            let cost = posting.cost
            let price = posting.price
            
            let unitsCurrency = units == .missing ? nil : units.currency
            var costCurrency = cost?.currency
            var priceCurrency = price == .missing ? nil : price?.currency
            
            if costCurrency == .missing, let priceCurrency, priceCurrency != .missing {
                costCurrency = priceCurrency
            }
            if priceCurrency == .missing, let costCurrency, costCurrency != .missing {
                priceCurrency = costCurrency
            }
            
            let refer: Refer = (index, unitsCurrency, costCurrency, priceCurrency)
            
            if units == .missing, priceCurrency == nil {
                autoPostings.append(refer)
            } else {
                if let currency = getBucketCurrency(refer: refer) {
                    sortDict.putIfAbsent(key: currency, value: index)
                    groups[currency, default: []].append(refer)
                } else {
                    unknown.append(refer)
                }
            }
        }
        
        // We look at the remaining postings... if they are all of a single currency,
        // the posting must be in that currency too.
        if unknown.count == 1 && groups.count == 1 {
            var (index, unitsCurrency, costCurrency, priceCurrency) = unknown.popLast()!
            let otherCurrency = groups.keys.first!
            if priceCurrency == nil && costCurrency == nil {
                unitsCurrency = otherCurrency
            } else {
                if priceCurrency == .missing {
                    priceCurrency = otherCurrency
                }
                if costCurrency == .missing {
                    costCurrency = otherCurrency
                }
            }
            
            let refer: Refer = (index, unitsCurrency, costCurrency, priceCurrency)
            let currency = getBucketCurrency(refer: refer)!
            sortDict.putIfAbsent(key: currency, value: index)
            groups[currency, default: []].append(refer)
        }
        
        
        // Finally, try to resolve all the unknown legs using the inventory contents
        // of each account.
        for refer in unknown {
            var (index, unitsCurrency, costCurrency, priceCurrency) = refer
            let posting = transaction.postings[index]
            let balance = balances[posting.account, default: Inventory()]
            
            if unitsCurrency == .missing {
                let balanceCurrencies = balance.currencies
                if balanceCurrencies.count == 1 {
                    unitsCurrency = balanceCurrencies.first
                }
            }
            
            if costCurrency == .missing || priceCurrency == .missing {
                let balanceCostCurrencies = balance.costCurrencies
                if balanceCostCurrencies.count == 1 {
                    let balanceCostCurrency = balanceCostCurrencies.first
                    if priceCurrency == .missing {
                        priceCurrency = balanceCostCurrency
                    }
                    if costCurrency == .missing {
                        costCurrency = balanceCostCurrency
                    }
                }
            }
            
            let refer: Refer = (index, unitsCurrency, costCurrency, priceCurrency)
            if let currency = getBucketCurrency(refer: refer) {
                sortDict.putIfAbsent(key: currency, value: index)
                groups[currency, default: []].append(refer)
            } else {
                errors.append(CategorizationError.failedToCategorize(txn: transaction, index: index))
            }
        }
        
        // Fill in missing units currencies if some remain as missing. This may occur
        // if we used the cost or price to bucket the currency but the units currency
        // was missing.
        for (currency, refers) in groups {
            for (rindex, refer) in refers.enumerated() {
                if refer.unitsCurrency == .missing {
                    let posting = transaction.postings[refer.index]
                    guard let balance = balances[posting.account] else {
                        continue
                    }
                    let balanceCurrencies = balance.currencies
                    if balanceCurrencies.count == 1 {
                        groups[currency]![rindex] = (refer.index,
                                                     balanceCurrencies.first,
                                                     refer.costCurrency,
                                                     refer.priceCurrency)
                    }
                }
            }
        }
        
        if autoPostings.count > 1 {
            errors.append(CategorizationError.extraAutoPostings(txn: transaction))
            autoPostings.removeSubrange(1...)
        }
        
        for refer in autoPostings {
            for currency in groups.keys {
                sortDict.putIfAbsent(key: currency, value: refer.index)
                groups[currency]!.append((refer.index, currency, nil, nil))
            }
        }
        
        for refers in groups.values {
            for refer in refers {
                for (currency, name) in [
                    (refer.unitsCurrency, "units"),
                    (refer.costCurrency, "cost"),
                    (refer.priceCurrency, "price")
                ] {
                    if currency == .missing {
                        errors.append(CategorizationError.cannotResolve(txn: transaction, name: name))
                    }
                }
            }
        }
        
        let sortedGroups = groups.sorted { lhs, rhs in
            return sortDict[lhs.key, default: 0] < sortDict[rhs.key, default: 0]
        }
        return (sortedGroups, errors)
    }
    
    func replaceCurrencies(postings: [Posting<CostSpec>], referGroups: [(Currency, [Refer])]) -> [(Currency, [Posting<CostSpec>])] {
        var newGroups = [(Currency, [Posting<CostSpec>])]()
        for (currency, refers) in referGroups {
            var newPostings = [Posting<CostSpec>]()
            for refer in refers.sorted(by: { $0.index < $1.index }) {
                var posting = postings[refer.index]
                var units = posting.units
                if units == .missing  {
                    posting.units = Amount(number: .nan, currency: refer.unitsCurrency ?? .missing)
                } else {
                    var replace = false
                    var cost = posting.cost
                    var price = posting.price
                    if units.currency == .missing {
                        units = Amount(number: units.number, currency: refer.unitsCurrency ?? .missing)
                        replace = true
                    }
                    if cost?.currency == .missing {
                        cost?.currency = refer.costCurrency
                        replace = true
                    }
                    if price?.currency == .missing {
                        price = Amount(number: price?.number ?? .nan, currency: refer.priceCurrency ?? .missing)
                        replace = true
                    }
                    if replace {
                        posting.units = units
                        posting.cost = cost
                        posting.price = price
                    }
                }
                newPostings.append(posting)
            }
            newGroups.append((currency, newPostings))
        }
        return newGroups
    }
    
    enum BookedPosting {
        case incomplete(Posting<CostSpec>)
        case complete(Posting<Cost>)
    }
    
    func bookReductions(entry: Directive<CostSpec>,
                        groupPostings: [Posting<CostSpec>],
                        balances: [Account: Inventory],
                        methods: BookingMethodStore) ->
    ([BookedPosting], [Error]) {
        var errors = [Error]()
        var localBalances = [Account: Inventory]()
        
        let empty = Inventory()
        var bookedPostings = [BookedPosting]()
        
        for posting in groupPostings {
            let units = posting.units
            let costSpec = posting.cost
            let account = posting.account
            
            if !localBalances.keys.contains(account) {
                let previousBalance = balances[account, default: empty]
                localBalances[account] = previousBalance.copy() as? Inventory
            }
            let balance = localBalances[account]
            
            guard let costSpec, units.number != .nan else {
                bookedPostings.append(.incomplete(posting))
                continue
            }
            
            let method = methods[account]
            if method != .NONE, let balance, balance.isReducedBy(units) {
                let costNumber = costSpec.computeCostNumber(by: units)
                var matches = [Position]()
                for position in balance.positions {
                    if position.units.currency != units.currency {
                        continue
                    }
                    if position.cost == nil {
                        continue
                    }
                    if costNumber != nil && position.cost?.number != costNumber {
                        continue
                    }
                    if costSpec.currency != .missing, position.cost?.currency != costSpec.currency {
                        continue
                    }
                    if costSpec.date != nil && position.cost?.date != costSpec.date {
                        continue
                    }
                    if costSpec.label != nil && position.cost?.label != costSpec.label {
                        continue
                    }
                    matches.append(position)
                }
                if matches.isEmpty {
                    errors.append(BookingError.reduction(entry))
                    return ([], errors)
                }
                
                let (reductionPostings, _, ambiErrors) = handleAmbiguousMatches(entry: entry, posting: posting, matches: matches, method: method)
                if !ambiErrors.isEmpty {
                    errors += ambiErrors
                    return ([], errors)
                }
                
                bookedPostings.append(contentsOf: reductionPostings.map({ .complete($0) }))
                
                for posting in reductionPostings {
                    balance.addPosition(.init(posting: posting))
                }
            } else {
                var posting = posting
                if costSpec.date == nil {
                    var datedCostSpec = costSpec
                    datedCostSpec.date = entry.date
                    posting.cost = datedCostSpec
                }
                bookedPostings.append(.incomplete(posting))
            }
        }
        return (bookedPostings, errors)
    }
    
    func interpolateGroup(postings: [BookedPosting], currency: Currency, tolerances: Interpolate.ToleranceMapping) -> ([Posting<Cost>], [Error]) {
        fatalError()
    }
}



extension CostSpec {
    func computeCostNumber(by units: Amount) -> Decimal? {
        guard numberPerUnit != .nan, numberTotal != .nan else {
            return nil
        }
        if let numberTotal {
            var costTotal = numberTotal
            let unitsNumber = abs(units.number)
            if let numberPerUnit {
                costTotal += numberPerUnit * unitsNumber
            }
            return costTotal / unitsNumber
        } else {
            return numberPerUnit
        }
    }
}

extension Posting<CostSpec> {
    func resolvingCost() -> Posting<Cost> {
        guard let cost else {
            return .init(account: account,
                         units: units,
                         cost: nil,
                         price: price,
                         flag: flag,
                         meta: meta,
                         comment: comment)
        }
        let numberPerUnit = cost.numberPerUnit
        let numberTotal = cost.numberTotal
        let unitCost: Decimal
        if let numberTotal {
            let unitsNumber = abs(units.number)
            var costTotal = numberTotal
            if let numberPerUnit, numberPerUnit != .nan {
                costTotal += numberPerUnit * unitsNumber
            }
            unitCost = costTotal / unitsNumber
        } else {
            unitCost = numberPerUnit!
        }
        return .init(
            account: account,
            units: units,
            cost: .init(
                number: unitCost,
                currency: cost.currency!,
                date: cost.date!,
                label: cost.label
            ),
            price: price,
            flag: flag,
            meta: meta,
            comment: comment
        )
    }
}

