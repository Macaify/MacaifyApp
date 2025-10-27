//
//  Persistence.swift
//  gptexpir
//
//  Created by lixindong on 2023/2/20.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    static let memoryContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    static var sharedContext: NSManagedObjectContext {
        shared.container.viewContext
    }

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = GPTConversation(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "gptexpir")
        // Enable lightweight migration for schema changes (new attributes, etc.).
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func loadConversations() -> [GPTConversation] {
        // 获取 NSManagedObjectContext 实例
        let context = container.viewContext
        
        // 创建一个 NSFetchRequest 实例，并指定要获取的数据类
        let fetchRequest: NSFetchRequest<GPTConversation> = GPTConversation.fetchRequest()
        
        // 按最后修改时间排序
        let sortDescriptor = NSSortDescriptor(key: "timestamp_", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]

        // 执行查询
        do {
            var conversations = try context.fetch(fetchRequest)
            // One-time migration: ensure every conversation has a stable UUID
            var needsSave = false
            for conv in conversations {
                if (conv.value(forKey: "uuid_") as? UUID) == nil {
                    conv.uuid = UUID()
                    needsSave = true
                }
            }
            if needsSave {
                do { try context.save() } catch { print("Error saving migrated conversation UUIDs: \(error)") }
                // Refresh the array to reflect saved values
                conversations = try context.fetch(fetchRequest)
            }
            return conversations
        } catch {
            print("Error fetching conversations: \(error)")
            return []
        }
    }

    func deleteConversation(conversation: GPTConversation) {
        let viewContext = conversation.managedObjectContext!
        viewContext.delete(conversation)
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    // MARK: - Sessions (Stage 2b)
    func ensureDefaultSession(conversation: GPTConversation) {
        let container = self.container
        let convID = conversation.objectID
        let ctx = container.newBackgroundContext()
        ctx.performAndWait {
            do {
                guard let conv = try? ctx.existingObject(with: convID) as? GPTConversation else { return }
                // Load sessions for this conversation
                let reqS: NSFetchRequest<GPTSession> = GPTSession.fetchRequest()
                reqS.predicate = NSPredicate(format: "agent == %@", conv)
                let existing = try ctx.fetch(reqS)
                var session: GPTSession
                if let first = existing.first {
                    session = first
                } else {
                    session = GPTSession(title: conv.name.isEmpty ? "新会话" : conv.name, agent: conv, context: ctx)
                }
                // Assign session to answers missing it
                let reqA: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                reqA.predicate = NSPredicate(format: "belongsTo == %@ AND session == nil", conv)
                let answers = try ctx.fetch(reqA)
                answers.forEach { $0.session = session }
                try ctx.save()
            } catch {
                print("ensureDefaultSession error: \(error)")
            }
        }
    }

    func loadSessions(conversation: GPTConversation) -> [GPTSession] {
        let viewContext = container.viewContext
        let req: NSFetchRequest<GPTSession> = GPTSession.fetchRequest()
        req.predicate = NSPredicate(format: "agent == %@", conversation)
        req.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt_", ascending: false),
            NSSortDescriptor(key: "createdAt_", ascending: false)
        ]
        return (try? viewContext.fetch(req)) ?? []
    }

    func createSession(conversation: GPTConversation, title: String = "新会话") -> GPTSession? {
        let viewContext = container.viewContext
        let session = GPTSession(title: title, agent: conversation, context: viewContext)
        do { try viewContext.save(); return session } catch { print(error); return nil }
    }

    func rename(session: GPTSession, title: String) {
        session.title = title
        session.updatedAt = Date()
        do { try session.managedObjectContext?.save() } catch { print(error) }
    }

    func archive(session: GPTSession, archived: Bool) {
        session.archived = archived
        session.updatedAt = Date()
        do { try session.managedObjectContext?.save() } catch { print(error) }
    }

    // Delete a session. If moveToDefault is true, reassign its messages to the first non-archived default session; otherwise messages will be left with `session == nil` and will be assigned on next ensureDefaultSession.
    func delete(session: GPTSession, moveToDefault: Bool = true) {
        guard let ctx = session.managedObjectContext, let conv = session.agent else { return }
        if moveToDefault {
            // Find or create a destination session
            var destination: GPTSession? = loadSessions(conversation: conv).first(where: { $0 != session && !$0.archived })
            if destination == nil { destination = createSession(conversation: conv, title: "新会话") }
            if let dest = destination {
                // Reassign messages
                let reqA: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                reqA.predicate = NSPredicate(format: "session == %@", session)
                if let answers = try? ctx.fetch(reqA) {
                    answers.forEach { $0.session = dest }
                }
            }
        }
        ctx.delete(session)
        do { try ctx.save() } catch { print(error) }
    }
    
    func addConvasation() {
        let viewContext = container.viewContext
        let newItem = GPTConversation(context: viewContext)
        newItem.uuid = UUID()
        newItem.name = ""
        newItem.prompt = ""
        newItem.desc = ""
        newItem.icon = ""
        newItem.shortcut = ""
        newItem.timestamp = Date()
        newItem.own = []
        do {
            print("try")
            try viewContext.save()
        } catch {
            print("catch")
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func updateConvasationInfo(conversation: GPTConversation, id: UUID? = nil, name: String? = nil, prompt: String? = nil, desc: String? = nil, icon: String? = nil, shortcut: String? = nil, timestamp: Date? = nil, own: [GPTAnswer]? = nil) {
        let viewContext = conversation.managedObjectContext!
        
        if let id = id {
            conversation.uuid = id
        }
        if let name = name {
            conversation.name = name
        }
        if let prompt = prompt {
            conversation.prompt = prompt
        }
        if let desc = desc {
            conversation.desc = desc
        }
        if let icon = icon {
            conversation.icon = icon
        }
        if let shortcut = shortcut {
            conversation.shortcut = shortcut
        }
        if let timestamp = timestamp {
            conversation.timestamp = timestamp
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    func addAnswer(conversation: GPTConversation, role: String, response: String, prompt: String, parentId: UUID? = nil, contextClearedAfterThis: Bool = false) {
        let viewContext = conversation.managedObjectContext!
        let newItem = GPTAnswer(context: viewContext)
        newItem.uuid = UUID()
        newItem.role = role
        newItem.response = response
        newItem.prompt = prompt
        newItem.parentMessageId = parentId
        newItem.contextClearedAfterThis = contextClearedAfterThis
        newItem.prompt = prompt
        newItem.timestamp = Date()
        newItem.belongsTo = conversation
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func clearContext(conversation: GPTConversation) {
        let viewContext = conversation.managedObjectContext!
        if let answer = conversation.own.last {
            answer.contextClearedAfterThis = true
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            print("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func clearAnswers(conversation: GPTConversation) {
        let viewContext = conversation.managedObjectContext!
        conversation.own.forEach({ item in
            viewContext.delete(item)
        })
        conversation.own = []
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            print("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}
