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
    public var comments: [Comment]
    
    private enum CodingKeys: String, CodingKey {
        case rant, comments
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        rant = try values.decode(Rant.self, forKey: .rant)
        
        do {
            comments = try values.decode([Comment].self, forKey: .comments)
        } catch {
            comments = []
        }
        
        for idx in 0..<comments.count {
            comments[idx].precalculateLinkRanges()
        }
    }
}

public protocol SwiftRantErrorProtocol: Error {
    var message: String { get }
}

public struct SwiftRantError: SwiftRantErrorProtocol {
    public var message: String
}

fileprivate struct CommentResponse: Decodable {
    public let comment: Comment?
}

fileprivate struct ProfileResponse: Decodable {
    let profile: Profile?
    let subscribed: Int?
}

public class SwiftRant {
    
    /// Initializes the SwiftRant library.
    ///
    /// - Parameter shouldUseKeychainAndUserDefaults: Whether or not the library should store devRant access tokens and the user's personal username and password in the Keychain and small caches in User Defaults. If no value is given, Keychain and User Defaults for the instance are automatically enabled.
    /// - Returns: a new SwiftRant class instance.
    public init(shouldUseKeychainAndUserDefaults: Bool = true) {
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
    /// - Parameters:
    ///    - username: The username of the user attempting to log in.
    ///    - password: The password of the user attempting to log in.
    ///    - completionHandler: The completion handler to call when the authentication process is complete.
    ///
    ///        The completion handler takes in a single `result` parameter which will contain the result of the request (``UserCredentials`` with the auth token info if successful, ``SwiftRantError`` if failed).
    public func logIn(username: String, password: String, completionHandler: @escaping (Result<UserCredentials, SwiftRantError>) -> Void) {
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
                                    completionHandler(.failure(SwiftRantError(message: error)))
                                    return
                                }
                                
                                completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                                return
                            }
                            
