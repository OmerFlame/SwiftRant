import XCTest
@testable import SwiftRant
import SwiftKeychainWrapper

final class SwiftRantTests: XCTestCase {
    func testLogin() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(SwiftRant().text, "Hello, World!")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, token in
            XCTAssertNotNil(token)
            XCTAssertNil(error)
            
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            XCTAssertEqual(storedToken, token)
            
            XCTAssertNotNil(storedToken)
            
            let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecMatchLimit as String: kSecMatchLimitOne,
                                       kSecReturnAttributes as String: true,
                                       kSecReturnData as String: true,
                                       kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
            ]
            
            var item: CFTypeRef?
            SecItemCopyMatching(query as CFDictionary, &item)
            
            let existingItem = item as? [String:Any]
            let passwordData = existingItem?[kSecValueData as String] as? Data
            let password = String(data: passwordData ?? Data(), encoding: .utf8)
            let account = existingItem?[kSecAttrAccount as String] as? String
            
            XCTAssertEqual(account, username)
            XCTAssertEqual(password, password)
            
            UserDefaults.resetStandardUserDefaults()
            keychainWrapper.removeAllKeys()
            
            SecItemDelete(query as CFDictionary)
            
            semaphore.signal()
        }
        
        semaphore.wait()
        
        //XCTAssertEqual(SwiftRant().logIn(username: "OmerFlame", password: "ntbf782m", shouldUseUserDefaults: true, completionHandler: <#T##((String?, UserCredentials?) -> Void)##((String?, UserCredentials?) -> Void)##(String?, UserCredentials?) -> Void#>), <#T##expression2: Equatable##Equatable#>)
    }
    
    func testRantFeed() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!, completionHandler: { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.getRantFeed(token: nil, skip: 0, prevSet: nil, completionHandler: { error, rantFeed in
                //print("BREAKPOINT HERE")
                
                XCTAssertNotNil(rantFeed)
                XCTAssertNil(error)
                
                semaphore.signal()
            })
        })
        
        semaphore.wait()
        
        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecReturnAttributes as String: true,
                                   kSecReturnData as String: true,
                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
        ]
        
        keychainWrapper.removeAllKeys()
        UserDefaults.resetStandardUserDefaults()
        SecItemDelete(query as CFDictionary)
    }
    
    func testRantFromID() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.getRantFromID(token: nil, id: 4806571, lastCommentID: 4806576) { error, rant, comments in
                XCTAssertNil(error)
                XCTAssertNotNil(rant)
                XCTAssertNotNil(comments)
                
                print("BREAKPOINT")
                
                semaphore.signal()
            }
        }
        
        semaphore.wait()
        
        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecReturnAttributes as String: true,
                                   kSecReturnData as String: true,
                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
        ]
        
        keychainWrapper.removeAllKeys()
        UserDefaults.resetStandardUserDefaults()
        SecItemDelete(query as CFDictionary)
    }
    
    func testNotificationFeed() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            /*SwiftRant.shared.getRantFromID(token: nil, id: 4806571, lastCommentID: 4806576) { error, rant, comments in
                XCTAssertNil(error)
                XCTAssertNotNil(rant)
                XCTAssertNotNil(comments)
                
                print("BREAKPOINT")
                
                semaphore.signal()
            }*/
            
            SwiftRant.shared.getNotificationFeed(token: nil, lastCheckTime: nil, shouldGetNewNotifs: false, category: .all) { error, notifications in
                XCTAssertNil(error)
                XCTAssertNotNil(notifications)
                
                print("BREAKPOINT")
                
                semaphore.signal()
            }
        }
        
        semaphore.wait()
        
        let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecReturnAttributes as String: true,
                                   kSecReturnData as String: true,
                                   kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
        ]
        
        keychainWrapper.removeAllKeys()
        UserDefaults.resetStandardUserDefaults()
        SecItemDelete(query as CFDictionary)
    }
}
