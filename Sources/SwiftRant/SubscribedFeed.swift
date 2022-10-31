//
//  SubscribedFeed.swift
//  
//
//  Created by Omer Shamai on 15/02/2022.
//

import Foundation

public struct SubscribedFeed: Decodable, Hashable {
    
    /// A structure representing information about the current page of the Subscribed feed.
    public struct PageInfo: Decodable, Hashable {
        /// A signature marking the end of the current page. Use this to get a fresh list of rants that weren't showcased in this feed.
        public let endCursor: String
        
        /// Whether or not the Subscribed feed for the user has more rants to show. Used for infinite scroll/pagination.
        public let hasNextPage: Bool
        
        private enum CodingKeys: String, CodingKey {
            case endCursor = "end_cursor"
            case hasNextPage = "has_next_page"
        }
        
        public init(endCursor: String, hasNextPage: Bool) {
            self.endCursor = endCursor
            self.hasNextPage = hasNextPage
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            endCursor = try values.decode(String.self, forKey: .endCursor)
            hasNextPage = try values.decode(Bool.self, forKey: .hasNextPage)
        }
    }
    
    /// A structure representing the list of users the devRant API thinks it can recommend to the user.
    public struct RecommendedUsers: Decodable, Hashable {
        
        /// The list of the IDs of the recommended users.
        public var users: [Int]
        
        /// Whether or not the Subscribed feed for the user has more users to recommend.
        /// - Note: The explanation for this property is unconfirmed. Do not rely on this variable until this note is gone from the documentation.
        public let hasNextPage: Bool
        
        private enum CodingKeys: String, CodingKey {
            case items
            case hasNextPage = "has_next_page"
        }
        
        public init(users: [Int], hasNextPage: Bool) {
            self.users = users
            self.hasNextPage = hasNextPage
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            let decodedItemsArray = try values.decode(Array<Any>.self, forKey: .items) as! Array<Dictionary<String, Int>>
            
            var tempUsers = [Int]()
            
            for item in decodedItemsArray {
                tempUsers.append(item["uid"]!)
            }
            
            users = tempUsers
            
            hasNextPage = try values.decode(Bool.self, forKey: .hasNextPage)
        }
    }
    
    /// A structure representing a wrapper for an array holding a map of the users showcased and recommended in this feed.
    /// - Warning: **This struct is incompatible with** ``Notifications/UsernameMapArray``**, because of different key names between the two responses.** This is not a limitation of this library, but a screw-up on devRant's side.
    public struct UsernameMap: Decodable, Hashable {
        
        /// A structure representing a single user in the username map.
        public struct User: Decodable, Hashable {
            public static func == (lhs: SubscribedFeed.UsernameMap.User, rhs: SubscribedFeed.UsernameMap.User) -> Bool {
                return lhs.username == rhs.username && lhs.avatar == rhs.avatar && lhs.score == rhs.score && lhs.userID == rhs.userID
            }
            
            /* The hash function should take into account all stored properties, not just the id.
             * Because it should be used to recognize changes in the object, not to identify the object.
            public func hash(into hasher: inout Hasher) {
                hasher.combine(userID)
            }
             */
            
            /// The user's username.
            public let username: String
            
            /// The user's avatar.
            public let avatar: Rant.UserAvatar
            
            /// The user's score.
            public var score: Int
            
            /// The user's ID.
            public let userID: Int
            
            private enum CodingKeys: String, CodingKey {
                case username
                case avatar
                case score
            }
            
            public init(username: String, avatar: Rant.UserAvatar, score: Int, userID: Int) {
                self.username = username
                self.avatar = avatar
                self.score = score
                self.userID = userID
            }
            
            public init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                
                username = try values.decode(String.self, forKey: .username)
                avatar = try values.decode(Rant.UserAvatar.self, forKey: .avatar)
                score = try values.decode(Int.self, forKey: .score)
                
                userID = Int(values.codingPath[values.codingPath.endIndex - 1].stringValue)!
            }
        }
        
        /// The array of the users.
        public var users: [User]
        
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
        
        public init(users: [SubscribedFeed.UsernameMap.User]) {
            self.users = users
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: DynamicCodingKeys.self)
            
            var tempArray = [User]()
            
            for key in values.allKeys {
                let decodedObject = try values.decode(User.self, forKey: DynamicCodingKeys(stringValue: key.stringValue)!)
                tempArray.append(decodedObject)
            }
            
            users = tempArray
        }
    }
    
    /// The rants in the feed.
    public var rants: [RantInSubscribedFeed]
    
    /// Pagination and infinite scroll-related information about this feed.
    public let pageInfo: PageInfo
    
    /// The list of users the devRant API thinks it can recommend to the user.
    public let recommendedUsers: RecommendedUsers
    
    /// A map of all users mentioned in the feed.
    public let usernameMap: UsernameMap
    
    private enum CodingKeys: String, CodingKey {
        case feed
    }
    
    public init(rants: [RantInSubscribedFeed], pageInfo: SubscribedFeed.PageInfo, recommendedUsers: SubscribedFeed.RecommendedUsers, usernameMap: SubscribedFeed.UsernameMap) {
        self.rants = rants
        self.pageInfo = pageInfo
        self.recommendedUsers = recommendedUsers
        self.usernameMap = usernameMap
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let feed = try values.decode(Dictionary<String, Any>.self, forKey: .feed)
        
        let rantDictArray = (feed["activity"]! as! Dictionary<String, Any>)["items"]! as! Array<Any>
        
        var tempRantArray = [RantInSubscribedFeed]()
        
        for dict in rantDictArray {
            let rantData = try JSONSerialization.data(withJSONObject: dict as! Dictionary<String, Any>, options: [])
            
            let rant = try JSONDecoder().decode(RantInSubscribedFeed.self, from: rantData)
            
            tempRantArray.append(rant)
        }
        
        rants = tempRantArray
        
        let pageInfoDict = (feed["activity"]! as! Dictionary<String, Any>)["page_info"]! as! Dictionary<String, Any>
        
        let pageInfoData = try JSONSerialization.data(withJSONObject: pageInfoDict, options: [])
        
        pageInfo = try JSONDecoder().decode(PageInfo.self, from: pageInfoData)
        
        let recommendedUsersDict = feed["rec_users"]! as! Dictionary<String, Any>
        
        let recommendedUsersData = try JSONSerialization.data(withJSONObject: recommendedUsersDict, options: [])
        
        recommendedUsers = try JSONDecoder().decode(RecommendedUsers.self, from: recommendedUsersData)
        
        let usernameMapDict = feed["users"]! as! Dictionary<String, Any>
        
        let usernameMapData = try JSONSerialization.data(withJSONObject: usernameMapDict, options: [])
        
        usernameMap = try JSONDecoder().decode(UsernameMap.self, from: usernameMapData)
    }
}
