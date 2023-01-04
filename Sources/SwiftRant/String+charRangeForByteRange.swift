//
//  String+charRangeForByteRange.swift
//  
//
//  Created by Omer Shamai on 04/01/2023.
//

import Foundation

extension String {
    func charRangeForByteRange(range: NSRange) -> NSRange {
        let bytes = [UInt8](utf8)
        
        var charOffset = 0
        
        for i in 0..<range.location {
            if (bytes[i] & 0xC0) != 0x80 {
                charOffset += 1
            }
        }
        
        let location = charOffset
        
        for i in range.location..<(range.location + range.length) {
            if (bytes[i] & 0xC0) != 0x80 {
                charOffset += 1
            }
        }
        
        let length = charOffset - location
        
        return NSRange(location: location, length: length)
    }
}
