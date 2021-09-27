//
//  RantInFeed.swift
//  RantInFeed
//
//  Created by Omer Shamai on 09/09/2021.
//

import Foundation

/// Holds shortened and summarized information about a specific rant. Used when the rant is contained in a feed.
public struct RantInFeed: Decodable, Identifiable {
    let uuid = UUID()
    
    /// The rant's ID.
    public let id: Int
    
    /// The rant's text content.
    let text: String
    
    /// The current score of the rant.
    var score: Int
    
    /// The Unix timestamp at which the rant was posted.
    let createdTime: Int
    
    /// If the rant has an image attached to it, the variable will contain information about it.
    let attachedImage: Rant.AttachedImage?
    
    /// The amount of comments for this rant.
    let commentCount: Int
    
    /// The tags this rant is listed under.
    let tags: [String]
    
    /// The current logged-in user's vote on the rant.
    /// * 1 = upvote
    /// * 0 = unvoted
    /// * -1 = downvote
    var voteState: Int
    
    /// Whether or not the rant was edited in the past.
    let isEdited: Bool
    
    /// A link to the rant.
    let link: String?
    
    /// If the rant is a collab, this will contain the type of the collab in short.
    /// * 1 = Open source idea
    /// * 2 = Existing open source project
    /// * 3 = Project idea
    /// * 4 = Existing project
    let collabType: Int?
    
    /// If the rant is a collab, this will contain the type of the collab as a full string.
    let collabTypeLong: String?
    
    /// The author's devRant user ID.
    let userID: Int
    
    /// The author's devRant username.
    let username: String
    
    /// The author's score on devRant.
    let userScore: Int
    
    /// The author's avatar, can be used optimally for small portraits of the user.
    let userAvatar: Rant.UserAvatar
    
    /// A larger version of the author's avatar, can be used optimally for profile screens.
    let userAvatarLarge: Rant.UserAvatar
    
    /// If the user is subscribed to devRant++, this property will be equal to `1`. If not, this property will either be `nil` or `0`.
    let isUserDPP: Int?
    
    enum CodingKeys: String, CodingKey {
        case id,
             text,
             score,
             createdTime = "created_time",
             attachedImage = "attached_image",
             commentCount = "num_comments",
             tags,
             voteState = "vote_state",
             isEdited = "edited",
             link,
             collabType = "c_type",
             collabTypeLong = "c_type_long",
             userID = "user_id",
             username = "user_username",
             userScore = "user_score",
             userAvatar = "user_avatar",
             userAvatarLarge = "user_avatar_lg",
             isUserDPP = "user_dpp"
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        score = try values.decode(Int.self, forKey: .score)
        createdTime = try values.decode(Int.self, forKey: .createdTime)
        
        do {
            attachedImage = try values.decode(Rant.AttachedImage.self, forKey: .attachedImage)
        } catch {
            attachedImage = nil
        }
        
        commentCount = try values.decode(Int.self, forKey: .commentCount)
        tags = try values.decode([String].self, forKey: .tags)
        voteState = try values.decode(Int.self, forKey: .voteState)
        isEdited = try values.decode(Bool.self, forKey: .isEdited)
        link = try? values.decode(String.self, forKey: .link)
        collabType = try? values.decode(Int.self, forKey: .collabType)
        collabTypeLong = try? values.decode(String.self, forKey: .collabTypeLong)
        userID = try values.decode(Int.self, forKey: .userID)
        username = try values.decode(String.self, forKey: .username)
        userScore = try values.decode(Int.self, forKey: .userScore)
        userAvatar = try values.decode(Rant.UserAvatar.self, forKey: .userAvatar)
        userAvatarLarge = try values.decode(Rant.UserAvatar.self, forKey: .userAvatarLarge)
        isUserDPP = try? values.decode(Int.self, forKey: .isUserDPP)
    }
}
