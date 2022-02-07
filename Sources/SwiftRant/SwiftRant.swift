import Foundation
import SwiftKeychainWrapper

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif

/// Holds the raw devRant server response for getting a rant.
/// This is essential because the rant and its comments are distributed across 2 different properties in the returned JSON object.
fileprivate struct RantResponse: Decodable {
    
    /// The rant itself.
    public var rant: Rant
    
    /// The comments listed under the rant.
    public var comments: [Comment]?
    
    private enum CodingKeys: String, CodingKey {
        case rant, comments
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        rant = try values.decode(Rant.self, forKey: .rant)
        
        
        comments = try values.decodeIfPresent([Comment].self, forKey: .comments)
        
        if comments != nil {
            for idx in 0..<comments!.count {
                comments![idx].precalculateLinkRanges()
            }
        }
    }
}

fileprivate struct CommentResponse: Decodable {
    public let comment: Comment?
}

fileprivate struct ProfileResponse: Decodable {
    let profile: Profile?
}

public class SwiftRant {
    
    /// Initializes the SwiftRant library.
    ///
    /// - Parameter shouldUseKeychainAndUserDefaults: Whether or not the library should store devRant access tokens and the user's personal username and password in the Keychain and small caches in User Defaults. If no value is given, Keychain and User Defaults for the instance are automatically enabled.
    /// - Returns: a new SwiftRant class.
    init(shouldUseKeychainAndUserDefaults: Bool = true) {
        self.shouldUseKeychainAndUserDefaults = shouldUseKeychainAndUserDefaults
    }
    
    /// The shared SwiftRant instance.
    ///
    /// This instance is configured to use the Keychain and User Defaults.
    public static let shared = SwiftRant()
    
    private let shouldUseKeychainAndUserDefaults: Bool
    
    private let baseURL = "https://devrant.com/api"
    
    private let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant")
    
    /// The username stored in the system keychain.
    public var usernameFromKeychain: String? {
        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecReturnAttributes as String: true,
                                   kSecReturnData as String: true,
                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
        ]
        
