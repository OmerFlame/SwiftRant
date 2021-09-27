import Foundation

public class SwiftRant {
    private static let baseURL = "https://devrant.com/api"
    
    /// Returns an auth token if the username and password are both correct.
    ///
    /// - Parameter username: The username of the user attempting to log in.
    /// - Parameter password: The password of the user attempting to log in.
    /// - Parameter shouldUseUserDefaults: If set to `true`, the method will save all token info, including the username and password in User Defaults, for use later. If set to `false`, the method will skip saving to User Defaults.
    /// - Parameter completionHandler: an escaping method that takes in a `String` parameter and a ``UserCredentials`` parameter.
    ///
    /// If the authentication is successful, the ``UserCredentials`` parameter will hold the actual auth token info, while the `String` is `nil`. If the authentication is unsuccessful, then the `String` will hold an error message, while the ``UserCredentials`` will be `nil`.
    ///
    /// If you called this method while setting `shouldUseUserDefaults` to `true`, the username will be stored in the User Defaults under the ID `DRUsername`, the password under `DRPassword`, and the result ``UserCredentials`` under `DRToken`.
    ///
    /// An example to accessing this info would look like this:
    /// ```
    ///let token = (UserDefaults.standard.value(forKey: "DRToken") as? UserCredentials)
    ///
    ///print("User ID: \(token!.authToken.userID)"
    /// ```
    public static func logIn(username: String, password: String, shouldUseUserDefaults: Bool, completionHandler: @escaping ((String?, UserCredentials?) -> Void)) {
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
                        UserDefaults.standard.encodeAndSet(token, forKey: "DRToken")
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
                    
                    if shouldUseUserDefaults {
                        //UserDefaults.standard.set(token!.authToken.userID, forKey: "DRUserID")
                        //UserDefaults.standard.set(token!.authToken.tokenID, forKey: "DRTokenID")
                        //UserDefaults.standard.set(token!.authToken.tokenKey, forKey: "DRTokenKey")
                        //UserDefaults.standard.set(token!.authToken.expireTime, forKey: "DRTokenExpireTime")
                        
                        //UserDefaults.standard.encodeAndSet(token!, forKey: "DRToken")
                        
                        UserDefaults.standard.encodeAndSet(token, forKey: "DRToken")
                        
                        UserDefaults.standard.set(username, forKey: "DRUsername")
                        UserDefaults.standard.set(password, forKey: "DRPassword")
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
    /// - parameter shouldUseUserDefaults: if set to `true`, the method will attempt getting the auth token stored inside the app's User Defaults. **Note:** if set to `true`, set the `token` parameter to `nil`.
    /// - parameter token: The user's token. set to `nil` if the parameter `shouldUseUserDefaults` is set to `true`.
    /// - parameter skip: How many rants to skip before loading. Used for pagination/infinite scroll.
    /// - parameter prevSet: If you have fetched a rant feed before and `shouldUseUserDefaults` is `false`, set this to  the ``RantFeed/set`` you got in the last fetch.
    /// - parameter completionHandler: If the fetch is successful, the ``RantFeed`` parameter will hold the actual auth token info, while the `String` is `nil`. If the fetch is unsuccessful, then the `String` will hold an error message, while the ``RantFeed`` will be `nil`.
    public static func getRantFeed(shouldUseUserDefaults: Bool, token: UserCredentials?, skip: Int, prevSet: String?, completionHandler: @escaping ((String?, RantFeed?) -> Void)) {
        if !shouldUseUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = UserDefaults.standard.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: UserDefaults.standard.string(forKey: "DRUsername")!, password: UserDefaults.standard.string(forKey: "DRPassword")!, shouldUseUserDefaults: true) { error, _ in
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
            if shouldUseUserDefaults {
                if UserDefaults.standard.string(forKey: "DRLastSet") != nil {
                    let currentToken: UserCredentials? = UserDefaults.standard.decode(forKey: "DRToken")
                    return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo&prev_set=\(String(UserDefaults.standard.string(forKey: "DRLastSet")!))&app=3&plat=1&nari=1&user_id=\(String(currentToken!.authToken.userID))&token_id=\(String(currentToken!.authToken.tokenID))&token_key=\(currentToken!.authToken.tokenKey)")!
                } else {
                    let currentToken: UserCredentials? = UserDefaults.standard.decode(forKey: "DRToken")
                    return URL(string: baseURL + "/devrant/rants?limit=20&skip=\(String(skip))&sort=algo&app=3&plat=1&nari=1&user_id=\(String(currentToken!.authToken.userID))&token_id=\(String(currentToken!.authToken.tokenID))&token_key=\(currentToken!.authToken.tokenKey)")!
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
                    
                    if shouldUseUserDefaults {
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
    
    public static func getNotificationFeed(shouldUseUserDefaults: Bool, token: UserCredentials?, lastCheckTime: Int?, shouldGetNewNotifs: Bool, category: Notifications.Categories, completionHandler: @escaping ((String?, Notifications?) -> Void)) {
        if !shouldUseUserDefaults {
            guard token != nil else {
                fatalError("No token was specified!")
            }
        } else {
            let storedToken: UserCredentials? = UserDefaults.standard.decode(forKey: "DRToken")
            
            if Double(storedToken!.authToken.expireTime) - Double(Date().timeIntervalSince1970) <= 0 {
                let loginSemaphore = DispatchSemaphore(value: 0)
                
                var errorMessage: String?
                
                logIn(username: UserDefaults.standard.string(forKey: "DRUsername")!, password: UserDefaults.standard.string(forKey: "DRPassword")!, shouldUseUserDefaults: true) { error, _ in
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
        
        var resourceURL = URL(string: baseURL + "/users/me/notif-feed\(category == .all ? "" : "/\(category.rawValue)")")!
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        let data = string.data(using: .utf8, allowLossyConversion: false)
        append(data!)
    }
}
