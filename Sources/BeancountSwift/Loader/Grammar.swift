//
//  Grammar.swift
//
//
//  Created by Yeatse on 2023/12/23.
//

import Foundation
import SwiftTreeSitter

protocol Parsable {
    init(from node: SwiftTreeSitter.Node, content: String) throws
}

protocol AcceptingTagStack {
    func mergingTags(_ tags: [Tag]) -> Self
}

protocol AcceptingMetaStack {
    func mergingMetaData(_ meta: [String: MetaDataValue]) -> Self
}

private let quoteCharacterSet = CharacterSet(charactersIn: "\"")

enum SyntaxError: Error {
    case badNode(SwiftTreeSitter.Node)
}

extension String: Parsable {
    func trimmingQuotes() -> String {
        return trimmingCharacters(in: quoteCharacterSet)
    }

    init(from node: Node, content: String) throws {
        guard let range = Range(node.range, in: content) else {
            throw SyntaxError.badNode(node)
        }
        self = String(content[range])
    }
}

extension Character: Parsable {
    init(from node: Node, content: String) throws {
        if let first = try String(from: node, content: content).first {
            self = first
        } else {
            throw SyntaxError.badNode(node)
        }
    }
}

extension Date: Parsable {
    init(from node: Node, content: String) throws {
        if let date = Date.fromDateString(try String(from: node, content: content)) {
            self = date
        } else {
            throw SyntaxError.badNode(node)
        }
    }
}

extension Bool: Parsable {
    init(from node: Node, content: String) throws {
        self = try String(from: node, content: content) == "TRUE"
    }
}

extension Decimal: Parsable {
    init(from node: Node, content: String) throws {
        switch node.nodeType {
        case "number":
            let text = try String(from: node, content: content)
            guard let decimal = Decimal(string: text) else {
                throw SyntaxError.badNode(node)
            }
            self = decimal
        case "unary_number_expr":
            guard let sign = node.namedChild(at: 0),
                let val = node.namedChild(at: 1)
            else {
                throw SyntaxError.badNode(node)
            }
            let decimal = try Decimal(from: val, content: content)
            if sign.nodeType == "plus" {
                self = decimal
            } else {
                self = -decimal
            }
        case "binary_number_expr":
            guard let left = node.namedChild(at: 0),
                let oper = node.namedChild(at: 1),
                let right = node.namedChild(at: 2)
            else {
                throw SyntaxError.badNode(node)
            }
            let leftVal = try Decimal(from: left, content: content)
            let rightVal = try Decimal(from: right, content: content)
            switch oper.nodeType {
            case "plus":
                self = leftVal + rightVal
            case "minus":
                self = leftVal - rightVal
            case "asterisk":
                self = leftVal * rightVal
            case "slash":
                self = leftVal / rightVal
            default:
                throw SyntaxError.badNode(node)
            }
        default:
            throw SyntaxError.badNode(node)
        }
    }
}

extension Currency: Parsable {
    init(from node: Node, content: String) throws {
        self.init(id: try String(from: node, content: content))
    }
}

extension Account: Parsable {
    init(from node: Node, content: String) throws {
        self.init(id: try String(from: node, content: content))
    }
}

extension Amount: Parsable {
    init(from node: Node, content: String) throws {
        let number = try node.namedChild(at: 0).map { try Decimal(from: $0, content: content) }
        let currency = try node.namedChild(at: 1).map { try Currency(from: $0, content: content) }
        guard let number, let currency else { throw SyntaxError.badNode(node) }
        self.init(number: number, currency: currency)
    }
}

struct AmountTolerance {
    public let base: Decimal
    public let tolerance: Decimal
    public let currency: Currency
}

extension AmountTolerance: Parsable {
    init(from node: Node, content: String) throws {
        switch node.childCount {
        case 2:
            guard
                let numberNode = node.child(at: 0),
                let currency = node.child(at: 1)
            else {
                throw SyntaxError.badNode(node)
            }
            let number = try Decimal(from: numberNode, content: content)
            self.init(
                base: number,
                tolerance: number.leastSignificantDigit,
                currency: try Currency(from: currency, content: content)
            )
        case 4:
            guard
                let num = node.child(at: 0),
                let tol = node.child(at: 2),
                let currency = node.child(at: 3)
            else {
                throw SyntaxError.badNode(node)
            }
            self.init(
                base: try Decimal(from: num, content: content),
                tolerance: try Decimal(from: tol, content: content),
                currency: try Currency(from: currency, content: content)
            )
        default:
            throw SyntaxError.badNode(node)
        }
    }
}

