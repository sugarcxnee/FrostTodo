import SwiftUI

/// 侧边栏选择
public enum SidebarSelection: Hashable {
    case smart(SmartView)
    case tag(String)
    case project(String)
    case history
    case settings
}

/// 左栏：智能视图、标签、项目、历史与设置入口
public struct SidebarView: View {
    @EnvironmentObject private var app: AppViewModel
    @Binding var selection: SidebarSelection

    public var body: some View {
        List(selection: $selection) {
            Section("任务") {
                ForEach([SmartView.inbox, .today, .planned, .completed]) { view in
                    NavigationLink(value: SidebarSelection.smart(view)) {
                        Label(view.title, systemImage: view.symbol)
                    }
                }
            }

            if !app.taskList.availableTags.isEmpty {
                Section("标签") {
                    ForEach(app.taskList.availableTags, id: \.self) { tag in
                        NavigationLink(value: SidebarSelection.tag(tag)) {
                            Label(tag, systemImage: "tag")
                        }
                    }
                }
            }

            if !app.taskList.availableProjects.isEmpty {
                Section("项目") {
                    ForEach(app.taskList.availableProjects, id: \.self) { project in
                        NavigationLink(value: SidebarSelection.project(project)) {
                            Label(project, systemImage: "folder")
                        }
                    }
                }
            }

            Section("记录") {
                NavigationLink(value: SidebarSelection.history) {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                }
            }

            if !app.todaySchedule.isEmpty {
                Section("今日日程") {
                    ForEach(app.todaySchedule) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.callout)
                                .lineLimit(1)
                            if event.isAllDay {
                                Text("全天")
                                    .font(.caption)
                                    .foregroundStyle(FrostTheme.secondaryText)
                            } else {
                                Text("\(Formatters.time.string(from: event.startDate)) - \(Formatters.time.string(from: event.endDate))")
                                    .font(.caption)
                                    .foregroundStyle(FrostTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                NavigationLink(value: SidebarSelection.settings) {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}
