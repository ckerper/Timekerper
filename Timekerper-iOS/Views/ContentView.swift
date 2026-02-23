import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("Calendar", systemImage: "calendar") {
                CalendarTab()
            }

            Tab("Tasks", systemImage: "checklist") {
                TasksTab()
            }

            Tab("Events", systemImage: "clock") {
                EventsTab()
            }
        }
        .tint(Color(hex: "#7c3aed")) // Purple accent matching web
    }
}

// MARK: - Calendar Tab

struct CalendarTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var warmBackground: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(red: 0.98, green: 0.975, blue: 0.96)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ActiveTaskBar()
                CalendarView()
            }
            .background(warmBackground)
            .navigationTitle(DateTimeUtils.formatDateHeaderCompact(appState.selectedDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Button(action: appState.undo) {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!appState.canUndo)

                        Button(action: appState.redo) {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!appState.canRedo)
                    }
                }

                ToolbarItemGroup(placement: .principal) {
                    HStack(spacing: 12) {
                        Button(action: appState.goToPreviousDay) {
                            Image(systemName: "chevron.left")
                        }

                        Button(appState.isToday ? "Today" : DateTimeUtils.formatShortDateHeader(appState.selectedDate)) {
                            appState.goToToday()
                        }
                        .font(.headline)

                        Button(action: appState.goToNextDay) {
                            Image(systemName: "chevron.right")
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {
                        appState.editingTask = nil
                        appState.showTaskSheet = true
                    }) {
                        Image(systemName: "checklist.unchecked")
                    }

                    Button(action: {
                        appState.editingEvent = nil
                        appState.showEventSheet = true
                    }) {
                        Image(systemName: "calendar.badge.plus")
                    }

                    Button(action: { appState.showSettingsSheet = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: Binding(
                get: { appState.showSettingsSheet },
                set: { appState.showSettingsSheet = $0 }
            )) {
                SettingsView()
                    .preferredColorScheme(
                        appState.settings.darkMode == "on" ? .dark :
                        appState.settings.darkMode == "off" ? .light : nil
                    )
            }
            .sheet(isPresented: Binding(
                get: { appState.showTaskSheet },
                set: { appState.showTaskSheet = $0 }
            )) {
                TaskFormSheet()
                    .preferredColorScheme(
                        appState.settings.darkMode == "on" ? .dark :
                        appState.settings.darkMode == "off" ? .light : nil
                    )
            }
            .sheet(isPresented: Binding(
                get: { appState.showEventSheet },
                set: { appState.showEventSheet = $0 }
            )) {
                EventFormSheet()
                    .preferredColorScheme(
                        appState.settings.darkMode == "on" ? .dark :
                        appState.settings.darkMode == "off" ? .light : nil
                    )
            }
        }
    }
}

// MARK: - Tasks Tab

struct TasksTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var warmBackground: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(red: 0.98, green: 0.975, blue: 0.96)
    }

    var body: some View {
        NavigationStack {
            TaskListView()
                .background(warmBackground)
                .navigationTitle("Tasks")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            appState.editingTask = nil
                            appState.showTaskSheet = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { appState.showTaskSheet },
                    set: { appState.showTaskSheet = $0 }
                )) {
                    TaskFormSheet()
                }
        }
    }
}

// MARK: - Events Tab

struct EventsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var warmBackground: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(red: 0.98, green: 0.975, blue: 0.96)
    }

    var body: some View {
        NavigationStack {
            EventListView()
                .background(warmBackground)
                .navigationTitle("Events")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            appState.editingEvent = nil
                            appState.showEventSheet = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { appState.showEventSheet },
                    set: { appState.showEventSheet = $0 }
                )) {
                    EventFormSheet()
                }
        }
    }
}
