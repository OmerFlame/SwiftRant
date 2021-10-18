import Foundation
import SwiftKeychainWrapper

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
    static let shared = SwiftRant()
    
    private let shouldUseKeychainAndUserDefaults: Bool
    
    private let baseURL = "https://devrant.com/api"
    
    private let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
    
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
                        
                        var didSucceed = self.keychainWrapper.encodeAndSet(token, forKey: "DRToken", withAccessibility: .whenUnlockedThisDeviceOnly)
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
    /// - parameter completionHandler: A function that will run after the fetch was completed. If the fetch is successful, the ``RantFeed`` parameter will hold the actual auth token info, while the `String` is `nil`. If the fetch is unsuccessful, then the `String` will hold an error message, while the ``RantFeed`` will be `nil`.
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
    /// - parameter completionHandler: A function that will run after the fetch was completed. If the fetch was successful, the ``Notifications`` parameter will hold the actual notification info, while the `String` is `nil`. If the fetch was unsuccessful, then the `String` will hold an error message, while the ``Notifications`` will be `nil`.
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
    /// - parameter completionHandler: A function that will run after the fetch was completed. If the fetch was successful, the ``Rant`` parameter will hold the actual rant info, the ``Comment`` array will hold all the comments attached to the ``Rant`` and the `String` will be `nil`. If the fetch was unsuccessful, then the `String` will hold an error message, and the ``Rant`` and ``Comment`` will both be `nil`.
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
                
                let rantResponse = try? decoder.decode(Rant.RantResponse.self, from: data)
                
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
}

private extension Data {
    mutating func appendString(_ string: String) {
        let data = string.data(using: .utf8, allowLossyConversion: false)
        append(data!)
    }
}
