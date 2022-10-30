//
//  AvatarCustomization.swift
//  AvatarCustomization
//
//  Created by Omer Shamai on 13/09/2021.
//

import Foundation

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif

/// A model representing the results of the customization query from the devRant servers.
public struct AvatarCustomizationResults: Decodable, Hashable {
    
    /// A class representing a customization image in the avatar editor.
    public class AvatarCustomizationImage: Decodable, Hashable, Equatable {
        //TODO: check if this class can be a struct. If yes, change it to struct and remove the explicit functions to conform to Hashable and Equatable, because they are synthesized automatically for structs.
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(backgroundColor)
            hasher.combine(fullImageName)
            hasher.combine(midImageName)
        }
        
        public static func == (lhs: AvatarCustomizationResults.AvatarCustomizationImage, rhs: AvatarCustomizationResults.AvatarCustomizationImage) -> Bool {
            return
                rhs.backgroundColor == lhs.backgroundColor &&
                rhs.fullImageName == lhs.fullImageName &&
                rhs.midImageName == lhs.midImageName
        }
        
        /// The background color in hexadecimal.
        public let backgroundColor: String
        
        /// The URL of the fully-featured image.
        public let fullImageName: String
        
        /// The URL of an image containing the preview of the customization option.
        public let midImageName: String
        
        private enum CodingKeys: String, CodingKey {
            case backgroundColor = "b"
            case fullImage = "full"
            case midCompleteImage = "mid"
        }
        
