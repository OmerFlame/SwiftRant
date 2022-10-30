//
//  File.swift
//  
//
//  Created by Omer Shamai on 15/02/2022.
//

import Foundation

struct JSONCodingKeys: CodingKey {
    var stringValue: String
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    var intValue: Int?
    
    init?(intValue: Int) {
        self.init(stringValue: "\(intValue)")
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: Dictionary<String, Any>.Type, forKey key: K) throws -> Dictionary<String, Any> {
        let container = try self.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        
        return try container.decode(type)
    }
    
    func decodeIfPresent(_ type: Dictionary<String, Any>.Type, forKey key: K) throws -> Dictionary<String, Any>? {
        guard contains(key) else {
            return nil
        }
        
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Array<Any>.Type, forKey key: K) throws -> Array<Any> {
        var container = try self.nestedUnkeyedContainer(forKey: key)
        return try container.decode(type)
    }
    
    func decodeIfPresent(_ type: Array<Any>.Type, forKey key: K) throws -> Array<Any>? {
        guard contains(key) else {
            return nil
        }
        
        return try decode(type, forKey: key)
    }
    
    func decode(_ type: Dictionary<String, Any>.Type) throws -> Dictionary<String, Any> {
        var dictionary = Dictionary<String, Any>()
        
        for key in allKeys {
            if let boolValue = try? decode(Bool.self, forKey: key) {
                dictionary[key.stringValue] = boolValue
            } else if let stringValue = try? decode(String.self, forKey: key) {
                dictionary[key.stringValue] = stringValue
            } else if let intValue = try? decode(Int.self, forKey: key) {
                dictionary[key.stringValue] = intValue
            } else if let doubleValue = try? decode(Double.self, forKey: key) {
                dictionary[key.stringValue] = doubleValue
            } else if let nestedDictionary = try? decode(Dictionary<String, Any>.self, forKey: key) {
                dictionary[key.stringValue] = nestedDictionary
            } else if let nestedArray = try? decode(Array<Any>.self, forKey: key) {
                dictionary[key.stringValue] = nestedArray
            }
        }
        
        return dictionary
    }
}

extension UnkeyedDecodingContainer {
    mutating func decode(_ type: Array<Any>.Type) throws -> Array<Any> {
        var array: [Any] = []
        while isAtEnd == false {
            if let value = try? decode(Bool.self) {
                array.append(value)
            } else if let value = try? decode(String.self) {
                array.append(value)
            } else if let nestedDictionary = try? decode(Dictionary<String, Any>.self) {
                array.append(nestedDictionary)
            } else if let nestedArray = try? decode(Array<Any>.self) {
                array.append(nestedArray)
            }
        }
        
        return array
    }
    
    mutating func decode(_ type: Dictionary<String, Any>.Type) throws -> Dictionary<String, Any> {
        let nestedContainer = try self.nestedContainer(keyedBy: JSONCodingKeys.self)
        return try nestedContainer.decode(type)
    }
}

/// A structure representing a single rant/post inside a Subscribed feed.
public struct RantInSubscribedFeed: Decodable, Hashable {
    
    /// A structure representing one action a specific user has performed on a post listed in a Subscribed feed.
    public struct RelatedUserAction: Decodable, Hashable {
        
        /// An enumeration listing the different types of actions the user could've performed on the post.
        public enum UserAction: String {
            
            /// Represents the action of liking the post.
            case liked
            
            /// Represents the action of posting the post.
            case posted
            
            /// Represents the action of commenting on the post.
            case commentedOn = "commented"
        }
        
        private enum CodingKeys: String, CodingKey {
            case userID = "uid"
            case action
        }
        
        /// The ID of the user that performed the action.
        public let userID: Int
        
        /// The action the user performed.
        public let action: UserAction
        
        public init(userID: Int, action: RantInSubscribedFeed.RelatedUserAction.UserAction) {
            self.userID = userID
            self.action = action
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: RantInSubscribedFeed.RelatedUserAction.CodingKeys.self)
            
            userID = Int(try values.decode(String.self, forKey: .userID))!
            action = RantInSubscribedFeed.RelatedUserAction.UserAction(rawValue: try values.decode(String.self, forKey: .action))!
        }
    }
    
    /// The rant's ID.
    public let id: Int
    
    /// The rant's text content.
    public let text: String
    
    /// The current score of the rant.
    public var score: Int
    
    /// The Unix timestamp at which the rant was posted.
    public let createdTime: Int
    
    /// If the rant has an image attached to it, the variable will contain information about it.
    public let attachedImage: Rant.AttachedImage?
    
    /// The amount of comments for this rant.
    public let commentCount: Int
    
    /// The tags this rant is listed under.
    public let tags: [String]
    
    public var voteStateRaw: Int
    
    /// The current logged-in user's vote on the rant.
    public var voteState: VoteState {
        get {
            return VoteState(rawValue: voteStateRaw) ?? .unvotable
        }
        set {
            voteStateRaw = newValue.rawValue
        }
    }
    
    /// Whether or not the rant was edited in the past.
    public let isEdited: Bool
    
    /// Actions other users have performed on this rant.
    public let relatedUserActions: [RelatedUserAction]
    
    private enum CodingKeys: String, CodingKey {
        case rant
        case actions
    }
    
    public init(id: Int, text: String, score: Int, createdTime: Int, attachedImage: Rant.AttachedImage?, commentCount: Int, tags: [String], voteState: VoteState, isEdited: Bool, relatedUserActions: [RantInSubscribedFeed.RelatedUserAction]) {
        self.id = id
        self.text = text
        self.score = score
        self.createdTime = createdTime
        self.attachedImage = attachedImage
        self.commentCount = commentCount
        self.tags = tags
        self.voteStateRaw = voteState.rawValue
        self.isEdited = isEdited
        self.relatedUserActions = relatedUserActions
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let rantInFeedProperties = try values.decode(Dictionary<String, Any>.self, forKey: .rant)
        
        id = rantInFeedProperties["id"]! as! Int
        text = rantInFeedProperties["text"]! as! String
        score = rantInFeedProperties["score"]! as! Int
        createdTime = rantInFeedProperties["created_time"]! as! Int
        
        if let attachedImageInProperties = rantInFeedProperties["attached_image"]! as? Dictionary<String, Any> {
            let dataFromAttachedImage = try JSONSerialization.data(withJSONObject: attachedImageInProperties, options: [])
            
            attachedImage = try JSONDecoder().decode(Rant.AttachedImage.self, from: dataFromAttachedImage)
        } else {
            attachedImage = nil
        }
        
        commentCount = rantInFeedProperties["num_comments"]! as! Int
        
        tags = rantInFeedProperties["tags"]! as! [String]
        
        voteStateRaw = rantInFeedProperties["vote_state"]! as! Int
        
        isEdited = rantInFeedProperties["edited"]! as! Bool
        
        relatedUserActions = try values.decode([RelatedUserAction].self, forKey: .actions)
    }
}
