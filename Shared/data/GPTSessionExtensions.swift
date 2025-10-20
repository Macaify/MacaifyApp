import Foundation
import CoreData

extension GPTSession {
    public var id: UUID {
        get { return uuid_ ?? UUID() }
        set { uuid_ = newValue }
    }
    var title: String {
        get { return title_ ?? "" }
        set { title_ = newValue }
    }
    var createdAt: Date {
        get { return createdAt_ ?? Date() }
        set { createdAt_ = newValue }
    }
    var updatedAt: Date {
        get { return updatedAt_ ?? Date() }
        set { updatedAt_ = newValue }
    }
    var archived: Bool {
        get { return archived_ }
        set { archived_ = newValue }
    }
    var agentConversation: GPTConversation? {
        get { return agent }
        set { agent = newValue }
    }
    var answers: [GPTAnswer] {
        get { return (messages?.array ?? []) as? [GPTAnswer] ?? [] }
        set { messages = NSOrderedSet(array: newValue) }
    }

    convenience init(title: String = "", agent: GPTConversation, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.archived = false
        self.agentConversation = agent
    }
}