        var item: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &item)
        
        let existingItem = item as? [String:Any]
        
        let username = existingItem?[kSecAttrAccount as String] as? String
        
        //self.keychainWrapper.string(forKey: "DRUsername")
        
        return username
    }
    
    /// The password stored in the system keychain.
    public var passwordFromKeychain: String? {
        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecReturnAttributes as String: true,
                                   kSecReturnData as String: true,
                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
        ]
        
        var item: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &item)
        
        let existingItem = item as? [String:Any]
        let passwordData = (existingItem?[kSecValueData as String] as? Data) ?? Data()
        let password = String(data: passwordData, encoding: .utf8)
        
        return password
        
        //self.keychainWrapper.string(forKey: "DRPassword")
    }
    
    /// The access token stored in the system keychain.
    public var tokenFromKeychain: UserCredentials? {
        let credentials: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
        return credentials
    }
    
    // MARK: - Data fetchers
    
    /// Returns an auth token if the username and password are both correct.
    ///
    /// - Parameter username: The username of the user attempting to log in.
    /// - Parameter password: The password of the user attempting to log in.
    /// - Parameter completionHandler: an escaping method that takes in a `String` parameter and a ``UserCredentials`` parameter.
    ///
    /// If the authentication is successful, the ``UserCredentials`` parameter will hold the actual auth token info, while the `String` is `nil`. If the authentication is unsuccessful, then the `String` will hold an error message, while the ``UserCredentials`` will be `nil`.
    ///
    /// If you called this method while initializing ``SwiftRant`` while setting `shouldUseKeychainAndUserDefaults` with `true`, the username, password and access token will be stored in the Keychain securely.
    public func logIn(username: String, password: String, completionHandler: @escaping ((String?, UserCredentials?) -> Void)) {
        let resourceURL = URL(string: baseURL + "/users/auth-token?app=3")!
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "app=3&username=\(username)&password=\(password.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)".data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let _ = response {
                if let data = data, let _ = String(data: data, encoding: .utf8) {
                    let decoder = JSONDecoder()
                    
                    let token: UserCredentials? = try? decoder.decode(UserCredentials.self, from: data)
                    
                    if token == nil {
                        if self.shouldUseKeychainAndUserDefaults {
                            self.keychainWrapper.removeObject(forKey: "DRToken")
                        }
                        
                        // Create a query that finds the entry that was generated by SwiftRant.
                        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                                   kSecReturnAttributes as String: true,
                                                   kSecReturnData as String: true,
                                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
                        ]
                        
                        // Tell the Keychain API to destroy the entry that resulted from the query.
                        SecItemDelete(query as CFDictionary)
                        
                        let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                        
                        if let jsonObject = jsonObject {
                            if let jObject = jsonObject as? [String:Any] {
                                if let error = jObject["error"] as? String {
                                    completionHandler(error, nil)
                                    return
                                }
                                
                                completionHandler("An unknown error has occurred.", nil)
                                return
                            }
                            
                            completionHandler("An unknown error has occurred.", nil)
                            return
                        }
                        
                        completionHandler("An unknown error has occurred.", nil)
                        return
                    }
                    
                    if self.shouldUseKeychainAndUserDefaults {
                        //UserDefaults.standard.set(token!.authToken.userID, forKey: "DRUserID")
                        //UserDefaults.standard.set(token!.authToken.tokenID, forKey: "DRTokenID")
                        //UserDefaults.standard.set(token!.authToken.tokenKey, forKey: "DRTokenKey")
                        //UserDefaults.standard.set(token!.authToken.expireTime, forKey: "DRTokenExpireTime")
                        
                        //UserDefaults.standard.encodeAndSet(token!, forKey: "DRToken")
                        
                        //var didSucceed = self.keychainWrapper.set(username, forKey: "DRUsername", withAccessibility: .whenUnlockedThisDeviceOnly, isSynchronizable: false)
                        
                        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                                   kSecAttrAccount as String: username,
                                                   kSecValueData as String: password.data(using: .utf8)!,
                                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
                        ]
                        
                        let status = SecItemAdd(query as CFDictionary, nil)
                        
                        if status == errSecSuccess {
                            print("STORING USERNAME AND PASSWORD TO KEYCHAIN SUCCEEDED")
                        } else {
                            print("STORING USERNAME AND PASSWORD TO KEYCHAIN NOT SUCCESSFUL")
                        }
                        
                        //print("DID SUCCEED IN WRITING USERNAME TO KEYCHAIN: \(didSucceed)")
                        
                        //didSucceed = self.keychainWrapper.set(password, forKey: "DRPassword", withAccessibility: .whenUnlockedThisDeviceOnly, isSynchronizable: false)
                        //print("DID SUCCEED IN WRITING PASSWORD TO KEYCHAIN: \(didSucceed)")
                        
                        let didSucceed = self.keychainWrapper.encodeAndSet(token, forKey: "DRToken", withAccessibility: .whenUnlockedThisDeviceOnly)
                        print("DID SUCCEED IN WRITING TOKEN TO KEYCHAIN: \(didSucceed)")
                        
                        //UserDefaults.standard.set(username, forKey: "DRUsername")
                        //UserDefaults.standard.set(password, forKey: "DRPassword")
                    }
                    
                    completionHandler(nil, token)
                    return
                }
                
                completionHandler("An unknown error has occurred.", nil)
                return
            }
            
            completionHandler("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    /// Gets a personalized rant feed for the user.
    ///
    /// - parameter token: The user's token. set to `nil`if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    /// - parameter prevSet: The ``RantFeed/set`` you got in the last fetch. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults, the SwiftRant instance will get the set from the last fetch from User Defaults.
    /// - parameter completionHandler: A function that will run after the fetch is completed. If the fetch is successful, the ``RantFeed`` parameter will hold the actual auth token info, while the `String` is `nil`. If the fetch is unsuccessful, then the `String` will hold an error message, while the ``RantFeed`` will be `nil`.
    public func getRantFeed(token: UserCredentials?, skip: Int, prevSet: String?, completionHandler: @escaping ((String?, RantFeed?) -> Void)) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain!, password: usernameFromKeychain!) { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler(errorMessage, nil)
                }
            }
        }
        
        var resourceURL: URL {
            if shouldUseKeychainAndUserDefaults {
                if UserDefaults.standard.string(forKey: "DRLastSet") != nil {
                    let currentToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
                    return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo&prev_set=\(String(UserDefaults.standard.string(forKey: "DRLastSet")!))&app=3&plat=1&nari=1&user_id=\(String(currentToken!.authToken.userID))&token_id=\(String(currentToken!.authToken.tokenID))&token_key=\(currentToken!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                } else {
                    let currentToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
                    return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo&app=3&plat=1&nari=1&user_id=\(String(currentToken!.authToken.userID))&token_id=\(String(currentToken!.authToken.tokenID))&token_key=\(currentToken!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                }
            } else {
                return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo\(prevSet != nil ? "prev_set=\(prevSet!)" : "")&app=3&plat=1&nari=1&user_id=\(String(token!.authToken.userID))&token_id=\(String(token!.authToken.tokenID))&token_key=\(token!.authToken.tokenKey)")!
            }
        }
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let _ = response {
                if let data = data {
                    let decoder = JSONDecoder()
                    
                    let rantFeed = try? decoder.decode(RantFeed.self, from: data)
                    
                    if rantFeed == nil {
                        let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                        
                        if let jsonObject = jsonObject {
                            if let jObject = jsonObject as? [String:Any] {
                                if let error = jObject["error"] as? String {
                                    completionHandler(error, nil)
                                    return
                                }
                                
                                completionHandler("An unknown error has occurred.", nil)
                                return
                            }
                            
                            completionHandler("An unknown error has occurred.", nil)
                            return
                        }
                        
                        completionHandler("An unknown error has occurred.", nil)
                        return
                    }
                    
                    if self.shouldUseKeychainAndUserDefaults {
                        UserDefaults.standard.set(rantFeed!.set, forKey: "DRLastSet")
                    }
                    
                    completionHandler(nil, rantFeed)
                    return
                } else {
                    completionHandler("An unknown error has occurred.", nil)
                    return
                }
            } else {
                completionHandler("An unknown error has occurred.", nil)
                return
            }
        }.resume()
    }
    
    /// Get the notification feed for the current user.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter lastCheckTime: The last Unix Timestamp at which the notifications were last checked at. Set to `nil` is the SwiftRant instance was configured to use Keychain and User Defaults, or if you set `shouldGetNewNotifs` to `false`.
    /// - parameter shouldGetNewNotifs: Whether or not the function should retrieve the latest notifications since the Unix Timestamp stored in User Defaults or `lastCheckTime`. If set to `false` and the SwiftRant instance was configured to use the Keychain and User Defaults, set `lastCheckTime` to `nil`. If set to `true` and the SwiftRant instance was NOT configured to use the Keychain and User Defaults, set `lastCheckTime` to the last Unix Timestamp at which the notifications were fetched last time.
    /// - parameter category: The category of notifications that the function should return.
    /// - parameter completionHandler: A function that will run after the fetch is completed. If the fetch was successful, the ``Notifications`` parameter will hold the actual notification info, while the `String` is `nil`. If the fetch was unsuccessful, then the `String` will hold an error message, while the ``Notifications`` will be `nil`.
    public func getNotificationFeed(token: UserCredentials?, lastCheckTime: Int?, shouldGetNewNotifs: Bool, category: Notifications.Categories, completionHandler: @escaping ((String?, Notifications?) -> Void)) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler(errorMessage, nil)
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/users/me/notif-feed\(category == .all ? "" : "/\(category.rawValue)")?last_time=\(shouldUseKeychainAndUserDefaults ? (shouldGetNewNotifs ? UserDefaults.standard.integer(forKey: "DRLastNotifCheckTime") : 0) : (shouldGetNewNotifs ? lastCheckTime! : 0))&ext_prof=1&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let notificationResult = try? decoder.decode(NotificationFeed.self, from: data)
                
                if notificationResult == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler(error, nil)
                                return
                            }
                        }
                        
                        completionHandler("An unknown error has occurred.", nil)
                        return
                    }
                    
                    completionHandler("An unknown error has occurred.", nil)
                    return
                } else {
                    completionHandler(nil, notificationResult!.data)
                    return
                }
            }
            
            completionHandler("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    /// Get a specific rant with a given ID.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter id: The ID of the rant to fetch.
    /// - parameter lastCommentID: If set to a valid comment ID that exists in the rant's comments, the function will get all the comments that were posted after the comment with the given ID.
    /// - parameter completionHandler: A function that will run after the fetch is completed. If the fetch was successful, the ``Rant`` parameter will hold the actual rant info, the ``Comment`` array will hold all the comments attached to the ``Rant`` and the `String` will be `nil`. If the fetch was unsuccessful, then the `String` will hold an error message, and the ``Rant`` and ``Comment`` will both be `nil`.
    public func getRantFromID(token: UserCredentials?, id: Int, lastCommentID: Int?, completionHandler: ((String?, Rant?, [Comment]?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil, nil)
                    return
                }
            }
        }
        
        let currentToken: UserCredentials? = shouldUseKeychainAndUserDefaults ? keychainWrapper.decode(forKey: "DRToken") : token
        
        let resourceURL = URL(string: baseURL + "/devrant/rants/\(id)?app=3&ver=1.17.0.4&user_id=\(currentToken!.authToken.userID)&token_id=\(currentToken!.authToken.tokenID)&token_key=\(currentToken!.authToken.tokenKey)\(lastCommentID != nil ? "&last_comment_id=\(lastCommentID!)" : "")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let rantResponse = try? decoder.decode(RantResponse.self, from: data)
                
                if rantResponse == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(error, nil, nil)
                                return
                            }
                        }
                    }
                    
                    completionHandler?("An unknown error has occurred.", nil, nil)
                    return
                } else {
                    completionHandler?(nil, rantResponse?.rant, rantResponse?.comments)
                    return
                }
            }
        }.resume()
    }
    
    /// Gets a single comment by ID.
    ///
    /// - parameter id: The ID of the comment to fetch.
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter completionHandler: A function that will run after the fetch is completed. If the fetch was successful, the `String?` parameter of the function will contain `nil` and the ``Comment`` parameter of the function will contain the fetched comment. If the fetch was unsuccessful, the `String?` parameter will contain an error message, and the ``Comment`` parameter will contain `nil`.
    public func getCommentFromID(_ id: Int, token: UserCredentials?, completionHandler: ((String?, Comment?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/comments/\(id)?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let comment = try? decoder.decode(CommentResponse.self, from: data)
                
                if comment == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(error, nil)
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(nil, comment?.comment)
                    return
                }
            }
            
            completionHandler?("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    // VERY EARLY PROTOTYPE TO GET THE USER'S SUBSCRIBED FEED.
    // lastEndCursor is for infinite scroll/pagination.
    // struct coming soon.
    public func getSubscribedFeed(_ token: UserCredentials?, lastEndCursor: String?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    // TODO: CREATE A COMPLETION HANDLER!
                    //completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/api/me/subscribed-feed?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        // TODO: WRITE THE REQUEST!
        fatalError("Not implemented yet!")
    }
    
    /// Retrieves the ID of a user with a specified username
    ///
    /// - parameter username: The username to get the ID for.
    /// - parameter completionHandler: A function that will run after the fetch is completed. If the fetch was successful, the `String?` parameter of the function will contain `nil`, and the `Int?` parameter of the function will contain the ID for the given username. If the fetch was unsuccessful, the `String?` parameter will contain an error message, and the `Int?` will contain `nil`.
    public func getUserID(of username: String, completionHandler: ((String?, Int?) -> Void)?) {
        let resourceURL = URL(string: "\(baseURL)/get-user-id?app=3&username=\(username)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, jObject["user_id"] as? Int)
                                return
                            } else {
                                completionHandler?("User doesn't exist!", nil)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", nil)
        }.resume()
    }
    
    /// Get a user's profile data.
    ///
    /// - parameter id: The ID of the user whose data will be fetched.
    /// - parameter userContentType: The type of content created by the user to be fetched.
    /// - parameter skip: The amount of content to be skipped on. Useful for pagination/infinite scroll.
    /// - parameter completionHandler: A function that will run after the fetch is completed. If the fetch was successful, the `String?` parameter of the function will contain `nil`, and the ``Profile`` parameter of the function will hold the fetched profile information. If the fetch was unsuccessful, the `String?` parameter of the function will contain an error message, and the ``Profile`` parameter of the function will contain `nil`.
    public func getProfileFromID(_ id: Int, token: UserCredentials?, userContentType: Profile.ProfileContentTypes, skip: Int, completionHandler: ((String?, Profile?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/users/\(id)?app=3&skip=\(skip)&content=\(userContentType.rawValue)&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let profileResponse = try? decoder.decode(ProfileResponse.self, from: data)
                
                if profileResponse == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(error, nil)
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(nil, profileResponse?.profile)
                    return
                }
                
                completionHandler?("An unknown error has occurred.", nil)
                return
            }
            
            completionHandler?("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    /// Retrieves a set of avatar customization options listed under a specific type of customization.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter type: The type of customization to retrieve the options for.
    /// - parameter subType: The sub-type of the type of customization to retrieve the options for. Not all customization types have a subtype, so this parameter is optional. If the type does not contain a sub-type, set `subOption` to `nil`.
    /// - parameter currentImageID: The ID of the current avatar of the user.
    /// - parameter shouldGetPossibleOptions: Whether or not the server should return the entire list of the different types and sub-types of customizations for a devRant avatar, alongside the query.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the ``AvatarCustomizationResults`` parameter of the function will contain the query's results. If the request was unsuccessful, the `String?` parameter will contain an error message, and the ``AvatarCustomizationResults`` will contain `nil`.
    public func getAvatarCustomizationOptions(_ token: UserCredentials?, type: String, subType: Int?, currentImageID: String, shouldGetPossibleOptions: Bool, completionHandler: ((String?, AvatarCustomizationResults?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/avatars/build?app=3&option=\(type)&image_id=\(currentImageID)&features=\(shouldGetPossibleOptions ? 1 : 0)\(subType != nil ? "&sub_option=\(subType!)" : "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let results = try? JSONDecoder().decode(AvatarCustomizationResults.self, from: data)
                
                if results != nil {
                    completionHandler?(nil, results)
                    return
                } else {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String: Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(error, nil)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    // MARK: - Data Senders
    
    /// Vote on a rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to vote on.
    /// - parameter vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the ``Rant`` parameter of the function will hold the target rant with updated information. If the request was unsuccessful, the `String?` parameter will contain an error message, and the ``Rant`` will contain `nil`.
    public func voteOnRant(_ token: UserCredentials?, rantID id: Int, vote: Int, completionHandler: ((String?, Rant?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/rants/\(id)/vote".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&vote=\(vote)".data(using: .utf8)
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let updatedRantInfo = try? decoder.decode(RantResponse.self, from: data)
                
                if updatedRantInfo == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(error, nil)
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(nil, updatedRantInfo?.rant)
                    return
                }
                
                completionHandler?("An unknown error has occurred.", nil)
                return
            }
            
            completionHandler?("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    /// Vote on a comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to vote on.
    /// - parameter vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String` parameter of the function will contain `nil`, and the ``Comment`` parameter of the function will hold the target comment with updated information. If the request was unsuccessful, the `String?` parameter will contain an error message, and the ``Comment`` will contain `nil`.
    public func voteOnComment(_ token: UserCredentials?, commentID id: Int, vote: Int, completionHandler: ((String?, Comment?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/comments/\(id)/vote".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&vote=\(vote)".data(using: .utf8)
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let updatedCommentInfo = try? decoder.decode(CommentResponse.self, from: data)
                
                if updatedCommentInfo == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(error, nil)
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(nil, updatedCommentInfo?.comment)
                    return
                }
                
                completionHandler?("An unknown error has occurred.", nil)
                return
            }
            
            completionHandler?("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    
    /// Updates the summary of the user whose token is used.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter aboutSection: The user's about section.
    /// - parameter skills: The user's list of skills.
    /// - parameter githubLink: The user's GitHub link.
    /// - parameter location: The user's location.
    /// - parameter website: The user's personal website.
    /// - parameter completionHandler: A function that wil run after the request was completed. If the request was successful, the `String?` parameter of the function will contain `nil`. If the request was unsuccessful, the `String?` parameter of the function will hold an error message.
    public func editProfileDetails(_ token: UserCredentials?, aboutSection: String?, skills: String?, githubLink: String?, location: String?, website: String?, completionHandler: ((String?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/users/me/edit-profile".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.httpBody = "app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&profile_about=\(aboutSection ?? "")&profile_skills=\(skills ?? "")&profile_github=\(githubLink ?? "")&profile_location=\(location ?? "")&profile_website=\(website ?? "")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                
                if let jsonObject = jsonObject {
                    if let jObject = jsonObject as? [String:Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil)
                                return
                            } else {
                                if let error = jObject["error"] as? String {
                                    completionHandler?(error)
                                    return
                                }
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.")
        }.resume()
    }
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Posts a rant to devRant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter postType: The type of post.
    /// - parameter content: The text content of the post.
    /// - parameter tags: The post's associated tags.
    /// - parameter image: An image to attach to the post.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Int?` parameter of the function will contain the ID of the post. If the the request was unsuccessful, the `String?` parameter will contain an error message, and the `Int?` will contain `nil`.
    public func postRant(_ token: UserCredentials?, postType: Rant.RantType, content: String, tags: String?, image: UIImage?, completionHandler: ((String?, Int?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/rants".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "rant": content,
                "tags": (tags != nil ? tags! : ""),
                "token_id": shouldUseKeychainAndUserDefaults ? String(tokenFromKeychain!.authToken.tokenID) : String(token!.authToken.tokenID),
                "token_key": shouldUseKeychainAndUserDefaults ? String(tokenFromKeychain!.authToken.tokenKey) : String(token!.authToken.tokenKey),
                "user_id": shouldUseKeychainAndUserDefaults ? String(tokenFromKeychain!.authToken.userID) : String(token!.authToken.userID),
                "type": String(postType.rawValue)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: image?.jpegData(compressionQuality: 1.0))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&rant=\(content)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&tags=\(tags ?? "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&type=\(postType.rawValue)&app=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, jObject["rant_id"] as? Int)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, nil)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error as occurred.", nil)
            return
        }.resume()
    }
    #else
    /// Posts a rant to devRant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter postType: The type of the post.
    /// - parameter content: The text content of the post.
    /// - parameter tags: The post's associated tags.
    /// - parameter image: An image to attach to the post.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Int?` parameter of the function will contain the ID of the post. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Int?` will contain `nil`.
    public func postRant(_ token: UserCredentials?, postType: Rant.RantType, content: String, tags: String?, image: NSImage?, completionHandler: ((String?, Int?) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, nil)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/rants".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
    
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "rant": content,
                "tags": (tags != nil ? tags! : ""),
                "token_id": shouldUseKeychainAndUserDefaults ? String(tokenFromKeychain!.authToken.tokenID) : String(token!.authToken.tokenID),
                "token_key": shouldUseKeychainAndUserDefaults ? String(tokenFromKeychain!.authToken.tokenKey) : String(token!.authToken.tokenKey),
                "user_id": shouldUseKeychainAndUserDefaults ? String(tokenFromKeychain!.authToken.userID) : String(token!.authToken.userID),
                "type": String(postType.rawValue)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: image != nil ? jpegData(from: image!) : nil)
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&rant=\(content)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&tags=\(tags ?? "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&type=\(postType.rawValue)&app=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, jObject["rant_id"] as? Int)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, nil)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", nil)
            return
        }.resume()
    }
    #endif
    
    /// Deletes a post from devRant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the post or rant to be deleted.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If he request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func deleteRant(_ token: UserCredentials?, rantID: Int, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)?app=3&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "DELETE"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, success)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    
    /// Marks a rant as a favorite.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the post or rant to be marked as favorite.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful. the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func favoriteRant(_ token: UserCredentials?, rantID: Int, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)/favorite".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        request.httpMethod = "POST"
        request.httpBody = "app=3&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, success)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
        }.resume()
    }
    
    /// Unmarks a rant as a favorite.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the post or rant to be unmarked as favorite.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful. the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func unfavoriteRant(_ token: UserCredentials?, rantID: Int, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)/unfavorite".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        var request = URLRequest(url: resourceURL)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        request.httpMethod = "POST"
        request.httpBody = "app=3&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, success)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
        }.resume()
    }
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Edits a posted rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to be edited.
    /// - parameter postType: The new type of the post.
    /// - parameter content: The new text content of the post.
    /// - parameter tags: The post's new associated tags.
    /// - parameter image: A new image to attach to the post.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func editRant(_ token: UserCredentials?, rantID: Int, postType: Rant.RantType, content: String, tags: String?, image: UIImage?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "rant": content,
                "tags": (tags != nil ? tags! : ""),
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID),
                "type": String(postType.rawValue)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: image?.jpegData(compressionQuality: 1.0))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&rant=\(content)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&tags=\(tags ?? "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&type=\(postType.rawValue)&app=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    #else
    /// Edits a posted rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to be edited.
    /// - parameter postType: The new type of the post.
    /// - parameter content: The new text content of the post.
    /// - parameter tags: The post's new associated tags.
    /// - parameter image: A new image to attach to the post.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func editRant(_ token: UserCredentials?, rantID: Int, postType: Rant.RantType, content: String, tags: String?, image: NSImage?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
    
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "rant": content,
                "tags": (tags != nil ? tags! : ""),
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID),
                "type": String(postType.rawValue)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: jpegData(from: image!))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&rant=\(content)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&tags=\(tags ?? "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&type=\(postType.rawValue)&app=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    #endif
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Posts a comment under a specific rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to post a comment under.
    /// - parameter content: The text content of the comment.
    /// - parameter image: An image to attach to the comment.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func postComment(_ token: UserCredentials?, rantID: Int, content: String, image: UIImage?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)/comments".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "comment": content,
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: image?.jpegData(compressionQuality: 1.0))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = "comment=\(content)&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    #else
    /// Posts a comment under a specific rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to post a comment under.
    /// - parameter content: The text content of the comment.
    /// - parameter image: An image to attach to the comment.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func postComment(_ token: UserCredentials?, rantID: Int, content: String, image: NSImage?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)/comments".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "comment": content,
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: jpegData(from: image!))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = "comment=\(content)&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    #endif
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Edits a posted comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to be edited.
    /// - parameter content: The new text content of the comment.
    /// - parameter image: A new image to attach to the comment.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func editComment(_ token: UserCredentials?, commentID: Int, content: String, image: UIImage?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/comments/\(commentID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "POST"
        
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "comment": content,
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: image?.jpegData(compressionQuality: 1.0))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "comment=\(content)&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    #else
    /// Edits a posted comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to be edited.
    /// - parameter content: The new text content of the comment.
    /// - parameter image: A new image to attach to the comment.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func editComment(_ token: UserCredentials?, commentID: Int, content: String, image: NSImage?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/comments/\(commentID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "POST"
        
        if image != nil {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "comment": content,
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: jpegData(from: image!))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "comment=\(content)&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    #endif
    
    /// Deletes an existing comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to be deleted.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func deleteComment(_ token: UserCredentials?, commentID: Int, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/comments/\(commentID)?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "DELETE"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    
    /// Updates the avatar image for the given user.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter fullImageID: The ID of the new avatar image (a file name with the extension of .png).
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func confirmAvatarCustomization(_ token: UserCredentials?, fullImageID: String, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/users/me/avatar".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.httpBody = "token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&app=3&image_id=\(fullImageID)&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
            return
        }.resume()
    }
    
    /// Marks all unread notifications as read.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter completionHandler: A function that will run after the request is completed. If the request was successful, the `String?` parameter of the function will contain `nil`, and the `Bool` parameter of the function will contain `true`. If the request was unsuccessful, the `String?` parameter will contain an error message, and the `Bool` will contain `false`.
    public func clearNotifications(_ token: UserCredentials?, completionHandler: ((String?, Bool) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: usernameFromKeychain ?? "", password: passwordFromKeychain ?? "") { error, _ in
                    if error != nil {
                        errorMessage = error
                        loginSemaphore.signal()
                        return
                    }
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(errorMessage, false)
                    return
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/users/me/notif-feed?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "DELETE"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(nil, true)
                                return
                            } else {
                                completionHandler?(jObject["error"] as? String, false)
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?("An unknown error has occurred.", false)
        }.resume()
    }
    
    // MARK: - Async Wrappers
    
    /// Returns an auth token if the username and password are both correct.
    ///
    /// - Parameter username: The username of the user attempting to log in.
    /// - Parameter password: The password of the user attempting to log in.
    /// - returns: A tuple that contains an error in a ``String`` and the token as a ``UserCredentials``.
    ///
    /// If the authentication is successful, the ``UserCredentials`` in the tuple will hold the actual auth token info, while the `String` in the tuple will be `nil`. If the authentication is unsuccessful, then the `String` in the tuple will hold an error message, while the ``UserCredentials`` in the tuple will be `nil`.
    ///
    /// If you called this method while initializing ``SwiftRant`` while setting `shouldUseKeychainAndUserDefaults` with `true`, the username, password and access token will be stored in the Keychain securely.
    public func logIn(username: String, password: String) async -> (String?, UserCredentials?) {
        return await withCheckedContinuation { continuation in
            self.logIn(username: username, password: password) { error, credentials in
                continuation.resume(returning: (error, credentials))
            }
        }
    }
    
    /// Gets a personalized rant feed for the user.
    ///
    /// - parameter token: The user's token. set to `nil`if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    /// - parameter prevSet: The ``RantFeed/set`` you got in the last fetch. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults, the SwiftRant instance will get the set from the last fetch from User Defaults.
    /// - returns: A tuple that contains an error in a ``String`` and the feed as a ``RantFeed``. If the fetch is successful, the ``RantFeed`` in the tuple will hold the actual auth token info, while the `String` in the tuple is `nil`. If the fetch is unsuccessful, then the `String` in the tuple will hold an error message, while the ``RantFeed`` in the tuple will be `nil`.
    public func getRantFeed(token: UserCredentials?, skip: Int, prevSet: String?) async -> (String?, RantFeed?) {
        return await withCheckedContinuation { continuation in
            self.getRantFeed(token: token, skip: skip, prevSet: prevSet) { error, feed in
                continuation.resume(returning: (error, feed))
            }
        }
    }
    
    /// Get the notification feed for the current user.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter lastCheckTime: The last Unix Timestamp at which the notifications were last checked at. Set to `nil` is the SwiftRant instance was configured to use Keychain and User Defaults, or if you set `shouldGetNewNotifs` to `false`.
    /// - parameter shouldGetNewNotifs: Whether or not the function should retrieve the latest notifications since the Unix Timestamp stored in User Defaults or `lastCheckTime`. If set to `false` and the SwiftRant instance was configured to use the Keychain and User Defaults, set `lastCheckTime` to `nil`. If set to `true` and the SwiftRant instance was NOT configured to use the Keychain and User Defaults, set `lastCheckTime` to the last Unix Timestamp at which the notifications were fetched last time.
    /// - parameter category: The category of notifications that the function should return.
    /// - returns: A tuple that contains an error in a ``String`` and the notification feed as a ``Notifications``. If the fetch was successful, the ``Notifications`` in the tuple will hold the actual notification info, while the `String` in the tuple will be `nil`. If the fetch was unsuccessful, then the `String` in the tuple will hold an error message, while the ``Notifications`` in the tuple will be `nil`.
    public func getNotificationFeed(token: UserCredentials?, lastCheckTime: Int?, shouldGetNewNotifs: Bool, category: Notifications.Categories) async -> (String?, Notifications?) {
        return await withCheckedContinuation { continuation in
            self.getNotificationFeed(token: token, lastCheckTime: lastCheckTime, shouldGetNewNotifs: shouldGetNewNotifs, category: category) { error, notifications in
                continuation.resume(returning: (error, notifications))
            }
        }
    }
    
    /// Get a specific rant with a given ID.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter id: The ID of the rant to fetch.
    /// - parameter lastCommentID: If set to a valid comment ID that exists in the rant's comments, the function will get all the comments that were posted after the comment with the given ID.
    /// - returns: A tuple that contains an error in a ``String``, the rant as a ``Rant`` and the rant's comments as an array of ``Comment``. If the fetch was successful, the ``Rant`` in the tuple will hold the actual rant info, the ``Comment`` array in the tuple will hold all the comments attached to the ``Rant`` and the `String` in the tuple will be `nil`. If the fetch was unsuccessful, then the `String` in the tuple will hold an error message, and the ``Rant`` and ``Comment`` array in the tuple will both be `nil`.
    public func getRantFromID(token: UserCredentials?, id: Int, lastCommentID: Int?) async -> (String?, Rant?, [Comment]?) {
        return await withCheckedContinuation { continuation in
            self.getRantFromID(token: token, id: id, lastCommentID: lastCommentID) { error, rant, comments in
                continuation.resume(returning: (error, rant, comments))
            }
        }
    }
    
    /// Gets a single comment by ID.
    ///
    /// - parameter id: The ID of the comment to fetch.
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - returns: A tuple that contains an error in a ``String`` and the comment as a ``Comment``. If the fetch was successful, the `String` in the tuple  will contain `nil` and the ``Comment`` in the tuple will contain the fetched comment. If the fetch was unsuccessful, the `String?` in the tuple will contain an error message, and the ``Comment`` in the tuple will contain `nil`.
    public func getCommentFromID(_ id: Int, token: UserCredentials?) async -> (String?, Comment?) {
        return await withCheckedContinuation { continuation in
            self.getCommentFromID(id, token: token) { error, comment in
                continuation.resume(returning: (error, comment))
            }
        }
    }
    
    /// Retrieves the ID of a user with a specified username
    ///
    /// - parameter username: The username to get the ID for.
    /// - returns: A tuple that contains an error in a ``String`` and the user's ID in an ``Int``. If the fetch was successful, the `String?` in the tuple will contain `nil`, and the `Int?` in the tuple will contain the ID for the given username. If the fetch was unsuccessful, the `String?` in the tuple will contain an error message, and the `Int?` in the tuple will contain `nil`.
    public func getUserID(of username: String) async -> (String?, Int?) {
        return await withCheckedContinuation { continuation in
            self.getUserID(of: username) { error, userID in
                continuation.resume(returning: (error, userID))
            }
        }
    }
    
    /// Get a user's profile data.
    ///
    /// - parameter id: The ID of the user whose data will be fetched.
    /// - parameter userContentType: The type of content created by the user to be fetched.
    /// - parameter skip: The amount of content to be skipped on. Useful for pagination/infinite scroll.
    /// - returns: A tuple that contains an error in a ``String`` and the profile as a ``Profile``. If the fetch was successful, the `String?` in the tuple will contain `nil`, and the ``Profile`` in the tuple will hold the fetched profile information. If the fetch was unsuccessful, the `String?` in the tuple will contain an error message, and the ``Profile`` in the tuple will contain `nil`.
    public func getProfileFromID(_ id: Int, token: UserCredentials?, userContentType: Profile.ProfileContentTypes, skip: Int) async -> (String?, Profile?) {
        return await withCheckedContinuation { continuation in
            self.getProfileFromID(id, token: token, userContentType: userContentType, skip: skip) { error, profile in
                continuation.resume(returning: (error, profile))
            }
        }
    }
    
    /// Retrieves a set of avatar customization options listed under a specific type of customization.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter type: The type of customization to retrieve the options for.
    /// - parameter subType: The sub-type of the type of customization to retrieve the options for. Not all customization types have a subtype, so this parameter is optional. If the type does not contain a sub-type, set `subOption` to `nil`.
    /// - parameter currentImageID: The ID of the current avatar of the user.
    /// - parameter shouldGetPossibleOptions: Whether or not the server should return the entire list of the different types and sub-types of customizations for a devRant avatar, alongside the query.
    /// - returns: A tuple that contains an error in a ``String`` and the query results as a ``AvatarCustomizationResults``. If the request was successful, the `String?` in the tuple will contain `nil`, and the ``AvatarCustomizationResults`` in the tuple will contain the query's results. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the ``AvatarCustomizationResults`` in the tuple will contain `nil`.
    public func getAvatarCustomizationOptions(_ token: UserCredentials?, type: String, subType: Int?, currentImageID: String, shouldGetPossibleOptions: Bool) async -> (String?, AvatarCustomizationResults?) {
        return await withCheckedContinuation { continuation in
            self.getAvatarCustomizationOptions(token, type: type, subType: subType, currentImageID: currentImageID, shouldGetPossibleOptions: shouldGetPossibleOptions) { error, results in
                continuation.resume(returning: (error, results))
            }
        }
    }
    
    /// Vote on a rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to vote on.
    /// - parameter vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    /// - returns: A tuple that contains an error message in a ``String`` and the updated rant as a ``Rant``. If the request was successful, the `String?` in the tuple will contain `nil`, and the ``Rant`` in the tuple will hold the target rant with updated information. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the ``Rant`` in the tuple will contain `nil`.
    public func voteOnRant(_ token: UserCredentials?, rantID: Int, vote: Int) async -> (String?, Rant?) {
        return await withCheckedContinuation { continuation in
            self.voteOnRant(token, rantID: rantID, vote: vote) { error, updatedRant in
                continuation.resume(returning: (error, updatedRant))
            }
        }
    }
    
    /// Vote on a comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to vote on.
    /// - parameter vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    /// - returns: A tuple that contains an error message in a ``String`` and the updated comment as a ``Comment``. If the request was successful, the `String` in the tuple will contain `nil`, and the ``Comment`` in the tuple will hold the target comment with updated information. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the ``Comment`` in the tuple will contain `nil`.
    public func voteOnComment(_ token: UserCredentials?, commentID id: Int, vote: Int) async -> (String?, Comment?) {
        return await withCheckedContinuation { continuation in
            self.voteOnComment(token, commentID: id, vote: vote) { error, updatedComment in
                continuation.resume(returning: (error, updatedComment))
            }
        }
    }
    
    /// Updates the summary of the user whose token is used.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter aboutSection: The user's about section.
    /// - parameter skills: The user's list of skills.
    /// - parameter githubLink: The user's GitHub link.
    /// - parameter location: The user's location.
    /// - parameter website: The user's personal website.
    /// - returns: An error message in a ``String``.  If the request was successful, the `String?` will contain `nil`. If the request was unsuccessful, the `String?` will hold an error message.
    public func editProfileDetails(_ token: UserCredentials?, aboutSection: String?, skills: String?, githubLink: String?, location: String?, website: String?) async -> String? {
        return await withCheckedContinuation { continuation in
            self.editProfileDetails(token, aboutSection: aboutSection, skills: skills, githubLink: githubLink, location: location, website: website) { error in
                continuation.resume(returning: error)
            }
        }
    }
    
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Posts a rant to devRant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter postType: The type of post.
    /// - parameter content: The text content of the post.
    /// - parameter tags: The post's associated tags.
    /// - parameter image: An image to attach to the post.
    /// - returns: A tuple that contains an error message in a ``String`` and the ID of the post in an ``Int``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Int?` in the tuple will contain the ID of the post. If the the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Int?` in the tuple will contain `nil`.
    public func postRant(_ token: UserCredentials?, postType: Rant.RantType, content: String, tags: String?, image: UIImage?) async -> (String?, Int?) {
        return await withCheckedContinuation { continuation in
            self.postRant(token, postType: postType, content: content, tags: tags, image: image) { error, rantID in
                continuation.resume(returning: (error, rantID))
            }
        }
    }
    #else
    /// Posts a rant to devRant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter postType: The type of post.
    /// - parameter content: The text content of the post.
    /// - parameter tags: The post's associated tags.
    /// - parameter image: An image to attach to the post.
    /// - returns: A tuple that contains an error message in a ``String`` and the ID of the post in an ``Int``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Int?` in the tuple will contain the ID of the post. If the the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Int?` in the tuple will contain `nil`.
    public func postRant(_ token: UserCredentials?, postType: Rant.RantType, content: String, tags: String?, image: NSImage?) async -> (String?, Int?) {
        return await withCheckedContinuation { continuation in
            self.postRant(token, postType: postType, content: content, tags: tags, image: image) { error, rantID in
                continuation.resume(returning: (error, rantID))
            }
        }
    }
    #endif
    
    /// Deletes a post from devRant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the post or rant to be deleted.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If he request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func deleteRant(_ token: UserCredentials?, rantID: Int) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.deleteRant(token, rantID: rantID) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    
    /// Marks a rant as a favorite.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the post or rant to be marked as favorite.
    /// - returns: A tuple that contains an error in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful. the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func favoriteRant(_ token: UserCredentials?, rantID: Int) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.favoriteRant(token, rantID: rantID) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    
    /// Unmarks a rant as a favorite.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the post or rant to be unmarked as favorite.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful. the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func unfavoriteRant(_ token: UserCredentials?, rantID: Int) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.unfavoriteRant(token, rantID: rantID) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Edits a posted rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to be edited.
    /// - parameter postType: The new type of the post.
    /// - parameter content: The new text content of the post.
    /// - parameter tags: The post's new associated tags.
    /// - parameter image: A new image to attach to the post.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func editRant(_ token: UserCredentials?, rantID: Int, postType: Rant.RantType, content: String, tags: String?, image: UIImage?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.editRant(token, rantID: rantID, postType: postType, content: content, tags: tags, image: image) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    #else
    /// Edits a posted rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to be edited.
    /// - parameter postType: The new type of the post.
    /// - parameter content: The new text content of the post.
    /// - parameter tags: The post's new associated tags.
    /// - parameter image: A new image to attach to the post.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func editRant(_ token: UserCredentials?, rantID: Int, postType: Rant.RantType, content: String, tags: String?, image: NSImage?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.editRant(token, rantID: rantID, postType: postType, content: content, tags: tags, image: image) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    #endif
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Posts a comment under a specific rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to post a comment under.
    /// - parameter content: The text content of the comment.
    /// - parameter image: An image to attach to the comment.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func postComment(_ token: UserCredentials?, rantID: Int, content: String, image: UIImage?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.postComment(token, rantID: rantID, content: content, image: image) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    #else
    /// Posts a comment under a specific rant.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter rantID: The ID of the rant to post a comment under.
    /// - parameter content: The text content of the comment.
    /// - parameter image: An image to attach to the comment.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func postComment(_ token: UserCredentials?, rantID: Int, content: String, image: NSImage?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.postComment(token, rantID: rantID, content: content, image: image) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    #endif
    
    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Edits a posted comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to be edited.
    /// - parameter content: The new text content of the comment.
    /// - parameter image: A new image to attach to the comment.
    /// - parameter completionHandler: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func editComment(_ token: UserCredentials?, commentID: Int, content: String, image: UIImage?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.editComment(token, commentID: commentID, content: content, image: image) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    #else
    /// Edits a posted comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to be edited.
    /// - parameter content: The new text content of the comment.
    /// - parameter image: A new image to attach to the comment.
    /// - parameter completionHandler: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func editComment(_ token: UserCredentials?, commentID: Int, content: String, image: NSImage?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.editComment(token, commentID: commentID, content: content, image: image) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    #endif
    
    /// Deletes an existing comment.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter commentID: The ID of the comment to be deleted.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func deleteComment(_ token: UserCredentials?, commentID: Int) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.deleteComment(token, commentID: commentID) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    
    /// Updates the avatar image for the given user.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - parameter fullImageID: The ID of the new avatar image (a file name with the extension of .png).
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool`` If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func confirmAvatarCustomization(_ token: UserCredentials?, fullImageID: String) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.confirmAvatarCustomization(token, fullImageID: fullImageID) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    
    /// Marks all unread notifications as read.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    /// - returns: A tuple that contains an error message in a ``String`` and whether or not the request succeeded in a ``Bool``. If the request was successful, the `String?` in the tuple will contain `nil`, and the `Bool` in the tuple will contain `true`. If the request was unsuccessful, the `String?` in the tuple will contain an error message, and the `Bool` in the tuple will contain `false`.
    public func clearNotifications(_ token: UserCredentials?) async -> (String?, Bool) {
        return await withCheckedContinuation { continuation in
            self.clearNotifications(token) { error, success in
                continuation.resume(returning: (error, success))
            }
        }
    }
    
    // MARK: - Miscellaneous
    
    private func createBody(parameters: [String: String],
                            boundary: String,
                            data: Data?) -> Data {
        var body = Data()
        
        let boundaryPrefix = "--\(boundary)\r\n"
        
        for (key, value) in parameters {
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        
        if data != nil {
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpeg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(data!)
            body.appendString("\r\n")
        }
        
        body.appendString("--".appending(boundary.appending("--")))
        
        return body
    }
    
    #if os(macOS)
    func jpegData(from image: NSImage) -> Data {
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let jpegData = bitmapRep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [:])!
        return jpegData
    }
    #endif
}

private extension Data {
    mutating func appendString(_ string: String) {
        let data = string.data(using: .utf8, allowLossyConversion: false)
        append(data!)
    }
}