struct CompoundAmount {
    let currency: Currency?
    let per: Decimal?
    let total: Decimal?
}

extension CompoundAmount: Parsable {
    init(from node: Node, content: String) throws {
        let currency = try node.child(byFieldName: "currency").map {
            try Currency(from: $0, content: content)
        }
        let per = try node.child(byFieldName: "per").map {
            try Decimal(from: $0, content: content)
        }
        let total = try node.child(byFieldName: "total").map {
            try Decimal(from: $0, content: content)
        }
        self.init(currency: currency, per: per, total: total)
    }
}

extension Node {
    func repeatedChildren(byFieldName: String, type: String) -> [Node] {
        var result: [Node] = []
        if let node = self.child(byFieldName: byFieldName) {
            result.append(node)
            var node = node
            while let next = node.nextNamedSibling, next.nodeType == type {
                result.append(next)
                node = next
            }
        }
        return result
    }

    func parseTagsAndLinks(in content: String) throws -> (tags: Set<Tag>, links: Set<String>) {
        var tags: Set<Tag> = []
        var links: Set<String> = []
        enumerateChildren { child in
            if child.isNamed {
                if child.nodeType == "link", let link = try? String(from: child, content: content) {
                    links.insert(link)
                } else if child.nodeType == "tag", let tag = try? Tag(from: child, content: content)
                {
                    tags.insert(tag)
                }
            }
        }
        return (tags, links)
    }
}

extension Tag: Parsable {
    init(from node: Node, content: String) throws {
        self.init(id: try String(from: node, content: content))
    }
}

extension MetaDataValue: Parsable {
    init(from node: Node, content: String) throws {
        self =
            switch node.nodeType {
            case "string": .string(try String(from: node, content: content).trimmingQuotes())
            case "account": .account(try Account(from: node, content: content))
            case "date": .date(try Date(from: node, content: content))
            case "currency": .currency(try Currency(from: node, content: content))
            case "tag": .tag(try Tag(from: node, content: content))
            case "bool": .bool(try Bool(from: node, content: content))
            case "amount": .amount(try Amount(from: node, content: content))
            case "number", "unary_number_expr", "binary_number_expr":
                .number(try Decimal(from: node, content: content))
            default: throw SyntaxError.badNode(node)
            }
    }
}

extension Directive<CostSpec>: Parsable {
    init(from node: Node, content: String) throws {
        let date = try node.child(byFieldName: "date").map { try Date(from: $0, content: content) }
        guard let date else { throw SyntaxError.badNode(node) }
        let comment = try node.child(byFieldName: "comment").map {
            try String(from: $0, content: content)
        }
        var meta: [String: MetaDataValue] = [
            "lineno": .number(Decimal(node.pointRange.lowerBound.row))
        ]
        var started = false
        for i in 0..<node.namedChildCount {
            if let child = node.namedChild(at: i), child.nodeType == "key_value" {
                started = true
                let key = child.namedChild(at: 0).flatMap {
                    try? String(from: $0, content: content)
                }
                let value = child.namedChild(at: 1)?.firstChild.flatMap {
                    try? MetaDataValue(from: $0, content: content)
                }
                if let key, let value { meta[key] = value }
            } else if started {
                break
            }
        }
        let content: DirectiveContent<CostSpec> =
            switch node.nodeType {
            case "balance": .balance(try Balance(from: node, content: content))
            case "close": .close(try Close(from: node, content: content))
            case "commodity": .commodity(try Commodity(from: node, content: content))
            case "custom": .custom(try Custom(from: node, content: content))
            case "document": .document(try Document(from: node, content: content))
            case "event": .event(try Event(from: node, content: content))
            case "note": .note(try Note(from: node, content: content))
            case "open": .open(try Open(from: node, content: content))
            case "pad": .pad(try Pad(from: node, content: content))
            case "price": .price(try Price(from: node, content: content))
            case "query": .query(try Query(from: node, content: content))
            case "transaction": .transaction(try Transaction(from: node, content: content))
            default: throw SyntaxError.badNode(node)
            }
        self.init(meta: meta, date: date, comment: comment, content: content)
    }
}

extension Directive: AcceptingTagStack, AcceptingMetaStack {
    func mergingTags(_ tags: [Tag]) -> Self {
        var result = self
        switch result.content {
        case .transaction(let transaction):
            result.content = .transaction(transaction.mergingTags(tags))
        case .document(let document):
            result.content = .document(document.mergingTags(tags))
        default:
            break
        }
        return result
    }

