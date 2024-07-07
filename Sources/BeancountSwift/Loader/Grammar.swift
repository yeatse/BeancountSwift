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
            case "paren_num_expr":
                guard let val = node.namedChild(at: 1) else {
                    throw SyntaxError.badNode(node)
                }
                self = try Decimal(from: val, content: content)
            case "unary_num_expr":
                guard let sign = node.child(at: 0), let val = node.child(at: 1) else {
                    throw SyntaxError.badNode(node)
                }
                let decimal = try Decimal(from: val, content: content)
                if sign.nodeType == "+" {
                    self = decimal
                } else {
                    self = -decimal
                }
            case "binary_num_expr":
                guard let left = node.child(at: 0), let oper = node.child(at: 1), let right = node.child(at: 2) else {
                    throw SyntaxError.badNode(node)
                }
                let leftVal = try Decimal(from: left, content: content)
                let rightVal = try Decimal(from: right, content: content)
                switch oper.nodeType {
                    case "+":
                        self = leftVal + rightVal
                    case "-":
                        self = leftVal - rightVal
                    case "*":
                        self = leftVal * rightVal
                    case "/":
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
        let number = try node.child(byFieldName: "number").map {
            try Decimal(from: $0, content: content)
        }
        let currency = try node.child(byFieldName: "currency").map {
            try Currency(from: $0, content: content)
        }
        self.init(number: number ?? .nan, currency: currency ?? .missing)
    }
}

struct AmountTolerance {
    let base: Decimal
    let tolerance: Decimal
    let currency: Currency
}

extension AmountTolerance: Parsable {
    init(from node: Node, content: String) throws {
        let number = try node.child(byFieldName: "number").map { try Decimal(from: $0, content: content) }
        let tolerance = try node.child(byFieldName: "tolerance").map { try Decimal(from: $0, content: content) }
        let currency = try node.child(byFieldName: "currency").map { try Currency(from: $0, content: content) }
        guard let number, let tolerance, let currency else {
            throw SyntaxError.badNode(node)
        }
        self.init(base: number, tolerance: tolerance, currency: currency)
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
        let per = try node.child(byFieldName: "number_per").map {
            try Decimal(from: $0, content: content)
        }
        let total = try node.child(byFieldName: "number_total").map {
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
                if child.nodeType == "link", let link = try? String(from: child, content: content), link.hasPrefix("^") {
                    links.insert(String(link.dropFirst()))
                } else if child.nodeType == "tag", let tag = try? Tag(from: child, content: content) {
                    tags.insert(tag)
                }
            }
        }
        return (tags, links)
    }
}

extension Tag: Parsable {
    init(from node: Node, content: String) throws {
        let tag = try String(from: node, content: content)
        guard tag.hasPrefix("#") else { throw SyntaxError.badNode(node) }
        self.init(id: String(tag.dropFirst()))
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
            case "number", "paren_num_expr", "unary_num_expr", "binary_num_expr":
                    .number(try Decimal(from: node, content: content))
            default: throw SyntaxError.badNode(node)
        }
    }
}

extension Dictionary {
    init(from node: Node, content: String) throws where Key == String, Value == MetaDataValue {
        var result: Self = [:]
        var child = node.namedChild(at: 0)
        while let keyValue = child {
            let key = try keyValue.child(byFieldName: "key").map { try String(from: $0, content: content).dropLast() }
            let value = try keyValue.child(byFieldName: "value").map { try MetaDataValue(from: $0, content: content) }
            guard let key else { throw SyntaxError.badNode(keyValue) }
            if let value {
                result[String(key)] = value
            }
            child = keyValue.nextNamedSibling
        }
        self = result
    }
}

