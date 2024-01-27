import Foundation
import SwiftTreeSitter
import TreeSitterBeancount

public struct Beancount {
    public let loader = Loader()
    public let realization = Realization()
    
    public init() {}
}
