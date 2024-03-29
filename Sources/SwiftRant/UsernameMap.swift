//
//  File.swift
//  File
//
//  Created by Omer Shamai on 13/09/2021.
//

import Foundation

public extension Notifications {
    
    /// A wrapper for an array holding a map of the usernames and their corresponding notifications.
    struct UsernameMapArray: Decodable, Hashable {
        
        /// A model representing a map of a username and its corresponding notification.
        public struct UsernameMap: Decodable, Hashable {
            
            /// The user's avatar.
            public let avatar: Rant.UserAvatar
            
            /// The user's username.
            public let name: String
            
            /// The user's ID.
            public let uidForUsername: String
            
            private enum CodingKeys: CodingKey {
                case avatar
                case name
            }
            
            public init(avatar: Rant.UserAvatar, name: String, uidForUsername: String) {
                self.avatar = avatar
                self.name = name
                self.uidForUsername = uidForUsername
            }
            
            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                
                avatar = try values.decode(Rant.UserAvatar.self, forKey: .avatar)
                name = try values.decode(String.self, forKey: .name)
                
                uidForUsername = values.codingPath[values.codingPath.endIndex - 1].stringValue
            }
        }
        
        /// The array holding the maps.
        public var array: [UsernameMap]
        
        private struct DynamicCodingKeys: CodingKey {
            var stringValue: String
            
            init?(stringValue: String) {
                self.stringValue = stringValue
            }
            
            var intValue: Int?
            
            init?(intValue: Int) {
                return nil
            }
        }
        
        public init(array: [Notifications.UsernameMapArray.UsernameMap]) {
            self.array = array
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: DynamicCodingKeys.self)
            
            var tempArray = [UsernameMap]()
            
            for key in values.allKeys {
                let decodedObject = try values.decode(UsernameMap.self, forKey: DynamicCodingKeys(stringValue: key.stringValue)!)
                tempArray.append(decodedObject)
            }
            
            array = tempArray
        }
    }
}
