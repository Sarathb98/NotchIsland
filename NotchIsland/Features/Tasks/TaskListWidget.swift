import SwiftUI

struct TaskListWidget: View {
    @ObservedObject var model: TaskListModel
    var height: CGFloat = 180

    @State private var newTask = ""

    private let muted = Color(white: 0.58)
    private let inset = Color(white: 0.11)
    private let blue = Color(red: 0.05, green: 0.61, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Tasks").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(muted)
                if !model.tasks.isEmpty {
                    Text("\(model.remainingCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted)
                        .accessibilityLabel("\(model.remainingCount) remaining")
                }
                Spacer(minLength: 0)
                if model.completedCount > 0 {
                    Menu {
                        Button("Clear Completed", role: .destructive) {
                            model.clearCompleted()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Task options")
                    .accessibilityLabel("Task options")
                }
            }

            HStack(spacing: 7) {
                Button(action: addTask) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add task")
                .accessibilityLabel("Add task")

                TextField("New task", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(addTask)
                    .accessibilityIdentifier("tasks.new")
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(inset, in: RoundedRectangle(cornerRadius: 7))

            if model.tasks.isEmpty {
                Text("Add a task to keep it close by.")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 5)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.tasks) { task in
                            row(task)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(error)
                    .accessibilityIdentifier("tasks.error")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: height)
        .foregroundStyle(.white)
        .tint(blue)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.tasks")
    }

    private func row(_ task: TaskListItem) -> some View {
        HStack(spacing: 7) {
            Button { model.toggle(task.id) } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(task.completed ? blue : muted)
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.plain)
            .help(task.completed ? "Mark incomplete" : "Mark complete")
            .accessibilityLabel(task.completed ? "Mark \(task.title) incomplete" : "Mark \(task.title) complete")
            .accessibilityValue(task.completed ? "Completed" : "Incomplete")

            Text(task.title)
                .font(.system(size: 12))
                .foregroundStyle(task.completed ? muted : .white)
                .strikethrough(task.completed)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(task.title)

            Button { model.remove(task.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(muted)
                    .frame(width: 19, height: 22)
            }
            .buttonStyle(.plain)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.title)")
        }
        .frame(height: 26)
        .contextMenu {
            Button(task.completed ? "Mark Incomplete" : "Mark Complete") {
                model.toggle(task.id)
            }
            Button("Delete Task", role: .destructive) {
                model.remove(task.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasks.row.\(task.id.uuidString)")
    }

    private func addTask() {
        if model.add(newTask) { newTask = "" }
    }
}
