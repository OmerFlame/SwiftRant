import XCTest
@testable import SwiftRant

final class SwiftRantTests: XCTestCase {
    func testLogin() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(SwiftRant().text, "Hello, World!")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        SwiftRant.logIn(username: "OmerFlame", password: "ntbf782m", shouldUseUserDefaults: true) { error, token in
            XCTAssertNotNil(token)
            XCTAssertNil(error)
            
            let storedToken: UserCredentials? = UserDefaults.standard.decode(forKey: "DRToken")
            
            XCTAssertNotNil(storedToken)
            
            XCTAssertEqual(UserDefaults.standard.string(forKey: "DRUsername")!, "OmerFlame")
            XCTAssertEqual(UserDefaults.standard.string(forKey: "DRPassword")!, "ntbf782m")
            
            UserDefaults.resetStandardUserDefaults()
            
            semaphore.signal()
        }
        
        semaphore.wait()
        
        //XCTAssertEqual(SwiftRant().logIn(username: "OmerFlame", password: "ntbf782m", shouldUseUserDefaults: true, completionHandler: <#T##((String?, UserCredentials?) -> Void)##((String?, UserCredentials?) -> Void)##(String?, UserCredentials?) -> Void#>), <#T##expression2: Equatable##Equatable#>)
    }
    
    func testRantFeed() throws {
        let semaphore = DispatchSemaphore(value: 0)
        
        SwiftRant.logIn(username: "OmerFlame", password: "ntbf782m", shouldUseUserDefaults: true, completionHandler: { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.getRantFeed(shouldUseUserDefaults: true, token: nil, skip: 0, prevSet: nil, completionHandler: { error, rantFeed in
                print("BREAKPOINT HERE")
                
                semaphore.signal()
            })
        })
        
        semaphore.wait()
    }
}
