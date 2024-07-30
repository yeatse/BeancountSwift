import Foundation
import SwiftTreeSitter
import TreeSitterBeancount

public struct Beancount {
    public let loader = Loader()
    public let parser = Parser()
    public let realization = Realization()
    
    public init() {}
}
