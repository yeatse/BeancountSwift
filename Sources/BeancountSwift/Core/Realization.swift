//
//  Realization.swift
//
//
//  Created by Yeatse on 2023/12/21.
//

/// A pair of a Posting and its parent Transaction. This is inserted as
/// temporaries in lists of postings-of-entries, which is the product of a
/// realization.
public struct TxnPosting {
    public let txn: Transaction<Cost>
    public let posting: Posting<Cost>
}