        public required init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            
            backgroundColor = try values.decode(String.self, forKey: .backgroundColor)
            midImageName = try values.decode(String.self, forKey: .midCompleteImage)
            fullImageName = try values.decode(String.self, forKey: .fullImage)
        }
        
        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(backgroundColor, forKey: .backgroundColor)
            try values.encode(fullImageName, forKey: .fullImage)
            try values.encode(midImageName, forKey: .midCompleteImage)
        }
        
        #if os(iOS) || targetEnvironment(macCatalyst)
        
        /// Get the fully-featured image.
        ///
        /// This method searches the app's document directory for a file that contains the image. If the method fails to find the image, it will download the image from the devRant servers and create a file that contains it. This action is an implementation of rudimentary image cache, as it is faster to copy a file's contents compared to fetching the same image from the internet every single time. However, setting the `shouldUseCache` parameter to `false` will prevent the method from searching for the image in the document directory.
        ///
        /// - Parameter shouldUseCache: whether or not the method should search for the image in the app's document directory.
        /// - Parameter completion: A method that takes the result image as a parameter.
        /// - returns: Nothing.
        public func getFullImage(shouldUseCache: Bool, completion: ((UIImage) -> (Void))?) {
            if shouldUseCache, let cachedFile = FileManager.default.contents(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fullImageName).relativePath) {
                completion?(UIImage(data: cachedFile)!)
            } else {
                let url = URL(string: "https://avatars.devrant.com/\(fullImageName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    if shouldUseCache {
                        FileManager.default.createFile(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(self.fullImageName).relativePath, contents: data!, attributes: nil)
                    }
                    
                    completion?(UIImage(data: data!)!)
                }.resume()
            }
        }
        
        /// Get the image containing a preview of the customization option.
        ///
        /// This method searches the app's document directory for a file that contains the image. If the method fails to find the image, it will download the image from the devRant servers and create a file that contains it. This action is an implementation of rudimentary image cache, as it is faster to copy a file's contents compared to fetching the same image from the internet every single time. However, setting the `shouldUseCache` parameter to `false` will prevent the method from searching for the image in the document directory.
        ///
        /// - Parameter shouldUseCache: whether or not the method should search for the image in the app's document directory.
        /// - Parameter completion: A method that takes the result image as a parameter.
        /// - returns: Nothing.
        public func getMidCompleteImage(shouldUseCache: Bool, completion: ((UIImage) -> (Void))?) {
            if shouldUseCache, let cachedFile = FileManager.default.contents(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(midImageName).relativePath) {
                completion?(UIImage(data: cachedFile)!)
            } else {
                let session = URLSession(configuration: .default)
                
                let url = URL(string: "https://avatars.devrant.com/\(midImageName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                session.dataTask(with: request) { data, _, _ in
                    if shouldUseCache {
                        FileManager.default.createFile(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(self.midImageName).relativePath, contents: data!, attributes: nil)
                    }
                    
                    completion?(UIImage(data: data!)!)
                }.resume()
            }
        }
        #else
        
        /// Get the fully-featured image.
        ///
        /// This method searches the app's document directory for a file that contains the image. If the method fails to find the image, it will download the image from the devRant servers and create a file that contains it. This action is an implementation of rudimentary image cache, as it is faster to copy a file's contents compared to fetching the same image from the internet every single time. However, setting the `shouldUseCache` parameter to `false` will prevent the method from searching for the image in the document directory.
        ///
        /// - Parameter shouldUseCache: whether or not the method should search for the image in the app's document directory.
        /// - Parameter completion: A method that takes the result image as a parameter.
        /// - returns: Nothing.
        public func getFullImage(shouldUseCache: Bool, completion: ((NSImage) -> (Void))?) {
            if shouldUseCache, let cachedFile = FileManager.default.contents(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fullImageName).relativePath) {
                completion?(NSImage(data: cachedFile)!)
            } else {
                let url = URL(string: "https://avatars.devrant.com/\(fullImageName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    if shouldUseCache {
                        FileManager.default.createFile(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(self.fullImageName).relativePath, contents: data!, attributes: nil)
                    }
                    
                    completion?(NSImage(data: data!)!)
                }.resume()
            }
        }
        
        /// Get the image containing a preview of the customization option.
        ///
        /// This method searches the app's document directory for a file that contains the image. If the method fails to find the image, it will download the image from the devRant servers and create a file that contains it. This action is an implementation of rudimentary image cache, as it is faster to copy a file's contents compared to fetching the same image from the internet every single time. However, setting the `shouldUseCache` parameter to `false` will prevent the method from searching for the image in the document directory.
        ///
        /// - Parameter shouldUseCache: whether or not the method should search for the image in the app's document directory.
        /// - Parameter completion: A method that takes the result image as a parameter.
        /// - returns: Nothing.
        func getMidCompleteImage(shouldUseCache: Bool, completion: ((NSImage) -> (Void))?) {
            if shouldUseCache, let cachedFile = FileManager.default.contents(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(midImageName).relativePath) {
                completion?(NSImage(data: cachedFile)!)
            } else {
                let session = URLSession(configuration: .default)
                
                let url = URL(string: "https://avatars.devrant.com/\(midImageName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                session.dataTask(with: request) { data, _, _ in
                    if shouldUseCache {
                        FileManager.default.createFile(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(self.midImageName).relativePath, contents: data!, attributes: nil)
                    }
                    
                    completion?(NSImage(data: data!)!)
                }.resume()
            }
        }
        #endif
    }
    
    /// A model representing the current info about the user.
    public struct AvatarCustomizationCurrentUserInfo: Decodable, Hashable {
        
        /// The user's current score on devRant.
        public var score: Int
    }
    
    /// A model representing an avatar customization type.
    public struct AvatarCustomizationType: Decodable, Hashable, Identifiable {
        
        /// The gender for which the customization type is made for, if the type is gender-specific.
        public let forGender: String?
        
        /// The ID of the customization type.
        public let id: String
        
        /// The display label that describes the customization type.
        public let label: String
        
        /// If the type is a subtype of a parent type, this will be equal to the sub-type's ID.
        public let subType: Int?
        
        private enum CodingKeys: String, CodingKey {
            case id
            case label
            case subType = "sub_type"
            case forGender = "for_gender"
        }
    }
    
    /// A model representing an avatar customization option.
    public struct AvatarCustomizationOption: Decodable, Hashable, Identifiable {
        
        /// The background color of the option's image in hexadecimal.
        public let backgroundColor: String?
        
        /// The ID of the option.
        public let id: String?
        
        /// Information about the option's different images.
        public let image: AvatarCustomizationImage
        
        /// The required amount of points in order to select the option, if the option is locked under a minimum amount of points.
        public let requiredPoints: Int?
        
        /// If the option is currently selected, this property will be equal to `true`. If not, this property will be equal to `false` or `nil`.
        public let isSelected: Bool?
        
        private enum CodingKeys: String, CodingKey {
            case backgroundColor = "bg"
            case id
            case image = "img"
            case requiredPoints = "points"
            case isSelected = "selected"
        }
    }
    
    /// The customization options given for the requested type.
    public let avatars: [AvatarCustomizationOption]
    
    /// The current user's info.
    public let userInfo: AvatarCustomizationCurrentUserInfo
    
    /// All possible customization types.
    /// - note: This value will be `nil` if you requested to get the customization results without the types.
    public let types: [AvatarCustomizationType]?
    
    private enum CodingKeys: String, CodingKey {
        case avatars
        case userInfo = "me"
        case types = "options"
    }
}

extension AvatarCustomizationResults {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        avatars = try values.decodeIfPresent([AvatarCustomizationOption].self, forKey: .avatars) ?? []
        
        userInfo = try values.decode(AvatarCustomizationCurrentUserInfo.self, forKey: .userInfo)
        types = try values.decodeIfPresent([AvatarCustomizationType].self, forKey: .types)
    }
}

extension AvatarCustomizationResults.AvatarCustomizationType {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        do {
            id = try values.decode(String.self, forKey: .id)
        } catch {
            id = try String(values.decode(Int.self, forKey: .id))
        }
        
        label = try values.decode(String.self, forKey: .label)
        subType = try values.decodeIfPresent(Int.self, forKey: .subType)
        forGender = try values.decodeIfPresent(String.self, forKey: .forGender)
    }
}

extension AvatarCustomizationResults.AvatarCustomizationOption {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        backgroundColor = try values.decodeIfPresent(String.self, forKey: .backgroundColor)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        image = try values.decode(AvatarCustomizationResults.AvatarCustomizationImage.self, forKey: .image)
        requiredPoints = try values.decodeIfPresent(Int.self, forKey: .requiredPoints)
        isSelected = try values.decodeIfPresent(Bool.self, forKey: .isSelected)
    }
}
