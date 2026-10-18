import Foundation

@main
struct TaskChecks {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = directory.appendingPathComponent("tasks.json")
        let model = TaskListModel(storageURL: storage)
        precondition(!model.add("  \n   "))
        precondition(model.tasks.isEmpty)
        precondition(model.add("  Call  \n  mom  "))
        precondition(model.tasks.count == 1)
        precondition(model.tasks[0].title == "Call mom")
        precondition(!model.tasks[0].completed && model.remainingCount == 1)

        let original = model.tasks[0]
        precondition(model.toggle(original.id))
        precondition(model.tasks[0].completed && model.completedCount == 1)
        precondition(model.tasks[0].createdAt == original.createdAt)

        let restored = TaskListModel(storageURL: storage)
        precondition(restored.tasks == model.tasks)
        precondition(restored.clearCompleted())
        precondition(TaskListModel(storageURL: storage).tasks.isEmpty)

        let longTitle = String(repeating: "📝", count: TaskListModel.maximumTitleLength + 20)
        precondition(restored.add(longTitle))
        precondition(restored.tasks[0].title.count == TaskListModel.maximumTitleLength)
        precondition(restored.remove(restored.tasks[0].id))
        precondition(restored.tasks.isEmpty)

        for number in 0..<TaskListModel.maximumTaskCount {
            precondition(restored.add("Task \(number)"))
        }
        precondition(!restored.add("One too many"))
        precondition(restored.tasks.count == TaskListModel.maximumTaskCount)
        precondition(restored.error != nil)
        precondition(restored.remove(restored.tasks[0].id))
        precondition(restored.error == nil)

        let obstructingFile = directory.appendingPathComponent("obstructing-file")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: obstructingFile)
        let unwritable = TaskListModel(storageURL: obstructingFile.appendingPathComponent("tasks.json"))
        precondition(!unwritable.add("Cannot save"))
        precondition(unwritable.tasks.isEmpty && unwritable.error != nil)

        let damagedStorage = directory.appendingPathComponent("damaged.json")
        let damagedData = Data("not JSON".utf8)
        try damagedData.write(to: damagedStorage)
        let damaged = TaskListModel(storageURL: damagedStorage)
        precondition(damaged.error != nil)
        precondition(!damaged.add("Would overwrite damaged data"))
        let preservedData = try Data(contentsOf: damagedStorage)
        precondition(preservedData == damagedData)

        print("PASS: task persistence, editing, caps, and storage failures")
    }
}
