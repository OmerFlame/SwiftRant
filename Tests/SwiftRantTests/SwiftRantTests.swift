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
        
        SwiftRant.shared.logIn(username: "OmerFlame", password: "password-here") { error, token in
            XCTAssertNotNil(token)
            XCTAssertNil(error)
            
            let storedToken: UserCredentials? = keychainWrapper.decode(forKey: "DRToken")
            
            XCTAssertNotNil(storedToken)
            
            let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecMatchLimit as String: kSecMatchLimitOne,
                                       kSecReturnAttributes as String: true,
                                       kSecReturnData as String: true,
                                       kSecAttrLabel as String: "SwiftRant-Attached Account" as CFString
            ]
            
            var item: CFTypeRef?
            var status = SecItemCopyMatching(query as CFDictionary, &item)
            
            let existingItem = item as? [String:Any]
            let passwordData = existingItem?[kSecValueData as String] as? Data
            let password = String(data: passwordData ?? Data(), encoding: .utf8)
            let account = existingItem?[kSecAttrAccount as String] as? String
            
            XCTAssertEqual(account, Optional("OmerFlame"))
            XCTAssertEqual(password, Optional("password-here"))
            
            UserDefaults.resetStandardUserDefaults()
            keychainWrapper.removeAllKeys()
            
            status = SecItemDelete(query as CFDictionary)
            
            semaphore.signal()
        }
        
        semaphore.wait()
        
        //XCTAssertEqual(SwiftRant().logIn(username: "OmerFlame", password: "ntbf782m", shouldUseUserDefaults: true, completionHandler: <#T##((String?, UserCredentials?) -> Void)##((String?, UserCredentials?) -> Void)##(String?, UserCredentials?) -> Void#>), <#T##expression2: Equatable##Equatable#>)
    }
    
    func testRantFeed() throws {
        let semaphore = DispatchSemaphore(value: 0)
        
        SwiftRant.shared.logIn(username: "OmerFlame", password: "password-here", completionHandler: { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.getRantFeed(token: nil, skip: 0, prevSet: nil, completionHandler: { error, rantFeed in
                print("BREAKPOINT HERE")
                
                semaphore.signal()
            })
        })
        
        semaphore.wait()
    }
}
