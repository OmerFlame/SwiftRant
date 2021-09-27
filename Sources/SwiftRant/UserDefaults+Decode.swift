//
//  File.swift
//  File
//
//  Created by Omer Shamai on 19/09/2021.
//

import Foundation

extension UserDefaults {
    
    /// Decodes a class stored in User Defaults.
    ///
    /// - parameter forKey: The name of one of the receiver's properties.
    /// - returns: The object for the property identified by `key`.
    public func decode<T: Decodable>(forKey: String) -> T? {
        if let object = object(forKey: forKey) as? Data {
            let decoder = JSONDecoder()
            
            if let decodedObject = try? decoder.decode(T.self, from: object) {
                return decodedObject
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    public func encodeAndSet<T: Encodable>(_ value: T?, forKey: String) {
        let encoder = JSONEncoder()
        
        guard value != nil else {
            set(nil, forKey: forKey)
            return
        }
        
        if let encoded = try? encoder.encode(value) {
            set(encoded, forKey: forKey)
        }
    }
}
