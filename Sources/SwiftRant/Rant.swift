//
//  Rant.swift
//  Rant
//
//  Created by Omer Shamai on 09/09/2021.
//

import Foundation

/// Holds information about a single rant.
public struct Rant: Decodable, Identifiable, Hashable {
    
    /// Holds information about a specific weekly group rant.
    public struct Weekly: Decodable, Hashable {
        
        /// The date the weekly group rant was published.
        public let date: String
        
        /// The height of the weekly group rant's card.
        public let height: Int
        
        /// The topic of the weekly group rant.
        public let topic: String
        
        /// The week number for the weekly group rant.
        public let week: Int
        
        public init(date: String, height: Int, topic: String, week: Int) {
            self.date = date
            self.height = height
            self.topic = topic
            self.week = week
        }
    }

    /// Holds information about links inside rants and comments.
    public struct Link: Decodable, Hashable {
        
        /// The type of link.
        /// The types that exist are `url` and `mention`.
        public let type: String
        
        /// The parsed URL.
        public let url: String
        
        /// A shortened version of the parsed URL.
        public let shortURL: String?
        
        /// A way to represent the URL in a truncated way in the rant itself when it is presented to the user.
        public let title: String
        
        /// The starting position of the link.
        /// - Important: The devRant API returns offsets for links in byte offsets and not in normalized character offsets. Please take this into account when using these offsets.
        public let start: Int?
        
        /// The ending position of the link.
        /// - Important: The devRant API returns offsets for links in byte offsets and not in normalized character offsets. Please take this into account when using these offsets.
        public let end: Int?
        
        /// The calculated range from the `start` and `end` attributes.
        /// - Important: Please note that this is not a value that the server returns. This API library automatically calculates this when initializing the structs that use this struct as a property, such as `Rant` and `Comment`. A way to use this property could be:
        ///````
        ///var string = "This is a test string"
        ///var attributedString = NSMutableAttributedString(string: string)
        ///attributedString.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 18), range: link.calculatedRange)
        ///````
        public var calculatedRange: NSRange!
        
        enum CodingKeys: String, CodingKey {
            case type,
                 url,
                 shortURL = "short_url",
                 title,
                 start,
                 end
        }
        
        public init(type: String, url: String, shortURL: String?, title: String, start: Int?, end: Int?, calculatedRange: NSRange? = nil) {
            self.type = type
            self.url = url
            self.shortURL = shortURL
            self.title = title
            self.start = start
            self.end = end
            self.calculatedRange = calculatedRange
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            type = try values.decode(String.self, forKey: .type)
            
            do {
                url = try values.decode(String.self, forKey: .url)
            } catch {
                url = try String(values.decode(Int.self, forKey: .url))
            }
            
            //url = try values.decodeIfPresent(String.self, forKey: .url) ?? String(values.decode(Int.self, forKey: .url))
            shortURL = try values.decodeIfPresent(String.self, forKey: .shortURL)
            title = try values.decode(String.self, forKey: .title)
            start = try values.decodeIfPresent(Int.self, forKey: .start)
            end = try values.decodeIfPresent(Int.self, forKey: .end)
        }
    }

    /// Holds information about attached images in rants and comments.
    public struct AttachedImage: Decodable, Hashable {
        //let attached_image: String?
        
        /// The attached image's URL.
        public let url: String
        
        /// The attached image's width.
        public let width: Int
        
        /// The attached image's height.
        public let height: Int
        
        public init(url: String, width: Int, height: Int) {
            self.url = url
            self.width = width
            self.height = height
        }
    }

    /// Holds information about a user's avatar.
    public struct UserAvatar: Decodable, Equatable, Hashable {
        
        /// The user's background color, in hex.
        public let backgroundColor: String
        
        /// If the user has built an avatar, this will contain a jpeg image name of the avatar's image.
        /// You can append it to `https://avatars.devrant.com/` to get a URL that you can use to fetch the image.
        public let avatarImage: String?
        
