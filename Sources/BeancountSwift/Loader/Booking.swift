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
                let (referGroups, catErrors) = categorizeByCurrency(entry: directive, balances: balances)
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
                                                                         transaction: txn,
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
                    var balance = balances[posting.account, default: Inventory()]
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
    
    struct Refer {
        var index: Int
        var unitsCurrency: Currency?
        var costCurrency: Currency?
        var priceCurrency: Currency?
    }
    
    func getBucketCurrency(refer: Refer) -> Currency? {
        if let costCurrency = refer.costCurrency {
            return costCurrency
        }
        if let priceCurrency = refer.priceCurrency {
            return priceCurrency
        }
        return refer.unitsCurrency
    }
    
    struct PostingReference {
        let posting: Posting<CostSpec>
        let unitsCurrency: Currency?
        let costCurrency: Currency?
        let priceCurrency: Currency?
    }
    
    func categorizeByCurrency(entry: Directive<CostSpec>, balances: [Account: Inventory]) -> ([(Currency, Refer)], [Error]) {
        #if false
        var errors = [(Transaction, String)]() // To store errors with their associated transaction
        
        var groups = [Currency: [Refer]]()
        var sortDict = [Currency: Int]()
        var autoPostings = [Refer]()
        var unknown = [Refer]()
        
        for (index, posting) in entry.postings.enumerated() {
            let costCurrency = posting.cost.flatMap { spec in
                switch spec {
                    case .cost(let cost): cost.currency
                    case .costSpec(let costSpec): costSpec.currency
                }
            }
            var refer = Refer(
                index: index,
                unitsCurrency: posting.units.currency,
                costCurrency: costCurrency,
                priceCurrency: posting.price?.currency
            )
            if refer.costCurrency == nil && refer.priceCurrency != nil {
                refer.costCurrency = refer.priceCurrency
            }
            if refer.priceCurrency == nil && refer.costCurrency != nil {
                refer.priceCurrency = refer.costCurrency
            }
            
            if posting.units == .placeholder && refer.priceCurrency == nil {
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
            let unknownPosting = unknown.popLast()!
            let otherCurrency = groups.keys.first!
            
            var unitsCurrency = unknownPosting.unitsCurrency
            var costCurrency = unknownPosting.costCurrency
            var priceCurrency = unknownPosting.priceCurrency
            
            if priceCurrency == nil && costCurrency == nil {
                unitsCurrency = otherCurrency
            } else {
                priceCurrency = priceCurrency ?? otherCurrency
                costCurrency = costCurrency ?? otherCurrency
            }
            
            let refer = Refer(
                index: unknownPosting.index,
                unitsCurrency: unitsCurrency,
                costCurrency: costCurrency,
                priceCurrency: priceCurrency
            )
            let currency = getBucketCurrency(refer: refer)!
            sortDict.putIfAbsent(key: currency, value: refer.index)
            groups[currency, default: []].append(refer)
        }
        
        
        // Finally, try to resolve all the unknown legs using the inventory contents
        // of each account.
        for refer in unknown {
            var unitsCurrency = refer.unitsCurrency
            var costCurrency = refer.costCurrency
            var priceCurrency = refer.priceCurrency
            let posting = entry.postings[refer.index]
            
            let balance = balances[posting.account] ?? Inventory(positions: [])
            
            if unitsCurrency == nil {
                let balanceCurrencies = balance.currencies()
                if balanceCurrencies.count == 1 {
                    unitsCurrency = balanceCurrencies.first
                }
            }
            
            if costCurrency == nil || priceCurrency == nil {
                let balanceCostCurrencies = balance.costCurrencies()
                if balanceCostCurrencies.count == 1 {
                    let balanceCostCurrency = balanceCostCurrencies.first
                    priceCurrency = priceCurrency ?? balanceCostCurrency
                    costCurrency = costCurrency ?? balanceCostCurrency
                }
            }
            
            let inferredRefer = PostingReference(
                posting: posting,
                unitsCurrency: unitsCurrency,
                costCurrency: costCurrency,
                priceCurrency: priceCurrency
            )
            
            if let currency = getBucketCurrency(refer: inferredRefer) {
                categorizedPostings[currency, default: []].append(inferredRefer)
            } else {
                errors.append((entry, "Failed to categorize posting: \(posting)"))
            }
        }
        
        return categorizedPostings
        #endif
        fatalError()
    }
    
    func replaceCurrencies(postings: [Posting<CostSpec>], referGroups: [(Currency, Refer)]) -> [(Currency, [Posting<CostSpec>])] {
        fatalError()
    }
    
    func bookReductions(entry: Directive<CostSpec>,
                        transaction: Transaction<CostSpec>,
                        groupPostings: [Posting<CostSpec>],
                        balances: [Account: Inventory],
                        methods: BookingMethodStore) ->
    ([Posting<CostSpec>], [Error]) {
        #if false
        var errors = [Error]()
        var localBalances = [Account: Inventory]()
        
        var empty = Inventory()
        var bookedPostings = [Posting]()
        
        for posting in groupPostings {
            let units = posting.units
            let costSpec = posting.costSpec
            let account = posting.account
            
            if !localBalances.keys.contains(account) {
                localBalances[account] = balances[account, default: empty]
            }
            var balance = localBalances[account]
            
            guard let costSpec, units.number != .nan else {
                bookedPostings.append(posting)
                continue
            }
            
            let method = booking[account]
            if method != .NONE, var balance, balance.isReducedBy(units) {
                let costNumber = costSpec.computeCostNumber(by: units)
                var matches = [Position]()
                for position in balance.positions {
                    if units.currency != "" && position.units.currency != units.currency {
                        continue
                    }
                    if position.cost == nil {
                        continue
                    }
                    if costNumber != nil && position.cost?.number != costNumber {
                        continue
                    }
                    if costSpec.currency != nil && position.cost?.currency != costSpec.currency {
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
                
                let (reductionPostings, _, ambiErrors) = method.handleAmbiguousMatches(entry: entry, posting: posting, matches: matches)
                if !ambiErrors.isEmpty {
                    errors += ambiErrors
                    return ([], errors)
                }
                
                bookedPostings += reductionPostings
                
                for posting in reductionPostings {
                    balance.addPosition(.init(posting: posting))
                    localBalances[account] = balance
                }
            }
        }
        #endif
        fatalError()
    }
    
    func interpolateGroup(postings: [Posting<CostSpec>], currency: Currency, tolerances: Interpolate.ToleranceMapping) -> ([Posting<Cost>], [Error]) {
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

