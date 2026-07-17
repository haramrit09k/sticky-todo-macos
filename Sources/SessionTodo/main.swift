import AppKit
import Carbon
import ServiceManagement
import UserNotifications

private let sessionTodoHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { delegate.togglePanel() }
    return noErr
}

final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class HorizontallyLockedClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.x = 0
        return constrained
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }
}

struct Todo: Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
}

@MainActor
final class TodoStore {
    private let key = "sessionTodos"
    var items: [Todo] = []

    init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Todo].self, from: data) else { return }
        items = saved
    }

    func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
final class TodoViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum DisplayRow: Equatable {
        case task(Int)
        case completedHeader
    }

    private let taskDragType = NSPasteboard.PasteboardType("local.sessiontodo.task-row")
    private let store = TodoStore()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let input = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Nothing pulling at your attention.\nAdd one small next step.")
    private let backlogButton = NSButton()
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private var isExpanded = false
    private var isCompletedExpanded = false
    private var editingIndex: Int?
    private var undoSnapshot: [Todo]?
    private var undoTimer: Timer?

    private var displayedRows: [DisplayRow] {
        guard isExpanded else {
            return store.items.firstIndex(where: { !$0.isDone }).map { [.task($0)] } ?? []
        }

        var rows = store.items.indices
            .filter { !store.items[$0].isDone }
            .map(DisplayRow.task)
        let completed = store.items.indices.filter { store.items[$0].isDone }
        if !completed.isEmpty {
            rows.append(.completedHeader)
            if isCompletedExpanded {
                rows.append(contentsOf: completed.map(DisplayRow.task))
            }
        }
        return rows
    }

    func pivotToTask(named rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let existingIndex = store.items.firstIndex(where: {
            !$0.isDone && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            let existing = store.items.remove(at: existingIndex)
            store.items.insert(existing, at: 0)
        } else {
            store.items.insert(Todo(id: UUID(), title: title, isDone: false), at: 0)
        }

        store.save()
        table.reloadData()
        updateCount()
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 520))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.085, alpha: 0.98).cgColor
        view.layer?.cornerRadius = 22
        view.layer?.masksToBounds = true
        buildUI()
        updateCount()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let availableWidth = max(scroll.contentSize.width - 2, 1)
        table.setFrameSize(NSSize(width: availableWidth, height: table.frame.height))
        table.tableColumns.first?.width = availableWidth
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func buildUI() {
        let title = NSTextField(labelWithString: "ONE THING AT A TIME")
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.42, green: 0.78, blue: 1, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Session focus")
        heading.font = .systemFont(ofSize: 30, weight: .bold)
        heading.textColor = .white
        heading.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: "×", target: self, action: #selector(quitApp))
        close.isBordered = false
        close.font = .systemFont(ofSize: 20, weight: .regular)
        close.contentTintColor = .tertiaryLabelColor
        close.toolTip = "Hide Session Todo (⌘⇧Space to restore)"
        close.translatesAutoresizingMaskIntoConstraints = false

        input.placeholderString = "What is the next small step?"
        input.font = .systemFont(ofSize: 17, weight: .medium)
        input.textColor = .white
        input.backgroundColor = .clear
        input.isBezeled = false
        input.isEditable = true
        input.isSelectable = true
        input.isEnabled = true
        input.focusRingType = .none
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false

        let inputShell = NSView()
        inputShell.wantsLayer = true
        inputShell.layer?.backgroundColor = NSColor(calibratedRed: 0.095, green: 0.11, blue: 0.14, alpha: 1).cgColor
        inputShell.layer?.cornerRadius = 13
        inputShell.translatesAutoresizingMaskIntoConstraints = false
        inputShell.addSubview(input)

        let addButton = NSButton(title: "Add", target: self, action: #selector(addTask))
        addButton.font = .systemFont(ofSize: 16, weight: .bold)
        addButton.bezelStyle = .regularSquare
        addButton.isBordered = false
        addButton.contentTintColor = .white
        addButton.wantsLayer = true
        addButton.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.75, alpha: 1).cgColor
        addButton.layer?.cornerRadius = 13
        addButton.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("todo"))
        column.width = 470
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 88
        table.intercellSpacing = NSSize(width: 0, height: 10)
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([taskDragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        let lockedClipView = HorizontallyLockedClipView(frame: .zero)
        lockedClipView.drawsBackground = false
        scroll.contentView = lockedClipView
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let clear = NSButton(title: "Clear completed", target: self, action: #selector(clearCompleted))
        clear.isBordered = false
        clear.font = .systemFont(ofSize: 13, weight: .medium)
        clear.contentTintColor = .secondaryLabelColor
        clear.translatesAutoresizingMaskIntoConstraints = false

        backlogButton.target = self
        backlogButton.action = #selector(toggleBacklog)
        backlogButton.isBordered = false
        backlogButton.font = .systemFont(ofSize: 13, weight: .semibold)
        backlogButton.contentTintColor = NSColor(calibratedRed: 0.42, green: 0.72, blue: 0.92, alpha: 1)
        backlogButton.translatesAutoresizingMaskIntoConstraints = false

        undoButton.target = self
        undoButton.action = #selector(undoLastChange)
        undoButton.isBordered = false
        undoButton.font = .systemFont(ofSize: 13, weight: .semibold)
        undoButton.contentTintColor = NSColor(calibratedRed: 0.42, green: 0.78, blue: 1, alpha: 1)
        undoButton.isHidden = true
        undoButton.translatesAutoresizingMaskIntoConstraints = false

        [title, heading, countLabel, close, inputShell, addButton, scroll, emptyLabel, backlogButton, undoButton, clear].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            heading.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            heading.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
            inputShell.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 24),
            inputShell.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            inputShell.heightAnchor.constraint(equalToConstant: 52),
            input.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor, constant: 14),
            input.trailingAnchor.constraint(equalTo: inputShell.trailingAnchor, constant: -14),
            input.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            input.heightAnchor.constraint(equalToConstant: 26),
            addButton.leadingAnchor.constraint(equalTo: inputShell.trailingAnchor, constant: 10),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            addButton.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 72),
            addButton.heightAnchor.constraint(equalToConstant: 52),
            scroll.topAnchor.constraint(equalTo: inputShell.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            scroll.bottomAnchor.constraint(equalTo: clear.topAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -10),
            backlogButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            backlogButton.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            undoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            undoButton.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            clear.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedRows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard displayedRows.indices.contains(row) else { return table.rowHeight }
        return displayedRows[row] == .completedHeader ? 44 : table.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedRows.indices.contains(row) else { return nil }
        if displayedRows[row] == .completedHeader {
            return makeCompletedHeader()
        }
        guard case let .task(itemIndex) = displayedRows[row] else { return nil }
        let item = store.items[itemIndex]
        let firstOpenRow = store.items.firstIndex(where: { !$0.isDone })
        let isNow = itemIndex == firstOpenRow
        let cell = NSView()
        let card = NSView()
        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer?.backgroundColor = (isNow
            ? NSColor(calibratedRed: 0.10, green: 0.19, blue: 0.27, alpha: 1)
            : NSColor(calibratedRed: 0.075, green: 0.087, blue: 0.11, alpha: 1)).cgColor
        card.layer?.cornerRadius = 12
        if isNow {
            card.layer?.borderWidth = 1
            card.layer?.borderColor = NSColor(calibratedRed: 0.25, green: 0.63, blue: 0.88, alpha: 0.55).cgColor
        }

        let taskControl: NSView
        if editingIndex == itemIndex {
            let editor = NSTextField(string: item.title)
            editor.tag = itemIndex
            editor.identifier = NSUserInterfaceItemIdentifier("inlineTaskEditor")
            editor.font = .systemFont(ofSize: 19, weight: .semibold)
            editor.textColor = .white
            editor.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07)
            editor.isBezeled = false
            editor.focusRingType = .none
            editor.delegate = self
            editor.target = self
            editor.action = #selector(saveInlineEdit(_:))
            editor.wantsLayer = true
            editor.layer?.cornerRadius = 7
            editor.translatesAutoresizingMaskIntoConstraints = false
            taskControl = editor
        } else {
            let taskWrapper = NSView()
            taskWrapper.translatesAutoresizingMaskIntoConstraints = false

            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleTask(_:)))
            check.tag = itemIndex
            check.state = item.isDone ? .on : .off
            check.controlSize = .large
            check.contentTintColor = item.isDone ? .tertiaryLabelColor : .white
            check.toolTip = item.isDone ? "Mark incomplete" : "Mark complete"
            check.translatesAutoresizingMaskIntoConstraints = false

            let taskTitle = NSButton(title: item.title, target: self, action: #selector(editTask(_:)))
            taskTitle.tag = itemIndex
            taskTitle.isBordered = false
            taskTitle.alignment = .left
            taskTitle.font = .systemFont(ofSize: 19, weight: .semibold)
            taskTitle.contentTintColor = item.isDone ? .tertiaryLabelColor : .white
            taskTitle.toolTip = "Edit task"
            taskTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            taskTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
            if item.isDone {
                taskTitle.attributedTitle = NSAttributedString(string: item.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ])
            }
            taskTitle.translatesAutoresizingMaskIntoConstraints = false

            taskWrapper.addSubview(check)
            taskWrapper.addSubview(taskTitle)
            NSLayoutConstraint.activate([
                check.leadingAnchor.constraint(equalTo: taskWrapper.leadingAnchor),
                check.centerYAnchor.constraint(equalTo: taskWrapper.centerYAnchor),
                check.widthAnchor.constraint(equalToConstant: 26),
                taskTitle.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
                taskTitle.trailingAnchor.constraint(equalTo: taskWrapper.trailingAnchor),
                taskTitle.centerYAnchor.constraint(equalTo: taskWrapper.centerYAnchor)
            ])
            taskControl = taskWrapper
        }

        let now = NSTextField(labelWithString: "NOW")
        now.font = .systemFont(ofSize: 11, weight: .bold)
        now.textColor = NSColor(calibratedRed: 0.45, green: 0.80, blue: 1, alpha: 1)
        now.isHidden = !isNow
        now.translatesAutoresizingMaskIntoConstraints = false

        let edit = NSButton(
            image: NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit task")!,
            target: self,
            action: #selector(editTask(_:))
        )
        edit.tag = itemIndex
        edit.isBordered = false
        edit.contentTintColor = .tertiaryLabelColor
        edit.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        edit.toolTip = "Edit task"
        edit.translatesAutoresizingMaskIntoConstraints = false

        let up = NSButton(
            image: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Move task up")!,
            target: self,
            action: #selector(moveTaskUp(_:))
        )
        up.tag = itemIndex
        up.isBordered = false
        up.contentTintColor = .tertiaryLabelColor
        up.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        up.toolTip = "Make this task sooner"
        up.isHidden = !isExpanded || item.isDone || itemIndex == firstOpenRow
        up.translatesAutoresizingMaskIntoConstraints = false

        let remove = NSButton(title: "×", target: self, action: #selector(removeTask(_:)))
        remove.tag = itemIndex
        remove.isBordered = false
        remove.font = .systemFont(ofSize: 24, weight: .medium)
        remove.contentTintColor = .tertiaryLabelColor
        remove.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(card)
        card.addSubview(taskControl)
        card.addSubview(now)
        card.addSubview(edit)
        card.addSubview(up)
        card.addSubview(remove)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: cell.topAnchor),
            card.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            taskControl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            taskControl.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            taskControl.trailingAnchor.constraint(lessThanOrEqualTo: now.leadingAnchor, constant: -8),
            taskControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            now.trailingAnchor.constraint(equalTo: edit.leadingAnchor, constant: -8),
            now.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            edit.trailingAnchor.constraint(equalTo: up.leadingAnchor, constant: -6),
            edit.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            edit.widthAnchor.constraint(equalToConstant: 30),
            edit.heightAnchor.constraint(equalToConstant: 30),
            up.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -6),
            up.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            up.widthAnchor.constraint(equalToConstant: 30),
            up.heightAnchor.constraint(equalToConstant: 30),
            remove.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            remove.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 34),
            remove.heightAnchor.constraint(equalToConstant: 34)
        ])
        return cell
    }

    private func makeCompletedHeader() -> NSView {
        let container = NSView()
        let count = store.items.filter(\.isDone).count
        let symbol = isCompletedExpanded ? "chevron.down" : "chevron.right"
        let disclosure = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: "Toggle completed tasks")!,
            target: self,
            action: #selector(toggleCompleted)
        )
        disclosure.title = "Completed (\(count))"
        disclosure.imagePosition = .imageLeading
        disclosure.imageHugsTitle = true
        disclosure.isBordered = false
        disclosure.alignment = .left
        disclosure.font = .systemFont(ofSize: 13, weight: .semibold)
        disclosure.contentTintColor = .secondaryLabelColor
        disclosure.toolTip = isCompletedExpanded ? "Hide completed tasks" : "Show completed tasks"
        disclosure.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(disclosure)
        NSLayoutConstraint.activate([
            disclosure.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            disclosure.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            disclosure.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            disclosure.heightAnchor.constraint(equalToConstant: 32)
        ])
        return container
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === input { addTask() }
            else if let editor = control as? NSTextField { saveInlineEdit(editor) }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), control !== input {
            editingIndex = nil
            table.reloadData()
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard isExpanded,
              displayedRows.indices.contains(row),
              case let .task(itemIndex) = displayedRows[row],
              !store.items[itemIndex].isDone else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(itemIndex), forType: taskDragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let completedHeaderRow = displayedRows.firstIndex(of: .completedHeader) ?? displayedRows.count
        guard isExpanded, row <= completedHeaderRow else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard isExpanded,
              let value = info.draggingPasteboard.string(forType: taskDragType),
              let source = Int(value),
              store.items.indices.contains(source),
              !store.items[source].isDone else { return false }
        var unfinished = store.items.filter { !$0.isDone }
        let completed = store.items.filter(\.isDone)
        guard let sourcePosition = unfinished.firstIndex(where: { $0.id == store.items[source].id }) else { return false }
        var destination = min(max(row, 0), unfinished.count)
        if sourcePosition < destination { destination -= 1 }
        guard destination != sourcePosition else { return false }
        rememberForUndo()
        let moved = unfinished.remove(at: sourcePosition)
        unfinished.insert(moved, at: destination)
        store.items = unfinished + completed
        changed()
        return true
    }

    @objc private func addTask() {
        let title = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.items.append(Todo(id: UUID(), title: title, isDone: false))
        input.stringValue = ""
        changed()
    }

    @objc private func toggleTask(_ sender: NSButton) {
        guard store.items.indices.contains(sender.tag) else { return }
        rememberForUndo()
        store.items[sender.tag].isDone.toggle()
        changed()
    }

    @objc private func removeTask(_ sender: NSButton) {
        guard store.items.indices.contains(sender.tag) else { return }
        rememberForUndo()
        store.items.remove(at: sender.tag)
        changed()
    }

    @objc private func clearCompleted() {
        guard store.items.contains(where: \.isDone) else { return }
        rememberForUndo()
        store.items.removeAll(where: \.isDone)
        changed()
    }

    @objc private func toggleBacklog() {
        isExpanded.toggle()
        isCompletedExpanded = false
        editingIndex = nil
        table.reloadData()
        updateCount()
    }

    @objc private func toggleCompleted() {
        isCompletedExpanded.toggle()
        editingIndex = nil
        table.reloadData()
        updateCount()
    }

    @objc private func editTask(_ sender: NSButton) {
        guard store.items.indices.contains(sender.tag) else { return }
        editingIndex = sender.tag
        table.reloadData()
        DispatchQueue.main.async {
            guard let displayRow = self.displayedRows.firstIndex(of: .task(sender.tag)),
                  let cell = self.table.view(atColumn: 0, row: displayRow, makeIfNecessary: false),
                  let editor = self.findInlineEditor(in: cell) else { return }
            self.view.window?.makeFirstResponder(editor)
            editor.currentEditor()?.selectAll(nil)
        }
    }

    private func findInlineEditor(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField,
           field.identifier?.rawValue == "inlineTaskEditor" { return field }
        for subview in view.subviews {
            if let found = findInlineEditor(in: subview) { return found }
        }
        return nil
    }

    @objc private func saveInlineEdit(_ field: NSTextField) {
        guard store.items.indices.contains(field.tag) else { return }
        let newTitle = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }
        rememberForUndo()
        store.items[field.tag].title = newTitle
        editingIndex = nil
        changed()
    }

    @objc private func moveTaskUp(_ sender: NSButton) {
        guard store.items.indices.contains(sender.tag),
              !store.items[sender.tag].isDone else { return }
        let unfinishedIndices = store.items.indices.filter { !store.items[$0].isDone }
        guard let position = unfinishedIndices.firstIndex(of: sender.tag), position > 0 else { return }
        rememberForUndo()
        store.items.swapAt(sender.tag, unfinishedIndices[position - 1])
        changed()
    }

    private func rememberForUndo() {
        undoSnapshot = store.items
        undoButton.isHidden = false
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.undoSnapshot = nil
                self?.undoButton.isHidden = true
            }
        }
    }

    @objc private func undoLastChange() {
        guard let undoSnapshot else { return }
        store.items = undoSnapshot
        self.undoSnapshot = nil
        undoTimer?.invalidate()
        undoButton.isHidden = true
        changed()
    }

    @objc private func quitApp() { view.window?.orderOut(nil) }

    private func changed() {
        store.save()
        table.reloadData()
        updateCount()
    }

    private func updateCount() {
        let remaining = store.items.filter { !$0.isDone }.count
        countLabel.stringValue = remaining == 1 ? "1 step left" : "\(remaining) steps left"
        let later = max(remaining - 1, 0)
        let completed = store.items.filter(\.isDone).count
        if isExpanded {
            backlogButton.title = "Hide backlog"
        } else if later == 1 {
            backlogButton.title = "Show 1 later"
        } else if later > 1 {
            backlogButton.title = "Show \(later) later"
        } else {
            backlogButton.title = "Show backlog"
        }
        backlogButton.isHidden = later == 0 && completed == 0
        emptyLabel.stringValue = store.items.isEmpty
            ? "Nothing pulling at your attention.\nAdd one small next step."
            : "Session complete.\nTake a breath before adding more."
        emptyLabel.isHidden = !displayedRows.isEmpty
    }

    func focusInput() {
        view.window?.makeFirstResponder(input)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var panel: NSPanel!
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var nudgeTimer: Timer?
    private var nudgeMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = TodoViewController()
        panel = FocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            self.panel.makeKey()
            controller.focusInput()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "checkmark.circle",
            accessibilityDescription: "Session Todo"
        )
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show / Hide Session Todo", action: #selector(togglePanel), keyEquivalent: " ")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(showItem)
        menu.addItem(.separator())
        nudgeMenuItem = NSMenuItem(title: "Gentle nudges", action: #selector(toggleNudges), keyEquivalent: "")
        nudgeMenuItem.target = self
        menu.addItem(nudgeMenuItem)
        loginMenuItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Session Todo", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        configureNudges()
        updateLoginMenuItem()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            sessionTodoHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
        let hotKeyID = EventHotKeyID(signature: 0x53544F44, id: 1) // STOD
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        nudgeTimer?.invalidate()
    }

    @objc func showPanel() {
        panel.center()
        panel.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        DispatchQueue.main.async {
            self.panel.makeKey()
            (self.panel.contentViewController as? TodoViewController)?.focusInput()
        }
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private var nudgesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "nudgesEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "nudgesEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "nudgesEnabled") }
    }

    private func configureNudges() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let yes = UNNotificationAction(identifier: "ON_TRACK", title: "Still on it", options: [])
        let distracted = UNNotificationAction(identifier: "DISTRACTED", title: "Got distracted", options: [.foreground])
        let switching = UNTextInputNotificationAction(
            identifier: "SWITCH_TASK",
            title: "Working on something else\u{2026}",
            options: [],
            textInputButtonTitle: "Switch focus",
            textInputPlaceholder: "What are you working on?"
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "FOCUS_CHECK", actions: [yes, distracted, switching], intentIdentifiers: [])
        ])
        nudgeMenuItem.state = nudgesEnabled ? .on : .off
        guard nudgesEnabled else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.scheduleNextNudge() }
        }
    }

    private func scheduleNextNudge() {
        nudgeTimer?.invalidate()
        guard nudgesEnabled else { return }
        let delay = TimeInterval.random(in: 20 * 60 ... 35 * 60)
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sendFocusNudge()
                self?.scheduleNextNudge()
            }
        }
    }

    private func sendFocusNudge() {
        guard let data = UserDefaults.standard.data(forKey: "sessionTodos"),
              let todos = try? JSONDecoder().decode([Todo].self, from: data),
              let current = todos.first(where: { !$0.isDone }) else { return }

        let copy: (title: String, body: String)
        switch Int.random(in: 0..<5) {
        case 0:
            copy = ("Rabbit-hole radar \u{1F407}", "Is \u{201C}\(current.title)\u{201D} still the mission?")
        case 1:
            copy = ("Tiny compass check \u{2728}", "Still heading toward \u{201C}\(current.title)\u{201D}?")
        case 2:
            copy = ("Psst\u{2026} your task is waving", "Making a little progress on \u{201C}\(current.title)\u{201D}?")
        case 3:
            copy = ("Plot check!", "Did the plot wander away from \u{201C}\(current.title)\u{201D}?")
        default:
            copy = ("A gentle todo boop", "Current quest: \u{201C}\(current.title)\u{201D}. Still with it?")
        }

        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.categoryIdentifier = "FOCUS_CHECK"
        content.sound = nil
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    @objc private func toggleNudges() {
        nudgesEnabled.toggle()
        nudgeMenuItem.state = nudgesEnabled ? .on : .off
        if nudgesEnabled { configureNudges() } else { nudgeTimer?.invalidate() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "SWITCH_TASK",
           let textResponse = response as? UNTextInputNotificationResponse {
            Task { @MainActor in
                (self.panel.contentViewController as? TodoViewController)?.pivotToTask(named: textResponse.userText)
                completionHandler()
            }
            return
        }
        if response.actionIdentifier == "DISTRACTED" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.showPanel() }
        }
        completionHandler()
    }

    private func updateLoginMenuItem() {
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Login Item"
            alert.informativeText = "Move Session Todo to Applications, then try again."
            alert.runModal()
        }
        updateLoginMenuItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
