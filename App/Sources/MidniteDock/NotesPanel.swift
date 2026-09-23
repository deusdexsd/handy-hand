import SwiftUI
import DockCore

/// Panel notatek i zadań po prawej. Domyślnie notatka jest globalna; prawy przycisk → „Przypisz do kolekcji”
/// przypina ją do kolekcji (widać ją wtedy tylko przy tej kolekcji, a globalne zostają widoczne wszędzie).
struct NotesPanel: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dockAccent) private var accent
    @State private var draft = ""

    var body: some View {
        let notes = store.visibleNotes
        VStack(spacing: 0) {
            HStack {
                Text(L("Notatki", "Notes")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: $store.data.settings.notesShowAll) {
                    Text(L("Tu", "Here")).tag(false)
                    Text(L("Wszystkie", "All")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 110)
                    .help(L("Tu: globalne i przypisane do bieżącego widoku. Wszystkie: każda notatka z podpisem, gdzie jest.", "Here: global and assigned to the current view. All: every note, labelled with where it lives."))
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(notes) { NoteRow(store: store, note: $0) }
                    if notes.isEmpty {
                        Text(L("Brak notatek. Dopisz poniżej — zostanie zapisana jako globalna albo dla wybranej kolekcji, folderu lub typu. Edycja: dwuklik w tekst; przenoszenie: przeciągnij całą notatkę w lewy panel.", "No notes yet. Add one below — it is saved as global, or for the selected collection or folder."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 6)
                    }
                }.padding(.horizontal, 6)
            }
            HStack(spacing: 6) {
                TextField(L("Nowa notatka…", "New note…"), text: $draft, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...4)
                    .onSubmit { store.addNote(draft); draft = "" }
                Button { store.addNote(draft); draft = "" } label: { Image(systemName: "plus.circle.fill").foregroundStyle(draft.isEmpty ? Color.secondary : accent) }
                    .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08))).padding(8)
        }
        .frame(width: 210)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5) }
    }
}

private struct NoteRow: View {
    @ObservedObject var store: LibraryStore
    let note: NoteItem
    @State private var hover = false
    @State private var editing = false
    @FocusState private var focused: Bool

    private var scopeTitle: String? { note.scope.flatMap { store.title(for: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                if editing {
                    TextField("", text: Binding(get: { note.text }, set: { t in store.updateNote(note.id) { $0.text = t } }), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                        .onSubmit { editing = false }
                        .onChange(of: focused) { _, f in if !f { editing = false } }
                } else {
                    Text(note.text).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = true; focused = true }
                }
                Menu {
                    Button(L("Globalna (wszędzie)", "Global (everywhere)")) { store.updateNote(note.id) { $0.scope = nil } }
                    ForEach(Array(store.noteScopeGroups.enumerated()), id: \.offset) { _, g in
                        Menu(g.title) {
                            ForEach(Array(g.choices.enumerated()), id: \.offset) { _, ch in
                                Button(ch.title) { store.updateNote(note.id) { $0.scope = ch.category } }
                            }
                        }
                    }
                } label: { Image(systemName: "folder.badge.plus").font(.system(size: 11)).foregroundStyle(.secondary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(L("Przypisz do kolekcji, folderu lub typu", "Assign to a collection, folder or type"))
                Button { store.removeNote(note.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).padding(.top, 2).help(L("Usuń notatkę", "Delete note"))
            }
            if let cat = note.scope, scopeTitle != nil {
                Button { store.select(category: cat) } label: {
                    Text(L("Przypisana do: \(scopeTitle ?? "")", "Assigned to: \(scopeTitle ?? "")")).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                }.buttonStyle(.plain).help(L("Przejdź do tego miejsca", "Go there"))
            } else {
                Text(L("Globalna", "Global")).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.09 : 0.06)))
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        // Cała notatka jest uchwytem do przeciągania (na kolekcję, folder lub typ w lewym panelu); edycja: dwuklik w tekst.
        .draggable(LibraryStore.notePayloadPrefix + note.id.uuidString) {
            Text(note.text).font(.system(size: 12)).lineLimit(2).padding(6).frame(maxWidth: 180, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        }
    }
}
