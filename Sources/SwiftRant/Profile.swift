//
//  Profile.swift
//  Profile
//
//  Created by Omer Shamai on 09/09/2021.
//

import Foundation

/// Holds information about a single user's profile.
public struct Profile: Decodable {
    
    public struct OuterUserContent: Decodable {
        
        /// The user's content.
        let content: InnerUserContent
        
        /// How much content of every type made by the user exists on devRant.
        let counts: UserCounts
    }

    public struct InnerUserContent: Decodable {
        
        /// The rants the user created.
        var rants: [RantInFeed]
        
        /// The rants the user upvoted.
        var upvoted: [RantInFeed]
        
        /// The user's comments.
        var comments: [Comment]
        
        /// The rants marked as favorite by the user.
        var favorites: [RantInFeed]?
        
        /// If the user is the current logged-in user, you can obtain the list of rants the user has viewed in the past.
        var viewed: [RantInFeed]?
        
        enum CodingKeys: String, CodingKey {
            case rants,
                 upvoted,
                 comments,
                 favorites,
                 viewed
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

    public struct UserCounts: Decodable {
        
        /// The amount of rants the user has posted.
        let rants: Int
        
        /// The amount of rants the user has upvoted.
        let upvoted: Int
        
        /// The amount of comments the user has posted.
        let comments: Int
        
        /// The amount of rants the user has marked as favorites.
        let favorites: Int
        
        /// The amount of collabs the user has posted.
        let collabs: Int
        
        enum CodingKeys: String, CodingKey {
            case rants,
                 upvoted,
                 comments,
                 favorites,
                 collabs
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

    public enum ProfileContentTypes: String {
        case all = "all"
        case rants = "rants"
        case upvoted = "upvoted"
        case comments = "comments"
        case favorite = "favorites"
        case viewed = "viewed"
    }

    public struct ProfileResponse: Decodable {
        let success: Bool
        let profile: Profile
        
        enum CodingKeys: String, CodingKey {
            case success,
                 profile
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            success = try values.decode(Bool.self, forKey: .success)
            profile = try values.decode(Profile.self, forKey: .profile)
        }
    }

    
    /// The user's devRant username.
    let username: String
    
    /// The user's total devRant score.
    let score: Int
    
    /// The user's summary of himself, if specified.
    let about: String
    
    /// The user's location, if specified.
    let location: String
    
    /// The Unix timestamp at which the user registered to devRant.
    let createdTime: Int
    
    /// The user's skills, if specified.
    let skills: String
    
    /// The user's GitHub profile, if specified.
    let github: String
    
    /// The user's personal website, if specified.
    let website: String?
    
    /// The user's content and how much of it exists.
    var content: OuterUserContent
    
    /// The user's large avatar, can be used optimally for profile screens.
    let avatar: Rant.UserAvatar
    
    /// The user's small avatar, can be used optimally for small portraits of the user.
    let avatarSmall: Rant.UserAvatar
    
    /// If the user is subscribed to devRant++, this property will be equal to `1`. If not, this property will either be `nil` or `0`.
    let isUserDPP: Int?
    
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
