//
//  Interpolate.swift
//
//
//  Created by Yeatse on 2023/12/25.
//

import Foundation

struct Interpolate {
    struct ToleranceMapping {
        let mapping: [Currency: Decimal]
        let `default`: Decimal
    }
    
    static let automaticResidual = "__residual__"
    static let automaticMeta = "__automatic__"
    
    func inferTolerances<T: PostingCost>(postings: [Posting<T>], options: [String: Option]) -> ToleranceMapping {
        return .init(mapping: [:], default: .zero)
    }
    
    func computeResidual(postings: [Booker.BookedPosting]) -> Inventory {
        let inventory = Inventory()
        for posting in postings {
            if let meta = posting.meta, meta[Interpolate.automaticResidual, default: .bool(false)] == .bool(true) {
                continue
            }
            let weight = switch posting {
            case .incomplete(let posting): posting.weight
            case .complete(let posting): posting.weight
            }
            inventory.addAmount(weight)
        }
        return inventory
    }
}
