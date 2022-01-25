import XCTest
@testable import SwiftRant
import SwiftKeychainWrapper
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class SwiftRantTests: XCTestCase {
    /*func withStdinReadingString(_ string: String, _ body: () throws -> Void) rethrows {
        let oldStdin = dup(STDIN_FILENO)
        
        let pipe = Pipe()
        
        dup2(pipe.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        
        pipe.fileHandleForWriting.write(Data(string.utf8))
        
        try! pipe.fileHandleForWriting.close()
        
        defer {
            dup2(oldStdin, STDIN_FILENO)
            
            close(oldStdin)
            
            try! pipe.fileHandleForReading.close()
        }
        
        try body()
    }*/
    
    func withReadLine(_ body: () -> Void) {
        let oldStdin = dup(STDIN_FILENO)
        let ttyFD = open("/dev/tty", O_RDONLY)
        if ttyFD == -1 {
            fatalError("withReadLine: couldn't read line")
        }
        
        dup2(ttyFD, STDIN_FILENO)
        
        defer {
            dup2(oldStdin, STDIN_FILENO)
            
            close(oldStdin)
        }
        
        body()
    }
    
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
            
            SwiftRant.shared.getRantFromID(token: nil, id: 5054220, lastCommentID: nil) { error, rant, comments in
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
    
    func testComment() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.getCommentFromID(4813564, token: nil) { error, comment in
                XCTAssertNil(error)
                XCTAssertNotNil(comment)
                
                print("BREAKPOINT HERE")
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
    
    func testVoteOnRant() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.voteOnRant(nil, rantID: 4811624, vote: 0) { error, updatedRant in
                XCTAssertNil(error)
                XCTAssertNotNil(updatedRant)
                
                print("BREAKPOINT HERE")
                
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
    
    func testVoteOnComment() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.voteOnComment(nil, commentID: 4811651, vote: 0) { error, updatedComment in
                XCTAssertNil(error)
                XCTAssertNotNil(updatedComment)
                
                print("BREAKPOINT HERE")
                
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
    
    func testGetProfile() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.getProfileFromID(SwiftRant.shared.tokenFromKeychain!.authToken.userID, token: nil, userContentType: .all, skip: 0) { error, profile in
                XCTAssertNil(error)
                XCTAssertNotNil(profile)
                
                print("BREAKPOINT HERE")
                
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
    
    func testEditProfileDetails() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.editProfileDetails(nil, aboutSection: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris sagittis, nulla accumsan viverra malesuada, sem ex consectetur ex, vitae iaculis felis lorem quis turpis. Duis imperdiet diam sed enim gravida ultrices. Mauris tempus rhoncus nunc, ac interdum tortor dictum nec. Praesent pretium id enim sit amet aliquet. Sed cursus laoreet porttitor.", skills: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", githubLink: "Lorem impsum", location: "Lorem ipsum, dolor", website: nil) { error in
                XCTAssertNil(error)
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testPostRant() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Print your real username: ", terminator: "")
        let username = readLine()
        
        print("Print your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            SwiftRant.shared.postRant(nil, postType: .undefined, content: "This is a test post", tags: nil, image: nil) { error, rantID in
                XCTAssertNil(error)
                XCTAssertNotNil(rantID)
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testDeleteRant() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the rant that you want to delete: ", terminator: "")
            var rantID = Int(readLine() ?? "")
            
            while rantID == nil {
                print("Invalid rant ID. Only digits are allowed.")
                print("Please enter the ID of the rant that you want to delete: ", terminator: "")
                rantID = Int(readLine() ?? "")
            }
            
            SwiftRant.shared.deleteRant(nil, rantID: rantID!) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The post exists on devRant.
2. The supplied user owns the post.
3. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testFavoriteRant() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the rant that you want to favorite: ", terminator: "")
            var rantID = Int(readLine() ?? "")
            
            while rantID == nil {
                print("Invalid rant ID. Only digits are allowed.")
                print("Please enter the ID of the rant that you want to favorite: ", terminator: "")
                rantID = Int(readLine() ?? "")
            }
            
            SwiftRant.shared.favoriteRant(nil, rantID: rantID!) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The post exists on devRant.
2. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testUnfavoriteRant() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the rant that you want to unfavorite: ", terminator: "")
            var rantID = Int(readLine() ?? "")
            
            while rantID == nil {
                print("Invalid rant ID. Only digits are allowed.")
                print("Please enter the ID of the rant that you want to unfavorite: ", terminator: "")
                rantID = Int(readLine() ?? "")
            }
            
            SwiftRant.shared.unfavoriteRant(nil, rantID: rantID!) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The post exists on devRant.
2. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testEditRant() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the rant that you want to edit: ", terminator: "")
            var rantID = Int(readLine() ?? "")
            
            while rantID == nil {
                print("Invalid rant ID. Only digits are allowed.")
                print("Please enter the ID of the rant that you want to edit: ", terminator: "")
                rantID = Int(readLine() ?? "")
            }
            
            print("Please enter the rant's new text body: ", terminator: "")
            var content = readLine() ?? ""
            
            while content.count <= 6 {
                print("Invalid body. You must enter more than 6 characters.")
                print("Please enter the rant's new text body: ", terminator: "")
                
                content = readLine() ?? ""
            }
            
            print("Please enter the rant's new post type.")
            print("""
        Available post types:
        1: rant
        2: collab
        3: meme
        4: question
        5: devRant
        6: random
        7: undefined
        """)
            
            print("Enter post type [1-7]: ", terminator: "")
            var postTypeID = Int(readLine() ?? "") ?? -1
            
            while !(1...7).contains(postTypeID) {
                print("Invalid post type entered.")
                print("Enter post type [1-7]: ", terminator: "")
                postTypeID = Int(readLine() ?? "") ?? -1
            }
            
            let postType = Rant.RantType(rawValue: postTypeID)!
            
            print("Please enter the rant's new tags (comma-separated, supports spaces, press ENTER with no input to provide no tags): ", terminator: "")
            let tags = readLine()
            
            print("NOTE: Adding images in tests are not supported.")
            
            SwiftRant.shared.editRant(nil, rantID: rantID!, postType: postType, content: content, tags: tags, image: nil) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The post exists on devRant.
2. The user that you provided owns the rant.
3. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testPostComment() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the rant to post a comment under: ", terminator: "")
            var rantID = Int(readLine() ?? "")
            
            while rantID == nil {
                print("Invalid rant ID. Only digits are allowed.")
                print("Please enter the ID of the rant that you want to post a comment under: ", terminator: "")
                rantID = Int(readLine() ?? "")
            }
            
            print("Please print the text inside the comment: ", terminator: "")
            var content = readLine() ?? ""
            
            while content.count <= 6 {
                print("Invalid body. You must enter more than 6 characters.")
                print("Please enter the rant's new text body: ", terminator: "")
                
                content = readLine() ?? ""
            }
            
            print("NOTE: Images in tests are not supported.")
            
            SwiftRant.shared.postComment(nil, rantID: rantID!, content: content, image: nil) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The post exists on devRant.
2. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testEditComment() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the comment that you want to edit: ", terminator: "")
            var commentID = Int(readLine() ?? "")
            
            while commentID == nil {
                print("Invalid comment ID. Only digits are allowed.")
                print("Please enter the ID of the comment that you want to edit: ", terminator: "")
                commentID = Int(readLine() ?? "")
            }
            
            print("Please enter the comment's new text body: ", terminator: "")
            var content = readLine() ?? ""
            
            while content.count <= 6 {
                print("Invalid body. You must enter more than 6 characters.")
                print("Please enter the comment's new text body: ", terminator: "")
                
                content = readLine() ?? ""
            }
            
            print("NOTE: Adding images is not supported in tests.")
            
            SwiftRant.shared.editComment(nil, commentID: commentID!, content: content, image: nil) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The comment exists on devRant.
2. The provided user owns the comment.
3. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
    
    // WARNING: DO NOT RUN THIS TOO MANY TIMES, THE ACCOUNT THAT YOU ARE LOGGING IN WITH MIGHT BE BANNED FOR SPAMMING!!!
    func testDeleteComment() throws {
        let keychainWrapper = KeychainWrapper(serviceName: "SwiftRant", accessGroup: "SwiftRantAccessGroup")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        print("Enter your real username: ", terminator: "")
        let username = readLine()
        
        print("Enter your real password: ", terminator: "")
        let password = readLine()
        
        SwiftRant.shared.logIn(username: username!, password: password!) { error, _ in
            XCTAssertNil(error)
            
            print("Please enter the ID of the comment that you want to delete: ", terminator: "")
            var commentID = Int(readLine() ?? "")
            
            while commentID == nil {
                print("Invalid comment ID. Only digits are allowed.")
                print("Please enter the ID of the comment that you want to delete: ", terminator: "")
                commentID = Int(readLine() ?? "")
            }
            
            SwiftRant.shared.deleteComment(nil, commentID: commentID!) { error, success in
                if !success {
                    if let error = error {
                        XCTExpectFailure("""
Something failed, but it might be completely expected.
This is the error that the function returned: \(error)

Before panicking, please make sure that:

1. The comment exists on devRant.
2. The provided user owns the comment.
3. None of the user's login credentials (username and/or password) have been changed externally while sending the request.
""") {
                            XCTFail()
                        }
                    }
                }
                
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
