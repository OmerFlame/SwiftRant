//
//  RantFeed.swift
//  RantFeed
//
//  Created by Omer Shamai on 13/09/2021.
//

import Foundation

/// Contains the contents of a devRant rant feed.
public struct RantFeed: Decodable, Hashable {
    
    /// Contains settings about notifications.
    public struct Settings: Codable, Hashable {
        
        /// Whether notifications are available.
        public let notificationState: String
        
        /// I have no idea what this is. This thing isn't documented.
        public let notificationToken: String?
        
        enum CodingKeys: String, CodingKey {
            case notificationState = "notif_state"
            case notificationToken = "notif_token"
        }
        
        public init(notificationState: String, notificationToken: String?) {
            self.notificationState = notificationState
            self.notificationToken = notificationToken
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            do {
                notificationState = try values.decode(String.self, forKey: .notificationState)
            } catch {
                // The notif_state can be the integer -1 instead of a string. Probably when the account's email has not been verified yet.
                notificationState = String(try values.decode(Int.self, forKey: .notificationState))
            }
            notificationToken = try? values.decode(String.self, forKey: .notificationToken)
        }
    }
    
    /// Contains the amount of unread notifications.
    public struct Unread: Decodable, Hashable {
        
        /// The total count of unread notifications.
        public let total: Int
        
        public init(total: Int) {
            self.total = total
        }
    }
    
    /// Contains information about news given in rant feeds.
    /// - note: This is mostly used for Weekly Group Rants.
    public struct News: Decodable, Hashable, Identifiable {
        
        /// The ID of the news.
        public let id: Int
        
        /// Most of the time this is equal to the value `intlink`, this specifies the type of news.
        public let type: String
        
        /// The headline of the news story.
        public let headline: String
        
        /// The contents of the news story.
        public let body: String?
        
        /// The footer of the news story.
        public let footer: String
        
        /// The expected height of the news story on the screen.
        public let height: Int
        
        /// The expected action that should take place when the news story is tapped/clicked on.
        public let action: RantFeedNewsAction
        
        enum CodingKeys: CodingKey {
            case id
            case type
            case headline
            case body
            case footer
            case height
            case action
        }
        
        public init(id: Int, type: String, headline: String, body: String?, footer: String, height: Int, action: RantFeed.RantFeedNewsAction) {
            self.id = id
            self.type = type
            self.headline = headline
            self.body = body
            self.footer = footer
            self.height = height
            self.action = action
        }
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<RantFeed.News.CodingKeys> = try decoder.container(keyedBy: RantFeed.News.CodingKeys.self)
            self.id = try container.decode(Int.self, forKey: RantFeed.News.CodingKeys.id)
            self.type = try container.decode(String.self, forKey: RantFeed.News.CodingKeys.type)
            self.headline = try container.decode(String.self, forKey: RantFeed.News.CodingKeys.headline)
            self.body = try container.decodeIfPresent(String.self, forKey: RantFeed.News.CodingKeys.body)
            self.footer = try container.decode(String.self, forKey: RantFeed.News.CodingKeys.footer)
            self.height = try container.decode(Int.self, forKey: RantFeed.News.CodingKeys.height)
            self.action = try container.decode(RantFeed.RantFeedNewsAction.self, forKey: RantFeed.News.CodingKeys.action)
        }
    }
    
    /// Has all cases of actions for tapping on a news heading in the rant feed.
    public enum RantFeedNewsAction: String, Decodable {
        case groupRant = "grouprant"
        case none = "none"
        case rant = "rant"
    }
    
    /// The rants in the feed.
    public var rants: [RantInFeed]
    
    /// The notification settings for the logged-in user.
    public let settings: Settings
    
    /// The feed's session hash.
    public let set: String?
    
    /// The Weekly Group Rant week number.
    public let weeklyRantWeek: Int?
    
    /// If the user is subscribed to devRant++, this property will be equal to `1`. If not, this property will either be equal to `0`.
    public let isUserDPP: Int
    
    /// The amount of unread notifications.
    /// - note: I have **no** idea why the developers of devRant duplicated this. It's a duplicate of ``Unread-swift.struct/total``.
    public let notifCount: Int?
    
    /// Contains the amount of unread notifications.
    public let unread: Unread?
    
    /// The current weekly news.
    public let news: News?
    
    private enum CodingKeys: String, CodingKey {
        case rants
        case settings
        case set
        case weeklyRantWeek = "wrw"
        case isUserDPP = "dpp"
        case notifCount = "num_notifs"
        case unread
        case news
    }
    
    public init(rants: [RantInFeed], settings: RantFeed.Settings, set: String?, weeklyRantWeek: Int?, isUserDPP: Int, notifCount: Int?, unread: RantFeed.Unread?, news: RantFeed.News?) {
        self.rants = rants
        self.settings = settings
        self.set = set
        self.weeklyRantWeek = weeklyRantWeek
        self.isUserDPP = isUserDPP
        self.notifCount = notifCount
        self.unread = unread
        self.news = news
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        rants = try values.decode([RantInFeed].self, forKey: .rants)
        settings = try values.decode(Settings.self, forKey: .settings)
        set = try values.decodeIfPresent(String.self, forKey: .set)
        weeklyRantWeek = try? values.decode(Int.self, forKey: .weeklyRantWeek)
        isUserDPP = try values.decodeIfPresent(Int.self, forKey: .isUserDPP) ?? 0
        notifCount = try values.decodeIfPresent(Int.self, forKey: .notifCount)
        unread = try values.decodeIfPresent(Unread.self, forKey: .unread)
        news = try values.decodeIfPresent(News.self, forKey: .news)
    }
}

//MARK: - sort & range

public extension RantFeed {
    enum Sort {
        /// The devRant algorithm decides what rants appear in the feed.
        case algorithm
        
        /// The most recent rants appear in the feed.
        case recent
        
        /// The top rated rants appear in the feed.
        case top(range: Range)
    }
    
    enum Range {
        /// Rants from the one day.
        case day
        
        /// Rants from the one week.
        case week
        
        /// Rants from the one month.
        case month
        
        /// Rants from all time.
        case all
    }
}
