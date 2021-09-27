//
//  NotificationFeed.swift
//  NotificationFeed
//
//  Created by Omer Shamai on 13/09/2021.
//

import Foundation

struct NotificationFeed: Decodable {
    public let data: Notifications
}

/// A model representing the notification data.
public struct Notifications: Decodable {
    
    /// An enumeration representing all different categories of notifications.
    public enum Categories: String {
        case all
        case upvotes
        case mentions
        case comments
        case subs
    }
    
    /// A model representing the amount of all types of unread notifications.
    public struct UnreadNotifications: Decodable {
        
        /// The total amount of unread notifications in the "all" category
        public let all: Int
        
        /// The total amount of unread commets.
        public let comments: Int
        
        /// The total amount of unread mentions.
        public let mentions: Int
        
        /// The total amount of unread rants from subscriptions.
        public let subs: Int
        
        /// Duplicate of ``all``.
        public let total: Int
        
        /// The total amount of unread upvotes.
        public let upvotes: Int
    }
    
    /// The server-side Unix timestamp at which the list of notifications were last checked.
    public let checkTime: Int
    
    /// The array of notifications that resulted from the request.
    public let items: [Notification]
    
    /// The amount of unread notifications, divided into notification types.
    public let unread: UnreadNotifications
    
    /// A username map that corresponds to every notification.
    public let usernameMap: UsernameMapArray?
    
    private enum CodingKeys: String, CodingKey {
        case checkTime = "check_time"
        case items
        case unread
        case usernameMap = "username_map"
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        checkTime = try values.decode(Int.self, forKey: .checkTime)
        
        items = try values.decodeIfPresent([Notification].self, forKey: .items) ?? []
        
        unread = try values.decode(UnreadNotifications.self, forKey: .unread)
        
        usernameMap = try? values.decode(UsernameMapArray.self, forKey: .usernameMap)
    }
}

/// A model representing a single notification.
public struct Notification: Decodable, Equatable {
    
    /// The comment's ID, if the notification is linked to a comment.
    public let commentID: Int?
    
    /// The Unix timestamp at which the notification was created.
    public let createdTime: Int
    
    /// The ID of the rant associated with the notification.
    public let rantID: Int
    
    /// If the user has already read the notification, this property will be equal to `1`. If not, this property will be equal to `0`.
    public var read: Int
    
    /// The type of the notification.
    public let type: NotificationType
    
    /// The ID of the user who triggered the notification.
    public let uid: Int
    
    private enum CodingKeys: String, CodingKey {
        case commentID = "comment_id"
        case createdTime = "created_time"
        case rantID = "rant_id"
        case read
        case type
        case uid
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        commentID = try values.decodeIfPresent(Int.self, forKey: .commentID)
        createdTime = try values.decode(Int.self, forKey: .createdTime)
        rantID = try values.decode(Int.self, forKey: .rantID)
        read = try values.decode(Int.self, forKey: .read)
        type = try values.decode(NotificationType.self, forKey: .type)
        uid = try values.decode(Int.self, forKey: .uid)
    }
    
    public static func == (lhs: Notification, rhs: Notification) -> Bool {
        return
            lhs.commentID == rhs.commentID &&
            lhs.createdTime == rhs.createdTime &&
            lhs.rantID == rhs.rantID &&
            lhs.read == rhs.read &&
            lhs.type == rhs.type &&
            lhs.uid == rhs.uid
    }
}

/// The types of a notification.
public enum NotificationType: String, Decodable {
    
    /// The type that describes an upvote on a rant.
    case rantUpvote = "content_vote"
    
    /// The type that describes an upvote on a comment.
    case commentUpvote = "comment_vote"
    
    /// The type that describes a comment on the user's rant.
    case commentContent = "comment_content"
    
    /// The type that describes a comment posted on a rant that the user has commented on.
    case commentDiscuss = "comment_discuss"
    
    /// The type that describes a mention of the user in a comment.
    case commentMention = "comment_mention"
    
    /// The type that describes a new rant posted by someone that the user is subscribed to.
    case rantSub = "rant_sub"
}
