//
//  Item.swift
//  LocalLLM
//
//  Created by Chinh on 25/8/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
