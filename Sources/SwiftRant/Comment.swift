//
//  Comment.swift
//  Comment
//
//  Created by Omer Shamai on 09/09/2021.
//

import Foundation

/// Holds information about a single comment.
public struct Comment: Decodable, Identifiable, Hashable {
    public let uuid = UUID()
    
    /// The comment's ID.
    public let id: Int
    
    /// The rant ID that the comment is listed under.
    public let rantID: Int
    
    /// The text contents of the comment.
    public let body: String
    
    /// The score of the comment.
    public var score: Int
    
    /// The Unix timestamp at which the comment was posted.
    public let createdTime: Int
    
    public var voteStateRaw: Int
    
    /// The current logged-in user's vote on the comment.
    public var voteState: VoteState {
        get {
            return VoteState(rawValue: voteStateRaw) ?? .unvotable
        }
        set {
            voteStateRaw = newValue.rawValue
        }
    }
    
    /// If the comment includes URLs in the text, those that were successfully parsed by the server will be in this array.
    public var links: [Rant.Link]?
    
    /// The author's devRant user ID.
    public let userID: Int
    
    /// The author's devRant username.
    public let username: String
    
    /// The author's total score on devRant.
    public let userScore: Int
    
    /// The author's avatar.
    public let userAvatar: Rant.UserAvatar
    
    /// If the user is subscribed to devRant++, this property will be equal to `1`. If not, this property will either be `nil` or `0`.
    public let isUserDPP: Int?
    
    /// If the comment has an image attached to it, a URL of the image will be stored in this.
    public let attachedImage: Rant.AttachedImage?
    
    private enum CodingKeys: String, CodingKey {
        case id,
             rantID = "rant_id",
             body,
             score,
             createdTime = "created_time",
             voteStateRaw = "vote_state",
             links,
             userID = "user_id",
             username = "user_username",
             userScore = "user_score",
             userAvatar = "user_avatar",
             isUserDPP = "user_dpp",
             attachedImage = "attached_image"
    }
    
    public init(id: Int, rantID: Int, body: String, score: Int, createdTime: Int, voteState: VoteState, links: [Rant.Link]?, userID: Int, username: String, userScore: Int, userAvatar: Rant.UserAvatar, isUserDPP: Int?, attachedImage: Rant.AttachedImage?) {
        self.id = id
        self.rantID = rantID
        self.body = body
        self.score = score
        self.createdTime = createdTime
        self.voteStateRaw = voteState.rawValue
        self.links = links
        self.userID = userID
        self.username = username
        self.userScore = userScore
        self.userAvatar = userAvatar
        self.isUserDPP = isUserDPP
        self.attachedImage = attachedImage
    }
    
    public init(decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        rantID = try values.decode(Int.self, forKey: .rantID)
        body = try values.decode(String.self, forKey: .body)
        score = try values.decode(Int.self, forKey: .score)
        createdTime = try values.decode(Int.self, forKey: .createdTime)
        voteStateRaw = try values.decode(Int.self, forKey: .voteStateRaw)
        links = try? values.decodeIfPresent([Rant.Link].self, forKey: .links)
        userID = try values.decode(Int.self, forKey: .userID)
        username = try values.decode(String.self, forKey: .username)
        userScore = try values.decode(Int.self, forKey: .userScore)
        userAvatar = try values.decode(Rant.UserAvatar.self, forKey: .userAvatar)
        isUserDPP = try? values.decode(Int.self, forKey: .isUserDPP)
        attachedImage = try? values.decode(Rant.AttachedImage.self, forKey: .attachedImage)
        
        if links != nil {
            let stringAsData = body.data(using: .utf8)!
            
            var temporaryStringBytes = Data()
            var temporaryGenericUseString = ""
            
            for i in 0..<(links!.count) {
                debugPrint("DECODING LINK!")
                if links![i].start == nil && links![i].end == nil {
                    links![i].calculatedRange = (body as NSString).range(of: links![i].title)
                } else {
                    temporaryStringBytes = stringAsData[stringAsData.index(stringAsData.startIndex, offsetBy: links![i].start!)..<stringAsData.index(stringAsData.startIndex, offsetBy: links![i].end!)]
                    
                    temporaryGenericUseString = String(data: temporaryStringBytes, encoding: .utf8)!
                    
                    links![i].calculatedRange = (body as NSString).range(of: temporaryGenericUseString)
                }
            }
        }
    }
    
    public mutating func precalculateLinkRanges() {
        if links != nil {
            let stringAsData = body.data(using: .utf8)!
            
            var temporaryStringBytes = Data()
            var temporaryGenericUseString = ""
            
            for i in 0..<(links!.count) {
                debugPrint("DECODING LINK!")
                if links![i].start == nil && links![i].end == nil {
                    links![i].calculatedRange = (body as NSString).range(of: links![i].title)
                } else {
                    temporaryStringBytes = stringAsData[stringAsData.index(stringAsData.startIndex, offsetBy: links![i].start!)..<stringAsData.index(stringAsData.startIndex, offsetBy: links![i].end!)]
                    
                    temporaryGenericUseString = String(data: temporaryStringBytes, encoding: .utf8)!
                    
                    links![i].calculatedRange = (body as NSString).range(of: temporaryGenericUseString)
                }
            }
        }
    }
}
