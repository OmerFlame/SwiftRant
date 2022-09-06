//
//  Weekly.swift
//  
//
//  Created by Omer Shamai on 06/09/2022.
//

import Foundation

/// A struct representing a list of Weekly Rant weeks.
public struct WeeklyList: Decodable {
    
    /// A struct representing the initial information for a since rant week.
    public struct Week: Decodable {
        
        /// The week number.
        public let week: Int
        
        /// The weekly subject.
        public let prompt: String
        
        /// The date the weekly rant was uploaded.
        public let date: String
        
        /// The amount of rants associated with the weekly rant.
        public let rantCount: Int
        
        enum CodingKeys: String, CodingKey {
            case week
            case prompt
            case date
            case rantCount = "num_rants"
        }
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<WeeklyList.Week.CodingKeys> = try decoder.container(keyedBy: WeeklyList.Week.CodingKeys.self)
            self.week = try container.decode(Int.self, forKey: WeeklyList.Week.CodingKeys.week)
            self.prompt = try container.decode(String.self, forKey: WeeklyList.Week.CodingKeys.prompt)
            self.date = try container.decode(String.self, forKey: WeeklyList.Week.CodingKeys.date)
            self.rantCount = try container.decode(Int.self, forKey: WeeklyList.Week.CodingKeys.rantCount)
        }
    }
    
    /// The list of weeks.
    public let weeks: [Week]
    
    enum CodingKeys: CodingKey {
        case weeks
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.weeks = try container.decode([WeeklyList.Week].self, forKey: .weeks)
    }
}

extension WeeklyList {
    public init(weeks: [WeeklyList.Week]) {
        self.weeks = weeks
    }
}

extension WeeklyList.Week {
    public init(week: Int, prompt: String, date: String, rantCount: Int) {
        self.week = week
        self.prompt = prompt
        self.date = date
        self.rantCount = rantCount
    }
}
