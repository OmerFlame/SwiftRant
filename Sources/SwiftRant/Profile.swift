//
//  Profile.swift
//  Profile
//
//  Created by Omer Shamai on 09/09/2021.
//

import Foundation

/// Holds information about a single user's profile.
public struct Profile: Decodable, Hashable {
    
    /// A structure that coalesces both the content itself and the amount of different types of content created by the user.
    public struct OuterUserContent: Decodable, Hashable {
        /// The user's content.
        public let content: InnerUserContent
        
        /// How much content of every type made by the user exists on devRant.
        public let counts: UserCounts
        
        public init(content: Profile.InnerUserContent, counts: Profile.UserCounts) {
            self.content = content
            self.counts = counts
        }
    }
    
    /// The actual content created by the user.
    public struct InnerUserContent: Decodable, Hashable {
        
        /// The rants the user created.
        public var rants: [RantInFeed]
        
        /// The rants the user upvoted.
        public var upvoted: [RantInFeed]
        
        /// The user's comments.
        public var comments: [Comment]
        
        /// The rants marked as favorite by the user.
        public var favorites: [RantInFeed]?
        
        /// If the user is the current logged-in user, you can obtain the list of rants the user has viewed in the past.
        public var viewed: [RantInFeed]?
        
        enum CodingKeys: String, CodingKey {
            case rants,
                 upvoted,
                 comments,
                 favorites,
                 viewed
        }
        
        public init(rants: [RantInFeed], upvoted: [RantInFeed], comments: [Comment], favorites: [RantInFeed]? = nil, viewed: [RantInFeed]? = nil) {
            self.rants = rants
            self.upvoted = upvoted
            self.comments = comments
            self.favorites = favorites
            self.viewed = viewed
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rants = try values.decode([RantInFeed].self, forKey: .rants)
            upvoted = try values.decode([RantInFeed].self, forKey: .upvoted)
            comments = try values.decode([Comment].self, forKey: .comments)
            
            do {
                favorites = try values.decode([RantInFeed].self, forKey: .favorites)
            } catch {
                favorites = nil
            }
            
            do {
                viewed = try values.decode([RantInFeed].self, forKey: .viewed)
            } catch {
                viewed = nil
            }
        }
    }
    
    /// A structure representing the amount of content the user has created for every single type of content.
    public struct UserCounts: Decodable, Hashable {
        
        /// The amount of rants the user has posted.
        public let rants: Int
        
        /// The amount of rants the user has upvoted.
        public let upvoted: Int
        
        /// The amount of comments the user has posted.
        public let comments: Int
        
        /// The amount of rants the user has marked as favorites.
        public let favorites: Int
        
        /// The amount of collabs the user has posted.
        public let collabs: Int
        
        enum CodingKeys: String, CodingKey {
            case rants,
                 upvoted,
                 comments,
                 favorites,
                 collabs
        }
        
        public init(rants: Int, upvoted: Int, comments: Int, favorites: Int, collabs: Int) {
            self.rants = rants
            self.upvoted = upvoted
            self.comments = comments
            self.favorites = favorites
            self.collabs = collabs
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rants = try values.decode(Int.self, forKey: .rants)
            upvoted = try values.decode(Int.self, forKey: .upvoted)
            comments = try values.decode(Int.self, forKey: .comments)
            favorites = try values.decode(Int.self, forKey: .favorites)
            collabs = try values.decode(Int.self, forKey: .collabs)
        }
    }
    
    /// An enumeration representing the different types of content that a user can create.
    public enum ProfileContentTypes: String {
        /// Represents all user content.
        case all = "all"
        
        /// Represents the user's rants.
        case rants = "rants"
        
        /// Represents content that the user upvoted.
        case upvoted = "upvoted"
        
        /// Represents the user's comments.
        case comments = "comments"
        
        /// Represents the user's favorite rants.
        case favorite = "favorites"
        
        /// Represents the rants the user has viewed.
        case viewed = "viewed"
    }
    
    /// The user's devRant username.
    public let username: String
    
    /// The user's total devRant score.
    public let score: Int
    
    /// The user's summary of himself, if specified.
    public let about: String
    
    /// The user's location, if specified.
    public let location: String
    
    /// The Unix timestamp at which the user registered to devRant.
    public let createdTime: Int
    
    /// The user's skills, if specified.
    public let skills: String
    
    /// The user's GitHub profile, if specified.
    public let github: String
    
    /// The user's personal website, if specified.
    public let website: String?
    
    /// The user's content and how much of it exists.
    public var content: OuterUserContent
    
    /// The user's large avatar, can be used optimally for profile screens.
    public let avatar: Rant.UserAvatar
    
    /// The user's small avatar, can be used optimally for small portraits of the user.
    public let avatarSmall: Rant.UserAvatar
    
    /// If the user is subscribed to devRant++, this property will be equal to `1`. If not, this property will either be `nil` or `0`.
    public let isUserDPP: Int?
    
    enum CodingKeys: String, CodingKey {
        case username,
             score,
             about,
             location,
             createdTime = "created_time",
             skills,
             github,
             website,
             content,
             avatar,
             avatarSmall = "avatar_sm",
             isUserDPP = "dpp"
    }
    
    public init(username: String, score: Int, about: String, location: String, createdTime: Int, skills: String, github: String, website: String?, content: Profile.OuterUserContent, avatar: Rant.UserAvatar, avatarSmall: Rant.UserAvatar, isUserDPP: Int?) {
        self.username = username
        self.score = score
        self.about = about
        self.location = location
        self.createdTime = createdTime
        self.skills = skills
        self.github = github
        self.website = website
        self.content = content
        self.avatar = avatar
        self.avatarSmall = avatarSmall
        self.isUserDPP = isUserDPP
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        username = try values.decode(String.self, forKey: .username)
        score = try values.decode(Int.self, forKey: .score)
        about = try values.decode(String.self, forKey: .about)
        location = try values.decode(String.self, forKey: .location)
        createdTime = try values.decode(Int.self, forKey: .createdTime)
        skills = try values.decode(String.self, forKey: .skills)
        github = try values.decode(String.self, forKey: .github)
        website = try? values.decode(String.self, forKey: .website)
        content = try values.decode(OuterUserContent.self, forKey: .content)
        avatar = try values.decode(Rant.UserAvatar.self, forKey: .avatar)
        avatarSmall = try values.decode(Rant.UserAvatar.self, forKey: .avatarSmall)
        isUserDPP = try? values.decode(Int.self, forKey: .isUserDPP)
    }
}
