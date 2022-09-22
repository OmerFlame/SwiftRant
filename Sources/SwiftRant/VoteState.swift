//
//  VoteState.swift
//  
//
//  Created by Wilhelm Oks on 21.09.22.
//

import Foundation

public enum VoteState: Int {
    /// Represents the state of a given ++ vote.
    case upvoted = 1
    
    /// Represents the state of no votes given.
    case unvoted = 0
    
    /// Represents the state of a given -- vote.
    case downvoted = -1
    
    /// Represents the state of not being able to vote.
    /// It can be unvotable if the rant or comment belongs to the logged in user.
    case unvotable = -2
}