extension Directive<CostSpec>: Parsable {
    init(from node: Node, content: String) throws {
        let date = try node.child(byFieldName: "date").map { try Date(from: $0, content: content) }
        guard let date else { throw SyntaxError.badNode(node) }
        var meta: MetaData = [
            "range": .range(node.tsRange)
        ]
        if let metadata = try node.child(byFieldName: "metadata").map({
            try Dictionary(from: $0, content: content)
        }) {
            meta.merge(metadata) { $1 }
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
        self.init(meta: meta, date: date, content: content)
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
        let amountNode = node.child(byFieldName: "amount")
        guard let account, let amountNode else { throw SyntaxError.badNode(node) }
        
        if amountNode.nodeType == "amount" {
            let amount = try Amount(from: amountNode, content: content)
            self.init(account: account, amount: amount, tolerance: nil, diffAmount: nil)
        } else {
            let amount = try AmountTolerance(from: amountNode, content: content)
            self.init(account: account,
                      amount: Amount(number: amount.base, currency: amount.currency),
                      tolerance: amount.tolerance,
                      diffAmount: nil)
        }
    }
}

extension Open: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let currencies = try node.repeatedChildren(byFieldName: "currencies", type: "currency").map {
            try Currency(from: $0, content: content)
        }
        let booking = try node.child(byFieldName: "booking")
            .flatMap { try String(from: $0, content: content).trimmingQuotes() }
            .flatMap { BookingMethod(rawValue: $0) }
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
        guard let nameNode = node.child(byFieldName: "name") else {
            throw SyntaxError.badNode(node)
        }
        let name = try String(from: nameNode, content: content).trimmingQuotes()
        var values: [MetaDataValue] = []
        var valueNode = nameNode.nextNamedSibling
        while let vn = valueNode, let value = try? MetaDataValue(from: vn, content: content) {
            values.append(value)
            valueNode = vn.nextNamedSibling
        }
        self.init(type: name, values: values)
    }
}

extension Document: Parsable {
    init(from node: Node, content: String) throws {
        let account = try node.child(byFieldName: "account").map {
            try Account(from: $0, content: content)
        }
        let filename = try node.child(byFieldName: "filename")?.firstChild.map {
            try String(from: $0, content: content).trimmingQuotes()
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
        let desc = try node.child(byFieldName: "description").map {
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
        let flag = try node.child(byFieldName: "flag").map {
            try Character(from: $0, content: content)
        }
        let payee = try node.child(byFieldName: "payee").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        let narration = try node.child(byFieldName: "narration").map {
            try String(from: $0, content: content).trimmingQuotes()
        }
        var tags: Set<Tag> = []
        var links: Set<String> = []
        if let tagsLinks = node.child(byFieldName: "tags_and_links") {
            (tags, links) = try tagsLinks.parseTagsAndLinks(in: content)
        }
        
        var postings: [Posting<CostSpec>] = []
        if let postingNodes = node.child(byFieldName: "postings") {
            for i in 0..<postingNodes.namedChildCount {
                guard let posting = postingNodes.namedChild(at: i), posting.nodeType == "posting" else {
                    continue
                }
                postings.append(try Posting(from: posting, content: content))
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
        var merge: Bool?
        var date: Date?
        var label: String?
        var amount: CompoundAmount?
        var costComp = node.child(byFieldName: "cost_comp_list")
        while let costCompNode = costComp {
            switch costCompNode.nodeType {
                case "merge":
                    merge = try String(from: costCompNode, content: content) == "*"
                case "date":
                    date = try Date(from: costCompNode, content: content)
                case "string":
                    label = try String(from: costCompNode, content: content).trimmingQuotes()
                case "compound_amount":
                    amount = try CompoundAmount(from: costCompNode, content: content)
                default:
                    throw SyntaxError.badNode(costCompNode)
            }
            costComp = costCompNode.nextNamedSibling
        }
        self.init(
            numberPerUnit: amount?.per,
            numberTotal: amount?.total,
            currency: amount?.currency,
            date: date,
            label: label,
            merge: merge
        )
    }
}

extension Posting<CostSpec>: Parsable {
    init(from node: Node, content: String) throws {
        let flag = try node.child(byFieldName: "flag").map {
            try Character(from: $0, content: content)
        }
        guard let accountNode = node.child(byFieldName: "account") else {
            throw SyntaxError.badNode(node)
        }
        let account = try Account(from: accountNode, content: content)
        let amount = try node.child(byFieldName: "amount").map {
            try Amount(from: $0, content: content)
        }
        let costSpec = try node.child(byFieldName: "cost_spec").map {
            try CostSpec(from: $0, content: content)
        }
        let priceAnnotation = try node.child(byFieldName: "price_annotation")?.namedChild(at: 0).map {
            try Amount(from: $0, content: content)
        }
        var meta: MetaData = [
            "lineno": .number(Decimal(accountNode.pointRange.lowerBound.row))
        ]
        if let metadata = try node.child(byFieldName: "metadata").map({
            try Dictionary(from: $0, content: content)
        }) {
            meta.merge(metadata) { $1 }
        }
        self.init(
            account: account,
            units: amount ?? .missing,
            cost: costSpec,
            price: priceAnnotation,
            flag: flag,
            meta: meta,
            comment: nil
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