        enum CodingKeys: String, CodingKey {
            case backgroundColor = "b",
                 avatarImage = "i"
        }
        
        public init(backgroundColor: String, avatarImage: String?) {
            self.backgroundColor = backgroundColor
            self.avatarImage = avatarImage
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            backgroundColor = try values.decode(String.self, forKey: .backgroundColor)
            avatarImage = try? values.decode(String.self, forKey: .avatarImage)
        }
    }
    
    /// If the rant is taking part in the weekly group rant, this variable will be populated with information regarding it.
    public let weekly: Weekly?
    
    /// The rant's ID.
    public let id: Int
    
    /// The contents of the rant.
    public let text: String
    
    /// The rant's score.
    public var score: Int
    
    /// The Unix timestamp at which the rant was created.
    public let createdTime: Int
    
    /// If the rant has an image attached to it, a URL of the image will be stored in this.
    public let attachedImage: AttachedImage?
    
    /// The amount of comments for this rant.
    public let commentCount: Int
    
    /// The tags the rant is listed under.
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
    
    /// Whether or not the rant's author has edited the rant in the past.
    public let isEdited: Bool
    
    /// Whether or not the current logged-in user has marked this rant as a favorite.
    public var isFavorite: Int?
    
    /// A link to the rant.
    public let link: String?
    
    /// If the rant includes URLs in the text, those that were successfully parsed by the server will be in this array.
    public var links: [Link]?
    
    /// If the rant is a collab, this will hold the type of the collab.
    public let collabTypeLong: String?
    
    /// If the rant is a collab, this will hold the description of the collab.
    public let collabDescription: String?
    
    /// If the rant is a collab, this will hold the required tech stack for joining the collab.
    public let collabTechStack: String?
    
    /// If the rant is a collab, this will hold the size of the team that works on the collab.
    public let collabTeamSize: String?
    
    /// If the rant is a collab, this will hold the official URL for the homepage of the collab.
    public let collabURL: String?
    
    /// The rant's author's ID.
    public let userID: Int
    
    /// The rant's author's username.
    public var username: String
    
    /// The rant's author's score on devRant.
    public let userScore: Int
    
    /// The author's avatar, can be used optimally for small portraits of the user.
    public let userAvatar: UserAvatar
    
    /// A larger version of the author's avatar, can be used optimally for profile screens.
    public let userAvatarLarge: UserAvatar
    
    /// If the user is subscribed to devRant++, this property will be equal to `1`. If not, this property will either be `nil` or `0`.
    public let isUserDPP: Int?
    
    enum CodingKeys: String, CodingKey {
        case id,
             text,
             score,
             createdTime = "created_time",
             attachedImage = "attached_image",
             commentCount = "num_comments",
             tags,
             voteState = "vote_state",
             weekly,
             isEdited = "edited",
             isFavorite = "favorited",
             link,
             links,
             collabTypeLong = "c_type_long",
             collabDescription = "c_description",
             collabTechStack = "c_tech_stack",
             collabTeamSize = "c_team_size",
             collabURL = "c_url",
             userID = "user_id",
             username = "user_username",
             userScore = "user_score",
             userAvatar = "user_avatar",
             userAvatarLarge = "user_avatar_lg",
             isUserDPP = "user_dpp"
    }
    
    /// An enumeration that represents the types of posts that exist.
    public enum RantType: Int {
        /// Represents a rant post type.
        case rant = 1
        
        /// Represents a collab post type.
        case collab = 2
        
        /// Represents a meme post type.
        case meme = 3
        
        /// Represents a question post type.
        case question = 4
        
        /// Represents a devRant-related post type.
        case devRant = 5
        
        /// Represents a random topic post type.
        case random = 6
        
        /// Represents an undefined post type (not available anymore in the official client).
        case undefined = 7
    }
    
