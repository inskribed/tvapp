import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
            OrkaBackground()
            if model.playlists.isEmpty {
                WelcomeView()
            } else {
                TabView(selection: $model.tab) {
                    Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView() }
                    Tab("Guide", systemImage: "list.bullet.rectangle", value: AppTab.guide) { GuideView() }
                    Tab("Sports", systemImage: "sportscourt.fill", value: AppTab.sports) { SportsView() }
                    Tab("Favorites", systemImage: "star.fill", value: AppTab.favorites) { FavoritesView() }
                    Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) { SearchView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        .fullScreenCover(isPresented: $model.showPlayer) { PlayerView() }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .task {
            #if DEBUG
            await DemoMode.prepare(model)
            #endif
            await model.bootstrap()
            #if DEBUG
            await DemoMode.arrange(model)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.appBecameActive()
            case .background: model.appWentToBackground()
            default: break
            }
        }
    }
}
