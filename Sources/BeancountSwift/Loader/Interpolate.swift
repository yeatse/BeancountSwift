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
    
    func inferTolerances<T: PostingCost>(postings: [Posting<T>], options: [String: Option]) -> ToleranceMapping {
        return .init(mapping: [:], default: .zero)
    }
}