    public init(weekly: Rant.Weekly?, id: Int, text: String, score: Int, createdTime: Int, attachedImage: Rant.AttachedImage?, commentCount: Int, tags: [String], voteState: VoteState, isEdited: Bool, isFavorite: Int? = nil, link: String?, links: [Rant.Link]? = nil, collabTypeLong: String?, collabDescription: String?, collabTechStack: String?, collabTeamSize: String?, collabURL: String?, userID: Int, username: String, userScore: Int, userAvatar: Rant.UserAvatar, userAvatarLarge: Rant.UserAvatar, isUserDPP: Int?) {
        self.weekly = weekly
        self.id = id
        self.text = text
        self.score = score
        self.createdTime = createdTime
        self.attachedImage = attachedImage
        self.commentCount = commentCount
        self.tags = tags
        self.voteStateRaw = voteState.rawValue
        self.isEdited = isEdited
        self.isFavorite = isFavorite
        self.link = link
        self.links = links
        self.collabTypeLong = collabTypeLong
        self.collabDescription = collabDescription
        self.collabTechStack = collabTechStack
        self.collabTeamSize = collabTeamSize
        self.collabURL = collabURL
        self.userID = userID
        self.username = username
        self.userScore = userScore
        self.userAvatar = userAvatar
        self.userAvatarLarge = userAvatarLarge
        self.isUserDPP = isUserDPP
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try values.decode(Int.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        score = try values.decode(Int.self, forKey: .score)
        createdTime = try values.decode(Int.self, forKey: .createdTime)
        
        do {
            attachedImage = try values.decode(AttachedImage.self, forKey: .attachedImage)
        } catch {
            attachedImage = nil
        }
        
        commentCount = try values.decode(Int.self, forKey: .commentCount)
        tags = try values.decode([String].self, forKey: .tags)
        voteStateRaw = try values.decode(Int.self, forKey: .voteState)
        weekly = try? values.decode(Weekly.self, forKey: .weekly)
        isEdited = try values.decode(Bool.self, forKey: .isEdited)
        isFavorite = try? values.decode(Int.self, forKey: .isFavorite)
        link = try? values.decode(String.self, forKey: .link)
        links = try? values.decode([Link].self, forKey: .links)
        
        collabTypeLong = try? values.decode(String.self, forKey: .collabTypeLong)
        collabDescription = try? values.decode(String.self, forKey: .collabDescription)
        collabTechStack = try? values.decode(String.self, forKey: .collabTechStack)
        collabTeamSize = try? values.decode(String.self, forKey: .collabTeamSize)
        collabURL = try? values.decode(String.self, forKey: .collabURL)
        
        userID = try values.decode(Int.self, forKey: .userID)
        username = try values.decode(String.self, forKey: .username)
        userScore = try values.decode(Int.self, forKey: .userScore)
        userAvatar = try values.decode(UserAvatar.self, forKey: .userAvatar)
        userAvatarLarge = try values.decode(UserAvatar.self, forKey: .userAvatarLarge)
        isUserDPP = try? values.decode(Int.self, forKey: .isUserDPP)
        
        if links != nil {
            let stringAsData = text.data(using: .utf8)!
            
            var temporaryStringBytes = Data()
            var temporaryGenericUseString = ""
            
            for i in 0..<(links!.count) {
                if links![i].start == nil && links![i].end == nil {
                    links![i].calculatedRange = (text as NSString).range(of: links![i].title)
                } else {
                    temporaryStringBytes = stringAsData[stringAsData.index(stringAsData.startIndex, offsetBy: links![i].start!)..<stringAsData.index(stringAsData.startIndex, offsetBy: links![i].end!)]
                    
                    temporaryGenericUseString = String(data: temporaryStringBytes, encoding: .utf8)!
                    
                    links![i].calculatedRange = (text as NSString).range(of: temporaryGenericUseString)
                }
            }
        }
    }
}