    func mergingMetaData(_ meta: [String: MetaDataValue]) -> Directive {
        var result = self
        switch result.content {
        case .transaction(let transaction):
            result.content = .transaction(transaction.mergingMetaData(meta))
        default:
            break
        }
        result.meta = result.meta.merging(meta, uniquingKeysWith: { old, new in old })
        return result
    }
}

extension Balance: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let amount = try node.child(byFieldName: "amount").map {
            try AmountTolerance(from: $0, content: content)
        }
        guard let account, let amount else { throw SyntaxError.badNode(node) }
        self.init(
            account: account,
            amount: Amount(number: amount.base, currency: amount.currency),
            tolerance: amount.tolerance,
            diffAmount: nil
        )
    }
}

extension Open: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let currencies = try node.repeatedChildren(byFieldName: "currencies", type: "currency").map
        {
            try Currency(from: $0, content: content)
        }
        let booking = try node.child(byFieldName: "opt_booking")
            .flatMap { try String(from: $0, content: content) }
            .flatMap { Booking(rawValue: $0) }
        guard let account else { throw SyntaxError.badNode(node) }
        self.init(account: account, currencies: currencies, booking: booking)
    }
}

extension Close: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        guard let account else { throw SyntaxError.badNode(node) }
        self.init(account: account)
    }
}

extension Commodity: Parsable {
    init(from node: Node, content: String) throws {
        let currency = try node.child(byFieldName: "currency").map {
            try Currency(from: $0, content: content)
        }
        guard let currency else { throw SyntaxError.badNode(node) }
        self.init(currency: currency)
    }
}

extension Custom: Parsable {
    init(from node: Node, content: String) throws {
        let name = try node.child(byFieldName: "name").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let values = try node.repeatedChildren(
            byFieldName: "custom_value_list",
            type: "custom_value"
        )
        .compactMap { $0.firstChild }
        .map { try MetaDataValue(from: $0, content: content) }
        guard let name else { throw SyntaxError.badNode(node) }
        self.init(type: name, values: values)
    }
}

extension Document: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let filename = try node.child(byFieldName: "filename")?.firstChild.map {
            try String(from: $0, content: content)
        }
        guard let account, let filename else { throw SyntaxError.badNode(node) }
        if let tagsLinks = node.child(byFieldName: "tags_links") {
            let (tags, links) = try tagsLinks.parseTagsAndLinks(in: content)
            self.init(account: account, filename: filename, tags: tags, links: links)
        } else {
            self.init(account: account, filename: filename, tags: nil, links: nil)
        }
    }
}

extension Document: AcceptingTagStack {
    func mergingTags(_ tags: [Tag]) -> Document {
        return .init(
            account: account,
            filename: filename,
            tags: (self.tags ?? []).union(tags),
            links: links
        )
    }
}

extension Event: Parsable {
    init(from node: Node, content: String) throws {
        let desc = try node.child(byFieldName: "desc").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let type = try node.child(byFieldName: "type").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        guard let desc, let type else { throw SyntaxError.badNode(node) }
        self.init(type: type, description: desc)
    }
}

extension Transaction<CostSpec>: Parsable {
    init(from node: Node, content: String) throws {
        guard let txn = node.child(byFieldName: "txn") else { throw SyntaxError.badNode(node) }
        var postingStart = txn

        let narration = try node.child(byFieldName: "narration").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let payee = try node.child(byFieldName: "payee").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        var tags: Set<Tag> = []
        var links: Set<String> = []
        if let tagsLinks = node.child(byFieldName: "tags_links") {
            (tags, links) = try tagsLinks.parseTagsAndLinks(in: content)
            postingStart = tagsLinks
        }
        let flag = try? txn.firstChild.flatMap { try Character(from: $0, content: content) }

        var postings: [Posting<CostSpec>] = []

        var curr = postingStart
        while let next = curr.nextNamedSibling {
            curr = next
            switch curr.nodeType {
            case "posting":
                postings.append(try Posting(from: curr, content: content))
            case "tags_links":
                let (t, l) = try curr.parseTagsAndLinks(in: content)
                tags.formUnion(t)
                links.formUnion(l)
            case "key_value":
                let key = next.namedChild(at: 0).flatMap { try? String(from: $0, content: content) }
                let value = next.namedChild(at: 1)?.firstChild.flatMap {
                    try? MetaDataValue(from: $0, content: content)
                }
                if let key, let value, let last = postings.last {
                    postings[postings.endIndex - 1] = last.mergingMetaData([key: value])
                }
            default:
                break
            }
        }
        self.init(
            flag: flag,
            payee: payee,
            narration: narration,
            tags: tags,
            links: links,
            postings: postings
        )
    }
}

