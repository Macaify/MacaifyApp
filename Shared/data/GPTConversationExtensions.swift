//
//  GPTConversationExts.swift
//  Found
//
//  Created by lixindong on 2023/4/24.
//

import Foundation
import CoreData
import KeyboardShortcuts

extension GPTConversation {
    var uuid: UUID {
        get {
            if let u = uuid_ { return u }
            // Initialize missing UUID once to ensure stable identity
            let u = UUID()
            uuid_ = u
            return u
        }
        set { uuid_ = newValue }
    }
    public var id: UUID {
        get { return uuid }
        set { uuid = newValue }
    }
    var name: String {
        get { return name_ ?? "" }
        set { name_ = newValue }
    }
    var prompt: String {
        get { return prompt_ ?? "" }
        set { prompt_ = newValue }
    }
    var desc: String {
        get { return desc_ ?? "" }
        set { desc_ = newValue }
    }
    var icon: String {
        get { return icon_ ?? "" }
        set { icon_ = newValue }
    }
    var shortcut: String {
        get { return shortcut_ ?? "" }
        set { shortcut_ = newValue }
    }
    var timestamp: Date {
        get { return timestamp_ ?? Date() }
        set { timestamp_ = newValue }
    }
    var autoAddSelectedText: Bool {
        get { return autoAddSelectedText_ }
        set { autoAddSelectedText_ = newValue }
    }
    var typingInPlace: Bool {
        get { return typingInPlace_ }
        set { typingInPlace_ = newValue }
    }
    var withContext: Bool {
        get { return withContext_ }
        set { withContext_ = newValue }
    }
    // Per-bot selected account model id (if modelSource == "account").
    var modelId: String {
        get { return modelId_ ?? "" }
        set { modelId_ = newValue }
    }
    // Model selection: "default" | "instance"
    var modelSource: String {
        get { return modelSource_ ?? "default" }
        set { modelSource_ = newValue }
    }
    // When modelSource == "instance"; reference CustomModelInstance.id
    var modelInstanceId: String {
        get { return modelInstanceId_ ?? "" }
        set { modelInstanceId_ = newValue }
    }
    var own: [GPTAnswer] {
        get {
            return (own_?.array ?? []) as! [GPTAnswer]
        }
        set {
            own_ = NSOrderedSet(array: newValue)
        }
    }
    
    convenience init(_ name: String, id: UUID = UUID(), prompt: String = "", desc: String = "", icon: String = "", shortcut: String = "", timestamp: Date = Date(), autoAddSelectedText: Bool = true, typingInPlace: Bool = true, withContext: Bool = true, modelSource: String = "default", modelInstanceId: String = "", modelId: String = "", own: [GPTAnswer] = [], context: NSManagedObjectContext = PersistenceController.memoryContext) {
        self.init(context: context)
        self.name = name
        self.uuid = uuid
        self.prompt = prompt
        self.desc = desc
        self.icon = icon
        self.shortcut = shortcut
        self.timestamp = timestamp
        self.autoAddSelectedText = autoAddSelectedText
        self.typingInPlace = typingInPlace
        self.withContext = withContext
        self.modelSource = modelSource
        self.modelInstanceId = modelInstanceId
        self.modelId = modelId
        self.own = own
    }

    func copy(name: String? = nil,
             id: UUID? = nil,
             prompt: String? = nil,
             desc: String? = nil,
             icon: String? = nil,
             shortcut: String? = nil,
             timestamp: Date? = nil,
             autoAddSelectedText: Bool? = nil,
             typingInPlace: Bool? = nil,
             withContext: Bool? = nil,
             modelSource: String? = nil,
             modelInstanceId: String? = nil,
             modelId: String? = nil,
             own: [GPTAnswer]? = nil,
             context: NSManagedObjectContext? = nil) -> GPTConversation {
        let name = name ?? self.name
        let id = id ?? self.id
        let prompt = prompt ?? self.prompt
        let desc = desc ?? self.desc
        let icon = icon ?? self.icon
        let shortcut = shortcut ?? self.shortcut
        let timestamp = timestamp ?? self.timestamp
        let autoAddSelectedText = autoAddSelectedText ?? self.autoAddSelectedText
        let typingInPlace = typingInPlace ?? self.typingInPlace
        let withContext = withContext ?? self.withContext
        let modelSource = modelSource ?? self.modelSource
        let modelInstanceId = modelInstanceId ?? self.modelInstanceId
        let modelId = modelId ?? self.modelId
        let context = context ?? self.managedObjectContext!

        let newConv = GPTConversation(name, id: id, prompt: prompt, desc: desc, icon: icon, shortcut: shortcut, timestamp: timestamp, autoAddSelectedText: autoAddSelectedText, typingInPlace: typingInPlace, withContext: withContext, modelSource: modelSource, modelInstanceId: modelInstanceId, modelId: modelId, context: context)
        
        // 热键转移（兼容旧、支持新：主/编辑/聊天 三个键位）
        if let shortcut = KeyboardShortcuts.getShortcut(for: self.Name) {
            KeyboardShortcuts.setShortcut(shortcut, for: newConv.Name)
            KeyboardShortcuts.reset(self.Name)
            HotKeyManager.register(newConv)
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: self.NameEdit) {
            KeyboardShortcuts.setShortcut(shortcut, for: newConv.NameEdit)
            KeyboardShortcuts.reset(self.NameEdit)
            HotKeyManager.register(newConv)
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: self.NameChat) {
            KeyboardShortcuts.setShortcut(shortcut, for: newConv.NameChat)
            KeyboardShortcuts.reset(self.NameChat)
            HotKeyManager.register(newConv)
        }

        let own = own ?? self.own.map { answer in
            let ans = answer.copy(context: context)
            ans.belongsTo = newConv
            return ans
        }
        newConv.own = own
        return newConv
    }
    func copyToCoreData() -> GPTConversation {
        return copy(context: PersistenceController.sharedContext)
    }

    func copyToMemory() -> GPTConversation {
        return copy(context: PersistenceController.memoryContext)
    }

    func addAnswer(answer: GPTAnswer) {
        self.own.append(answer)
        answer.belongsTo = self
        save()
    }
    
    func save() {
        do {
            try managedObjectContext?.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            print("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func delete() {
        KeyboardShortcuts.reset(Name)
        KeyboardShortcuts.reset(NameEdit)
        KeyboardShortcuts.reset(NameChat)
        let ctx = managedObjectContext!
        // Delete all answers and sessions explicitly to satisfy Core Data validation
        do {
            let reqA: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
            reqA.predicate = NSPredicate(format: "belongsTo == %@", self)
            if let answers = try? ctx.fetch(reqA) { answers.forEach { ctx.delete($0) } }
            let reqS: NSFetchRequest<GPTSession> = GPTSession.fetchRequest()
            reqS.predicate = NSPredicate(format: "agent == %@", self)
            if let sessions = try? ctx.fetch(reqS) { sessions.forEach { ctx.delete($0) } }
            ctx.delete(self)
            try ctx.save()
        } catch {
            let nsError = error as NSError
            print("Conversation delete error: \(nsError), \(nsError.userInfo)")
        }
    }

    static var new: GPTConversation {
        get {
            GPTConversation(context: PersistenceController.memoryContext)
        }
    }
}
