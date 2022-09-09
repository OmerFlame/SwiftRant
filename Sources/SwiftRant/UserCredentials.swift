//
//  UserCredentials.swift
//  UserCredentials
//
//  Created by Omer Shamai on 13/09/2021.
//

import Foundation

/// A structure representing a user's credentials for accessing the devRant servers.
public struct UserCredentials: Codable, Equatable {
    
    /// A structure representing a user's auth token.
    public struct AuthToken: Codable {
        /// The user's token ID.
        public let tokenID: Int
        
        /// The user's token key.
        public let tokenKey: String
        
        /// The token's expire time.
        public let expireTime: Int
        
        /// The user's ID.
        public let userID: Int
        
        private enum CodingKeys: String, CodingKey {
            case tokenID = "id"
            case tokenKey = "key"
            case expireTime = "expire_time"
            case userID = "user_id"
        }
        
        public init(tokenID: Int, tokenKey: String, expireTime: Int, userID: Int) {
            self.tokenID = tokenID
            self.tokenKey = tokenKey
            self.expireTime = expireTime
            self.userID = userID
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            tokenID = try values.decode(Int.self, forKey: .tokenID)
            tokenKey = try values.decode(String.self, forKey: .tokenKey)
            expireTime = try values.decode(Int.self, forKey: .expireTime)
            userID = try values.decode(Int.self, forKey: .userID)
        }
        
        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            
            try values.encode(tokenID, forKey: .tokenID)
            try values.encode(tokenKey, forKey: .tokenKey)
            try values.encode(expireTime, forKey: .expireTime)
            try values.encode(userID, forKey: .userID)
        }
    }
    
    /// The user's auth token.
    public let authToken: AuthToken
    
    private enum CodingKeys: String, CodingKey {
        case authToken = "auth_token"
    }
    
    public init(authToken: UserCredentials.AuthToken) {
        self.authToken = authToken
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        authToken = try values.decode(AuthToken.self, forKey: .authToken)
    }
    
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        
        try values.encode(authToken, forKey: .authToken)
    }
    
    public static func == (lhs: UserCredentials, rhs: UserCredentials) -> Bool {
        return lhs.authToken.userID == rhs.authToken.userID &&
            lhs.authToken.tokenID == rhs.authToken.tokenID &&
            lhs.authToken.tokenKey == rhs.authToken.tokenKey &&
            lhs.authToken.expireTime == rhs.authToken.expireTime
    }
}