extension Transaction: AcceptingTagStack, AcceptingMetaStack {
    func mergingTags(_ tags: [Tag]) -> Transaction {
        return .init(
            flag: flag,
            payee: payee,
            narration: narration,
            tags: self.tags.union(tags),
            links: links,
            postings: postings
        )
    }

    func mergingMetaData(_ meta: [String: MetaDataValue]) -> Transaction {
        return .init(
            flag: flag,
            payee: payee,
            narration: narration,
            tags: tags,
            links: links,
            postings: postings.map { $0.mergingMetaData(meta) }
        )
    }
}

extension CostSpec: Parsable {
    init(from node: Node, content: String) throws {
        let costComp = node.repeatedChildren(byFieldName: "cost_comp_list", type: "cost_comp")
            .compactMap { $0.firstChild }
        var amount: CompoundAmount?
        var date: Date?
        var label: String?
        for comp in costComp {
            switch comp.nodeType {
            case "compound_amount":
                amount = try CompoundAmount(from: comp, content: content)
            case "date":
                date = try Date(from: comp, content: content)
            case "string":
                label = try String(from: comp, content: content).trimmingQuotes()
            default:
                break
            }
        }
        self.init(
            numberPerUnit: amount?.per,
            numberTotal: amount?.total,
            currency: amount?.currency,
            date: date,
            label: label,
            merge: nil
        )
    }
}

extension Posting<CostSpec>: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let amount = try node.child(byFieldName: "amount").map {
            try Amount(from: $0, content: content)
        }
        let comment = try node.child(byFieldName: "comment").map {
            try String(from: $0, content: content)
        }
        let flag = try node.child(byFieldName: "optflag")?.namedChild(at: 0).map {
            try Character(from: $0, content: content)
        }
        let costSpec = try node.child(byFieldName: "cost_spec")
            .map { try CostSpec(from: $0, content: content) }
        let priceAnnotation = try node.child(byFieldName: "price_annotation")?.namedChild(at: 0).map
        {
            try Amount(from: $0, content: content)
        }

        guard let account else { throw SyntaxError.badNode(node) }
        let meta: [String: MetaDataValue] = [
            "lineno": .number(Decimal(node.pointRange.lowerBound.row))
        ]
        self.init(
            account: account,
            units: amount ?? .missing,
            cost: costSpec,
            price: priceAnnotation,
            flag: flag,
            meta: meta,
            comment: comment
        )
    }
}

extension Posting: AcceptingMetaStack {
    func mergingMetaData(_ meta: [String: MetaDataValue]) -> Posting {
        return .init(
            account: account,
            units: units,
            cost: cost,
            price: price,
            flag: flag,
            meta: (self.meta ?? [:]).merging(meta, uniquingKeysWith: { old, new in old }),
            comment: comment
        )
    }
}

extension Pad: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let fromAccount = try node.child(byFieldName: "from_account").map {
            try Account(from: $0, content: content)
        }
        guard let account, let fromAccount else { throw SyntaxError.badNode(node) }
        self.init(account: account, sourceAccount: fromAccount)
    }
}

extension Price: Parsable {
    init(from node: Node, content: String) throws {
        let amount = try node.child(byFieldName: "amount").map {
            try Amount(from: $0, content: content)
        }
        let currency = try node.child(byFieldName: "currency").map {
            try Currency(from: $0, content: content)
        }
        guard let amount, let currency else { throw SyntaxError.badNode(node) }
        self.init(currency: currency, amount: amount)
    }
}

extension Query: Parsable {
    init(from node: Node, content: String) throws {
        let name = try node.child(byFieldName: "name").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let query = try node.child(byFieldName: "query").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        guard let name, let query else { throw SyntaxError.badNode(node) }
        self.init(name: name, queryString: query)
    }
}

extension Option: Parsable {
    init(from node: Node, content: String) throws {
        let key = try node.child(byFieldName: "key").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let value = try node.child(byFieldName: "value").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        guard let key, let value else { throw SyntaxError.badNode(node) }
        self.init(key: key, value: value)
    }
}

extension Plugin: Parsable {
    init(from node: Node, content: String) throws {
        let name = try node.namedChild(at: 0).map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let config = try node.namedChild(at: 1).map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        guard let name else { throw SyntaxError.badNode(node) }
        self.init(name: name, config: config)
    }
}

extension Note: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let note = try node.child(byFieldName: "note").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        guard let account, let note else { throw SyntaxError.badNode(node) }
        self.init(account: account, note: note)
    }
}