                            completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                            return
                        }
                        
                        completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
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
                    
                    completionHandler(.success(token!))
                    return
                }
                
                completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                return
            }
            
            completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Removes the user credentials login token from the keychain.
    public func logOut() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        
        keychainWrapper.removeAllKeys()
        SecItemDelete(query as CFDictionary)
    }
    
    /// Gets a personalized rant feed for the user.
    ///
    /// - Parameters:
    ///    - token: The user's token. set to `nil`if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - sort: What kind of feed.
    ///    - skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    ///    - prevSet: The ``RantFeed/set`` you got in the last fetch. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults, the SwiftRant instance will get the set from the last fetch from User Defaults.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``RantFeed`` with the personalized rant feed if successful, ``SwiftRantError`` if failed).
    public func getRantFeed(token: UserCredentials?, sort: RantFeed.Sort = .algorithm, skip: Int, prevSet: String?, completionHandler: @escaping (Result<RantFeed, SwiftRantError>) -> Void) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let currentToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
        
        let sortAndRangeUrlPart: String
        switch sort {
        case .algorithm:
            sortAndRangeUrlPart = "&sort=algo"
        case .recent:
            sortAndRangeUrlPart = "&sort=recent"
        case .top(range: let range):
            switch range {
            case .day:
                sortAndRangeUrlPart = "&sort=top&range=day"
            case .week:
                sortAndRangeUrlPart = "&sort=top&range=week"
            case .month:
                sortAndRangeUrlPart = "&sort=top&range=month"
            case .all:
                sortAndRangeUrlPart = "&sort=top&range=all"
            }
        }
        
        var resourceURL: URL!
        
        if shouldUseKeychainAndUserDefaults {
            guard let currentToken = currentToken else {
                completionHandler(.failure(SwiftRantError(message: "Failed to get devRant access token from Keychain while building request URL!")))
                return
            }
            
            if UserDefaults.standard.string(forKey: "DRLastSet") != nil {
                resourceURL = URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))\(sortAndRangeUrlPart)&prev_set=\(String(UserDefaults.standard.string(forKey: "DRLastSet")!))&app=3&plat=1&nari=1&user_id=\(String(currentToken.authToken.userID))&token_id=\(String(currentToken.authToken.tokenID))&token_key=\(currentToken.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
            } else {
                resourceURL = URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))\(sortAndRangeUrlPart)&app=3&plat=1&nari=1&user_id=\(String(currentToken.authToken.userID))&token_id=\(String(currentToken.authToken.tokenID))&token_key=\(currentToken.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
            }
        } else {
            resourceURL = URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))\(sortAndRangeUrlPart)\(prevSet != nil ? "&prev_set=\(prevSet!)" : "")&app=3&plat=1&nari=1&user_id=\(String(token!.authToken.userID))&token_id=\(String(token!.authToken.tokenID))&token_key=\(token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        }
        
        
        
        /*var resourceURL: URL {
            if shouldUseKeychainAndUserDefaults {
                if UserDefaults.standard.string(forKey: "DRLastSet") != nil {
                    
                    return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo&prev_set=\(String(UserDefaults.standard.string(forKey: "DRLastSet")!))&app=3&plat=1&nari=1&user_id=\(String(currentToken.authToken.userID))&token_id=\(String(currentToken.authToken.tokenID))&token_key=\(currentToken.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                } else {
                    return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo&app=3&plat=1&nari=1&user_id=\(String(currentToken.authToken.userID))&token_id=\(String(currentToken.authToken.tokenID))&token_key=\(currentToken.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
                }
            } else {
                return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo\(prevSet != nil ? "prev_set=\(prevSet!)" : "")&app=3&plat=1&nari=1&user_id=\(String(token!.authToken.userID))&token_id=\(String(token!.authToken.tokenID))&token_key=\(token!.authToken.tokenKey)")!
            }
        }*/
        
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
                                    completionHandler(.failure(SwiftRantError(message: error)))
                                    return
                                }
                                
                                completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                                return
                            }
                            
                            completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                            return
                        }
                        
                        completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                        return
                    }
                    
                    if self.shouldUseKeychainAndUserDefaults {
                        UserDefaults.standard.set(rantFeed!.set, forKey: "DRLastSet")
                    }
                    
                    completionHandler(.success(rantFeed!))
                    return
                } else {
                    completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                    return
                }
            } else {
                completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                return
            }
        }.resume()
    }
    
    /// Get a specific week's Weekly Rant Week rant feed.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - limit: The maximum amount of rants to provide in the response. Default is 20.
    ///    - skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    ///    - week: The week number to fetch. This variable is optional. If you want to get the latest week's rants, skip this variable in the call.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``RantFeed`` with the Weekly Rant Week feed if successful, ``SwiftRantError`` if failed).
    public func getWeeklyRants(token: UserCredentials?, limit: Int = 20, skip: Int, week: Int = -1, completionHandler: @escaping (Result<RantFeed, SwiftRantError>) -> Void) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/weekly-rants?limit=\(limit)&skip=\(skip)&sort=algo\(week != -1 ? "&week=\(week)" : "")&hide_reposts=0&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let rantFeed = try? decoder.decode(RantFeed.self, from: data)
                
                if rantFeed == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data)
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                } else {
                    completionHandler(.success(rantFeed!))
                    return
                }
            }
            
            completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Get the list of Weekly Rant weeks.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``WeeklyList`` with the list of weeks if successful, ``SwiftRantError`` if failed).
    public func getWeekList(token: UserCredentials?, completionHandler: @escaping (Result<WeeklyList, SwiftRantError>) -> Void) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/weekly-list?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let weekList = try? decoder.decode(WeeklyList.self, from: data)
                
                if weekList == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data)
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String:Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    } else {
                        completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                        return
                    }
                } else {
                    completionHandler(.success(weekList!))
                    return
                }
            }
            
            completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Get the notification feed for the current user.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - lastCheckTime: The last Unix Timestamp at which the notifications were last checked at. Set to `nil` is the SwiftRant instance was configured to use Keychain and User Defaults, or if you set `shouldGetNewNotifs` to `false`.
    ///    - shouldGetNewNotifs: Whether or not the function should retrieve the latest notifications since the Unix Timestamp stored in User Defaults or `lastCheckTime`.
    ///
    ///         If set to `false` and the SwiftRant instance was configured to use the Keychain and User Defaults, set `lastCheckTime` to `nil`.
    ///
    ///         If set to `true` and the SwiftRant instance was NOT configured to use the Keychain and User Defaults, set `lastCheckTime` to the last Unix Timestamp at which the notifications were fetched last time.
    ///    - category: The category of notifications that the function should return.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``Notifications`` with the notification list info if successful, ``SwiftRantError`` if failed).
    public func getNotificationFeed(token: UserCredentials?, lastCheckTime: Int?, shouldGetNewNotifs: Bool, category: Notifications.Categories, completionHandler: @escaping (Result<Notifications, SwiftRantError>) -> Void) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let categoryUrlPart: String
        switch category {
        case .all:
            categoryUrlPart = ""
        default:
            categoryUrlPart = "/\(category.rawValue)"
        }
        
        let resourceURL = URL(string: baseURL + "/users/me/notif-feed\(categoryUrlPart)?last_time=\(shouldUseKeychainAndUserDefaults ? (shouldGetNewNotifs ? UserDefaults.standard.integer(forKey: "DRLastNotifCheckTime") : 0) : (shouldGetNewNotifs ? lastCheckTime! : 0))&ext_prof=1&app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
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
                                completionHandler(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                        
                        completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                        return
                    }
                    
                    completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                    return
                } else {
                    completionHandler(.success(notificationResult!.data))
                    return
                }
            }
            
            completionHandler(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Get a specific rant with a given ID.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - id: The ID of the rant to fetch.
    ///    - lastCommentID: If set to a valid comment ID that exists in the rant's comments, the function will get all the comments that were posted after the comment with the given ID.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request.
    ///
    ///         If the fetch was successful, then the result will contain a `Tuple` of a single ``Rant`` with the rant info and a ``Comment`` array with all the comments attached to the rant.
    ///
    ///         If the fetch was a failure, then the result will contain a ``SwiftRantError``.
    public func getRantFromID(token: UserCredentials?, id: Int, lastCommentID: Int?, completionHandler: ((Result<(Rant, [Comment]), SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                    
                    completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                    return
                } else {
                    completionHandler?(.success((rantResponse!.rant, rantResponse!.comments)))
                    return
                }
            }
        }.resume()
    }
    
    /// Gets a single comment by ID.
    ///
    /// - Parameters:
    ///    - id: The ID of the comment to fetch.
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``Comment`` with the fetched comment if successful, ``SwiftRantError`` if failed).
    public func getCommentFromID(_ id: Int, token: UserCredentials?, completionHandler: ((Result<Comment, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(.success(comment!.comment!))
                    return
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Gets a personal rant feed based on the user's subscriptions and the activity of the users the user has subscribed to.
    ///
    /// - Parameters:
    ///    - token: The user's token. set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - lastEndCursor: The ``SubscribedFeed/PageInfo-swift.struct/endCursor`` you got from the last fetch. Set to `nil` if the SwiftRant instance was configured to use the Keychain and UserDefaults. the SwiftRant instance will get the last end cursor from the last fetch from User Defaults.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``SubscribedFeed`` with the fetched Subscribed feed if successful, ``SwiftRantError`` if failed).
    public func getSubscribedFeed(_ token: UserCredentials?, lastEndCursor: String?, completionHandler: ((Result<SubscribedFeed, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/me/subscribed-feed?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)\(shouldUseKeychainAndUserDefaults ? (UserDefaults.standard.string(forKey: "DRLastEndCursor") != nil ? "&activity_before=\(UserDefaults.standard.string(forKey: "DRLastEndCursor")!)" : "") : (lastEndCursor != nil ? "&activity_before=\(lastEndCursor!)" : ""))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "GET"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                let decoder = JSONDecoder()
                
                let subscribedFeed = try? decoder.decode(SubscribedFeed.self, from: data)
                
                if subscribedFeed == nil {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String: Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                } else {
                    UserDefaults.standard.set(subscribedFeed!.pageInfo.endCursor, forKey: "DRLastEndCursor")
                    
                    completionHandler?(.success(subscribedFeed!))
                    return
                }
                
                completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                return
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Retrieves the ID of a user with a specified username
    ///
    /// - Parameters:
    ///    - username: The username to get the ID for.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Int` with the ID of the given username if successful, ``SwiftRantError`` if failed).
    public func getUserID(of username: String, completionHandler: ((Result<Int, SwiftRantError>) -> Void)?) {
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
                                completionHandler?(.success(jObject["user_id"] as! Int))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: "User doesn't exist!")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    /// Get a user's profile data.
    /// - Parameters:
    ///    - id: The ID of the user whose data will be fetched.
    ///    - token: The user's token. set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - userContentType: The type of content created by the user to be fetched.
    ///    - skip: The amount of content to be skipped on. Useful for pagination/infinite scroll.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``Profile`` with the fetched profile information if successful, ``SwiftRantError`` if failed).
    public func getProfileFromID(_ id: Int, token: UserCredentials?, userContentType: Profile.ProfileContentTypes, skip: Int, completionHandler: ((Result<Profile, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                } else {
                    var profile = profileResponse!.profile!
                    profile.subscribed = profileResponse!.subscribed == 1
                    completionHandler?(.success(profile))
                    return
                }
                
                completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                return
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Retrieves a set of avatar customization options listed under a specific type of customization.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - type: The type of customization to retrieve the options for.
    ///    - subType: The sub-type of the type of customization to retrieve the options for. Not all customization types have a subtype, so this parameter is optional. If the type does not contain a sub-type, set `subOption` to `nil`.
    ///    - currentImageID: The ID of the current avatar of the user.
    ///    - shouldGetPossibleOptions: Whether or not the server should return the entire list of the different types and sub-types of customizations for a devRant avatar, alongside the query.
    ///    - completionHandler: The completion handler to call when the fetch is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``AvatarCustomizationResults`` with the query's results if successful, ``SwiftRantError`` if failed).
    public func getAvatarCustomizationOptions(_ token: UserCredentials?, type: String, subType: Int?, currentImageID: String, shouldGetPossibleOptions: Bool, completionHandler: ((Result<AvatarCustomizationResults, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                    completionHandler?(.success(results!))
                    return
                } else {
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
                    
                    if let jsonObject = jsonObject {
                        if let jObject = jsonObject as? [String: Any] {
                            if let error = jObject["error"] as? String {
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    // MARK: - Data Senders
    
    /// Vote on a rant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the rant to vote on.
    ///    - vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``Rant`` with the updated rant data if successful, ``SwiftRantError`` if failed).
    public func voteOnRant(_ token: UserCredentials?, rantID id: Int, vote: VoteState, completionHandler: ((Result<Rant, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/rants/\(id)/vote".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&vote=\(vote.rawValue)".data(using: .utf8)
        
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
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(.success(updatedRantInfo!.rant))
                    return
                }
                
                completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                return
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Vote on a comment.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - commentID: The ID of the comment to vote on.
    ///    - vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (``Comment`` with the updated comment data if successful, ``SwiftRantError`` if failed).
    public func voteOnComment(_ token: UserCredentials?, commentID id: Int, vote: VoteState, completionHandler: ((Result<Comment, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/comments/\(id)/vote".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&vote=\(vote.rawValue)".data(using: .utf8)
        
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
                                completionHandler?(.failure(SwiftRantError(message: error)))
                                return
                            }
                        }
                    }
                } else {
                    completionHandler?(.success(updatedCommentInfo!.comment!))
                    return
                }
                
                completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
                return
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Updates the summary of the user whose token is used.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - aboutSection: The user's about section.
    ///    - skills: The user's list of skills.
    ///    - githubLink: The user's GitHub link.
    ///    - location: The user's location.
    ///    - website: The user's personal website.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func editProfileDetails(_ token: UserCredentials?, aboutSection: String?, skills: String?, githubLink: String?, location: String?, website: String?, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                if let error = jObject["error"] as? String {
                                    completionHandler?(.failure(SwiftRantError(message: error)))
                                    return
                                }
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    /// Posts a rant to devRant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - postType: The type of post.
    ///    - content: The text content of the post.
    ///    - tags: The post's associated tags.
    ///    - image: An image to attach to the post.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Int` with the ID of the rant if successful, ``SwiftRantError`` if failed).
    public func postRant(_ token: UserCredentials?, postType: Rant.RantType, content: String, tags: String?, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg], completionHandler: ((Result<Int, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: baseURL + "/devrant/rants".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if let image {
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
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: imageConversion.convert(image))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ("token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&tags=\(tags ?? "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&type=\(postType.rawValue)&app=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! + "&rant=\(content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)").data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(.success(jObject["rant_id"] as! Int))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error as occurred.")))
            return
        }.resume()
    }
    
    /// Deletes a post from devRant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the post or rant to be deleted.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func deleteRant(_ token: UserCredentials?, rantID: Int, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Marks a rant as a favorite.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the post or rant to be marked as favorite.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func favoriteRant(_ token: UserCredentials?, rantID: Int, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    /// Unmarks a rant as a favorite.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the post or rant to be unmarked as favorite.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func unfavoriteRant(_ token: UserCredentials?, rantID: Int, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    /// Edits a posted rant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the rant to be edited.
    ///    - postType: The new type of the post.
    ///    - content: The new text content of the post.
    ///    - tags: The post's new associated tags.
    ///    - image: A new image to attach to the post.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func editRant(_ token: UserCredentials?, rantID: Int, postType: Rant.RantType, content: String, tags: String?, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg], completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if let image {
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
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: imageConversion.convert(image))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ("token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&tags=\(tags ?? "")&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&type=\(postType.rawValue)&app=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! + "&rant=\(content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)").data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Posts a comment under a specific rant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the rant to post a comment under.
    ///    - content: The text content of the comment.
    ///    - image: An image to attach to the comment.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func postComment(_ token: UserCredentials?, rantID: Int, content: String, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg], completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/devrant/rants/\(rantID)/comments".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        
        if let image {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "comment": content,
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: imageConversion.convert(image))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = ("app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! + "&comment=\(content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)").data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Edits a posted comment.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - commentID: The ID of the comment to be edited.
    ///    - content: The new text content of the comment.
    ///    - image: A new image to attach to the comment.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func editComment(_ token: UserCredentials?, commentID: Int, content: String, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg], completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: "\(baseURL)/comments/\(commentID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "POST"
        
        if let image {
            let boundary = UUID().uuidString
            
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            let paramList: [String: String] = [
                "app": "3",
                "comment": content,
                "token_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID),
                "token_key": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey),
                "user_id": String(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)
            ]
            
            request.httpBody = createBody(parameters: paramList, boundary: boundary, data: imageConversion.convert(image))
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ("app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! + "&comment=\(content.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)").data(using: .utf8)
        }
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Deletes an existing comment.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - commentID: The ID of the comment to be deleted.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func deleteComment(_ token: UserCredentials?, commentID: Int, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Updates the avatar image for the given user.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - fullImageID: The ID of the new avatar image (a file name with the extension of .png).
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func confirmAvatarCustomization(_ token: UserCredentials?, fullImageID: String, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
            return
        }.resume()
    }
    
    /// Marks all unread notifications as read.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func clearNotifications(_ token: UserCredentials?, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    /// Subscribes to a user with the specified ID.
    ///
    /// - Parameters:
    ///    - token: The user's token. set to `nil`if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - userID: The ID of the user to subscribe to.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func subscribeToUser(_ token: UserCredentials?, userID: Int, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: (baseURL + "/users/\(userID)/subscribe").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
        var request = URLRequest(url: resourceURL)
        
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = "app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.data(using: .utf8)
        
        let session = URLSession(configuration: .default)
        
        session.dataTask(with: request) { data, response, error in
            if let data = data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let jObject = jsonObject as? [String: Any] {
                        if let success = jObject["success"] as? Bool {
                            if success {
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    /// Unsubscribes from a user with the specified ID.
    ///
    /// - Parameters:
    ///    - token: The user's token. set to `nil`if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - userID: The ID of the user to unsubscribe to.
    ///    - completionHandler: The completion handler to call when the request is complete.
    ///
    ///         The completion handler takes in a single `result` parameter which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func unsubscribeFromUser(_ token: UserCredentials?, userID: Int, completionHandler: ((Result<Void, SwiftRantError>) -> Void)?) {
        if !shouldUseKeychainAndUserDefaults {
            guard token != nil else {
                //fatalError("No token was specified!")
                
                completionHandler?(.failure(SwiftRantError(message: "No devRant access token was specified!")))
                return
            }
        } else {
            let storedToken: UserCredentials? = self.keychainWrapper.decode(forKey: "DRToken")
            
            guard let storedToken = storedToken else {
                completionHandler?(.failure(SwiftRantError(message: "Could not find devRant access token in Keychain during token validation!")))
                return
            }
            
            if Double(storedToken.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                guard let usernameFromKeychain = usernameFromKeychain, let passwordFromKeychain = passwordFromKeychain else {
                    completionHandler?(.failure(SwiftRantError(message: "Could not find devRant username/password in Keychain before renewing the token!")))
                    return
                }
                
                logIn(username: usernameFromKeychain, password: passwordFromKeychain) { result in
                    if case .failure(let failure) = result {
                        errorMessage = failure.message
                    }/* {
                        
                    }*/
                    
                    loginSemaphore.signal()
                }
                
                loginSemaphore.wait()
                
                if errorMessage != nil {
                    completionHandler?(.failure(SwiftRantError(message: errorMessage!)))
                }
            }
        }
        
        let resourceURL = URL(string: (baseURL + "/users/\(userID)/subscribe?app=3&user_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.userID : token!.authToken.userID)&token_id=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenID : token!.authToken.tokenID)&token_key=\(shouldUseKeychainAndUserDefaults ? tokenFromKeychain!.authToken.tokenKey : token!.authToken.tokenKey)").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
        
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
                                completionHandler?(.success(()))
                                return
                            } else {
                                completionHandler?(.failure(SwiftRantError(message: jObject["error"] as? String ?? "An unknown error has occurred.")))
                                return
                            }
                        }
                    }
                }
            }
            
            completionHandler?(.failure(SwiftRantError(message: "An unknown error has occurred.")))
        }.resume()
    }
    
    // MARK: - Async Wrappers
    
    /// Returns an auth token if the username and password are both correct.
    ///
    /// - Parameters:
    ///    - username: The username of the user attempting to log in.
    ///    - password: The password of the user attempting to log in.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``UserCredentials`` with the auth token info if successful, ``SwiftRantError`` if failed).
    ///
    /// If you called this method while initializing ``SwiftRant`` while setting `shouldUseKeychainAndUserDefaults` with `true`, the username, password and access token will be stored in the Keychain securely.
    public func logIn(username: String, password: String) async -> Result<UserCredentials, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.logIn(username: username, password: password) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Gets a personalized rant feed for the user.
    ///
    /// - Parameters:
    ///    - token: The user's token. set to `nil`if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - sort: What kind of feed.
    ///    - skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    ///    - prevSet: The ``RantFeed/set`` you got in the last fetch. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults, the SwiftRant instance will get the set from the last fetch from User Defaults.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``RantFeed`` with the personalized rant feed if successful, ``SwiftRantError`` if failed).
    public func getRantFeed(token: UserCredentials?, sort: RantFeed.Sort = .algorithm, skip: Int, prevSet: String?) async -> Result<RantFeed, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getRantFeed(token: token, sort: sort, skip: skip, prevSet: prevSet) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Get a specific week's Weekly Rant Week rant feed.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - limit: The maximum amount of rants to provide in the response. Default is 20.
    ///    - skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    ///    - week: The week number to fetch.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``RantFeed`` with the Weekly Rant Week feed if successful, ``SwiftRantError`` if failed).
    public func getWeeklyRants(token: UserCredentials?, limit: Int = 20, skip: Int, week: Int) async -> Result<RantFeed, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getWeeklyRants(token: token, limit: limit, skip: skip, week: week) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Get the list of Weekly Rant weeks.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``WeeklyList`` with the list of weeks if successful, ``SwiftRantError`` if failed).
    public func getWeekList(token: UserCredentials?) async -> Result<WeeklyList, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getWeekList(token: token) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Get the notification feed for the current user.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - lastCheckTime: The last Unix Timestamp at which the notifications were last checked at. Set to `nil` is the SwiftRant instance was configured to use Keychain and User Defaults, or if you set `shouldGetNewNotifs` to `false`.
    ///    - shouldGetNewNotifs: Whether or not the function should retrieve the latest notifications since the Unix Timestamp stored in User Defaults or `lastCheckTime`.
    ///
    ///         If set to `false` and the SwiftRant instance was configured to use the Keychain and User Defaults, set `lastCheckTime` to `nil`.
    ///
    ///         If set to `true` and the SwiftRant instance was NOT configured to use the Keychain and User Defaults, set `lastCheckTime` to the last Unix Timestamp at which the notifications were fetched last time.
    ///    - category: The category of notifications that the function should return.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``Notifications`` with the notification list info if successful, ``SwiftRantError`` if failed).
    public func getNotificationFeed(token: UserCredentials?, lastCheckTime: Int?, shouldGetNewNotifs: Bool, category: Notifications.Categories) async -> Result<Notifications, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getNotificationFeed(token: token, lastCheckTime: lastCheckTime, shouldGetNewNotifs: shouldGetNewNotifs, category: category) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Get a specific rant with a given ID.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - id: The ID of the rant to fetch.
    ///    - lastCommentID: If set to a valid comment ID that exists in the rant's comments, the function will get all the comments that were posted after the comment with the given ID.
    ///
    /// - returns: A `Result<>` which will contain the result of the request.
    ///
    ///         If the request was successful, then the result will contain a `Tuple` of a single ``Rant`` with the rant info and a ``Comment`` array with all the comments attached to the rant.
    ///
    ///         If the request was a failed, then the result will contain a ``SwiftRantError``.
    public func getRantFromID(token: UserCredentials?, id: Int, lastCommentID: Int?) async -> Result<(Rant, [Comment]), SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getRantFromID(token: token, id: id, lastCommentID: lastCommentID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Gets a single comment by ID.
    ///
    /// - Parameters:
    ///    - id: The ID of the comment to fetch.
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``Comment`` with the fetched comment if successful, ``SwiftRantError`` if failed).
    public func getCommentFromID(_ id: Int, token: UserCredentials?) async -> Result<Comment, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getCommentFromID(id, token: token) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Gets a personal rant feed based on the user's subscriptions and the activity of the users the user has subscribed to.
    ///
    /// - Parameters:
    ///    - token: The user's token. set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - lastEndCursor: The ``SubscribedFeed/PageInfo-swift.struct/endCursor`` you got from the last fetch. Set to `nil` if the SwiftRant instance was configured to use the Keychain and UserDefaults. the SwiftRant instance will get the last end cursor from the last fetch from User Defaults.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``SubscribedFeed`` with the fetched Subscribed feed if successful, ``SwiftRantError`` if failed).
    public func getSubscribedFeed(_ token: UserCredentials?, lastEndCursor: String?) async -> Result<SubscribedFeed, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getSubscribedFeed(token, lastEndCursor: lastEndCursor) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Retrieves the ID of a user with a specified username
    ///
    /// - parameter username: The username to get the ID for.
    /// - returns: A `Result<>` which will contain the result of the request (`Int` with the ID of the given username if successful, ``SwiftRantError`` if failed).
    public func getUserID(of username: String) async -> Result<Int, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getUserID(of: username) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Get a user's profile data.
    ///
    /// - Parameters:
    ///    - id: The ID of the user whose data will be fetched.
    ///    - token: The user's token. set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - userContentType: The type of content created by the user to be fetched.
    ///    - skip: The amount of content to be skipped on. Useful for pagination/infinite scroll.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``Profile`` with the fetched profile information if successful, ``SwiftRantError`` if failed).
    public func getProfileFromID(_ id: Int, token: UserCredentials?, userContentType: Profile.ProfileContentTypes, skip: Int) async -> Result<Profile, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getProfileFromID(id, token: token, userContentType: userContentType, skip: skip) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Retrieves a set of avatar customization options listed under a specific type of customization.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - type: The type of customization to retrieve the options for.
    ///    - subType: The sub-type of the type of customization to retrieve the options for. Not all customization types have a subtype, so this parameter is optional. If the type does not contain a sub-type, set `subOption` to `nil`.
    ///    - currentImageID: The ID of the current avatar of the user.
    ///    - shouldGetPossibleOptions: Whether or not the server should return the entire list of the different types and sub-types of customizations for a devRant avatar, alongside the query.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``AvatarCustomizationResults`` with the query's results if successful, ``SwiftRantError`` if failed).
    public func getAvatarCustomizationOptions(_ token: UserCredentials?, type: String, subType: Int?, currentImageID: String, shouldGetPossibleOptions: Bool) async -> Result<AvatarCustomizationResults, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.getAvatarCustomizationOptions(token, type: type, subType: subType, currentImageID: currentImageID, shouldGetPossibleOptions: shouldGetPossibleOptions) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Vote on a rant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the rant to vote on.
    ///    - vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``Rant`` with the updated rant data if successful, ``SwiftRantError`` if failed).
    public func voteOnRant(_ token: UserCredentials?, rantID: Int, vote: VoteState) async -> Result<Rant, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.voteOnRant(token, rantID: rantID, vote: vote) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Vote on a comment.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - commentID: The ID of the comment to vote on.
    ///    - vote: The vote state. 1 = upvote, 0 = neutral, -1 = downvote.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (``Comment`` with the updated comment data if successful, ``SwiftRantError`` if failed).
    public func voteOnComment(_ token: UserCredentials?, commentID id: Int, vote: VoteState) async -> Result<Comment, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.voteOnComment(token, commentID: id, vote: vote) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Updates the summary of the user whose token is used.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - aboutSection: The user's about section.
    ///    - skills: The user's list of skills.
    ///    - githubLink: The user's GitHub link.
    ///    - location: The user's location.
    ///    - website: The user's personal website.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func editProfileDetails(_ token: UserCredentials?, aboutSection: String?, skills: String?, githubLink: String?, location: String?, website: String?) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.editProfileDetails(token, aboutSection: aboutSection, skills: skills, githubLink: githubLink, location: location, website: website) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    
    /// Posts a rant to devRant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - postType: The type of post.
    ///    - content: The text content of the post.
    ///    - tags: The post's associated tags.
    ///    - image: An image to attach to the post.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Int` with the ID of the rant if successful, ``SwiftRantError`` if failed).
    public func postRant(_ token: UserCredentials?, postType: Rant.RantType, content: String, tags: String?, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg]) async -> Result<Int, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.postRant(token, postType: postType, content: content, tags: tags, image: image, imageConversion: imageConversion) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Deletes a post from devRant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the post or rant to be deleted.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func deleteRant(_ token: UserCredentials?, rantID: Int) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.deleteRant(token, rantID: rantID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Marks a rant as a favorite.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the post or rant to be marked as favorite.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func favoriteRant(_ token: UserCredentials?, rantID: Int) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.favoriteRant(token, rantID: rantID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Unmarks a rant as a favorite.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the post or rant to be unmarked as favorite.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func unfavoriteRant(_ token: UserCredentials?, rantID: Int) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.unfavoriteRant(token, rantID: rantID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Edits a posted rant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the rant to be edited.
    ///    - postType: The new type of the post.
    ///    - content: The new text content of the post.
    ///    - tags: The post's new associated tags.
    ///    - image: A new image to attach to the post.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func editRant(_ token: UserCredentials?, rantID: Int, postType: Rant.RantType, content: String, tags: String?, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg]) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.editRant(token, rantID: rantID, postType: postType, content: content, tags: tags, image: image, imageConversion: imageConversion) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Posts a comment under a specific rant.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - rantID: The ID of the rant to post a comment under.
    ///    - content: The text content of the comment.
    ///    - image: An image to attach to the comment.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func postComment(_ token: UserCredentials?, rantID: Int, content: String, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg]) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.postComment(token, rantID: rantID, content: content, image: image, imageConversion: imageConversion) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Edits a posted comment.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - commentID: The ID of the comment to be edited.
    ///    - content: The new text content of the comment.
    ///    - image: A new image to attach to the comment.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func editComment(_ token: UserCredentials?, commentID: Int, content: String, image: Data?, imageConversion: [ImageDataConverter] = [.unsupportedToJpeg]) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.editComment(token, commentID: commentID, content: content, image: image, imageConversion: imageConversion) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Deletes an existing comment.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - commentID: The ID of the comment to be deleted.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func deleteComment(_ token: UserCredentials?, commentID: Int) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.deleteComment(token, commentID: commentID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Updates the avatar image for the given user.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - fullImageID: The ID of the new avatar image (a file name with the extension of .png).
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func confirmAvatarCustomization(_ token: UserCredentials?, fullImageID: String) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.confirmAvatarCustomization(token, fullImageID: fullImageID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Marks all unread notifications as read.
    ///
    /// - parameter token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func clearNotifications(_ token: UserCredentials?) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.clearNotifications(token) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Subscribes to a user with the specified ID.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - userID: The ID of the user to subscribe to.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func subscribeToUser(_ token: UserCredentials?, userID: Int) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.subscribeToUser(token, userID: userID) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Unsubscribes to a user with the specified ID.
    ///
    /// - Parameters:
    ///    - token: The user's token. Set to `nil` if the SwiftRant instance was configured to use the Keychain and User Defaults.
    ///    - userID: The ID of the user to unsubscribe from.
    ///
    /// - returns: A `Result<>` which will contain the result of the request (`Void` if successful, ``SwiftRantError`` if failed).
    public func unsubscribeFromUser(_ token: UserCredentials?, userID: Int) async -> Result<Void, SwiftRantError> {
        return await withCheckedContinuation { continuation in
            self.subscribeToUser(token, userID: userID) { result in
                continuation.resume(returning: result)
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
}

private extension Data {
    mutating func appendString(_ string: String) {
        let data = string.data(using: .utf8, allowLossyConversion: false)
        append(data!)
    }
}
