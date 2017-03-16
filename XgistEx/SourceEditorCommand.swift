//
//  AppDelegate.swift
//  Xgist
//
//  Created by Fernando Bunn on 10/12/16.
//  Copyright © 2016 Fernando Bunn. All rights reserved.
//

import Foundation
import XcodeKit
import AppKit

enum CommandType: String {
    case selection = "SourceEditorCommandFromSelection"
    case file = "SourceEditorCommandFromFile"
}


class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        let data = requestDataWith(commandInvocation: invocation)
        postCodeToGist(data: data) { (error) in
            completionHandler(error)
        }
    }
  

    func copyToPasteBoard(value: String) -> Void {
        let pasteboard = NSPasteboard.general()
        pasteboard.declareTypes([NSPasteboardTypeString], owner: nil)
        pasteboard.setString(value, forType: NSPasteboardTypeString)
    }
    
    
    //MARK: - Data Handling Methods
    
    func codeTypeWith(buffer: XCSourceTextBuffer) -> String {
        //Github doesn't recognize the type "objective-c"
        //There's probably a better way to solve this, but this will do for now
        let types = [("objective-c", "m"),
                     ("com.apple.dt.playground", "playground.swift"),
                     ("swift","swift"),
                     ("xml", "xml")]
        
        for type in types {
            if buffer.contentUTI.contains(type.0) {
                return type.1
            }
        }
        return buffer.contentUTI
    }
    
    func getTextSelectionFrom(buffer: XCSourceTextBuffer) -> String {
        var text = ""
        
        buffer.selections.forEach { selection in
            guard let range = selection as? XCSourceTextRange else { return }
            
            for l in range.start.line...range.end.line {
                if l >= buffer.lines.count {
                    continue
                }
                guard let line = buffer.lines[l] as? String else { continue }
                text.append(line)
            }
        }
        return text
    }
    
    func requestDataWith(commandInvocation: XCSourceEditorCommandInvocation) -> Data? {
        var file = [String : Any]()
        
        if commandInvocation.commandIdentifier.contains(CommandType.selection.rawValue) {
            file["content"] = getTextSelectionFrom(buffer: commandInvocation.buffer)
        } else if commandInvocation.commandIdentifier.contains(CommandType.file.rawValue) {
            file["content"] = commandInvocation.buffer.completeBuffer
        }

        var files = [String : Any]()
        files["Xgist.\(codeTypeWith(buffer: commandInvocation.buffer))"] = file
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let dateString = formatter.string(from: Date())
        
        var jsonDictionary = [String : Any]()
        jsonDictionary["description"] = "Generated by Xgist (https://github.com/Bunn/Xgist) at \(dateString)"
        jsonDictionary["public"] = false
        jsonDictionary["files"] = files
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonDictionary, options: .prettyPrinted)
        return jsonData
    }
    
    
    //MARK: - Network Methods
    
    func postCodeToGist(data: Data?, completion: @escaping (Error?) -> Void) -> Void {
        var request = URLRequest(url: URL(string: "https://api.github.com/gists")!)
        request.httpMethod = "POST"
        request.httpBody = data
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(error)
                return
            }
            
            if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 201 {
                completion(NSError(domain: "Wrong HHTP status", code: httpStatus.statusCode, userInfo: nil))
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as! [String : Any] {
                if let htmlURL = json["html_url"] as? String {
                    self.copyToPasteBoard(value: htmlURL)
                    
                    self.showSuccessMessage()
                    
                    completion(nil)
                }
            }
        }
        task.resume()
    }
    
    //MARK: - UI Agent
    
    private func showSuccessMessage() {
        guard let url = BezelMessage.clipboard.urlEncoded else { return }
        
        _ = NSWorkspace.shared().open(url)
    }
    
}
