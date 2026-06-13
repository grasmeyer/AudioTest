//
//  MainTabView.swift
//  AudioTest
//
//  Root tab bar: a Music tab with simple playback controls and a Visuals tab
//  holding the visualizer menu. Pushing into a visual hides the tab bar (see
//  RootView, which marks each destination with .toolbar(.hidden, for: .tabBar)).
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            MusicTabView()
                .tabItem {
                    Label("Music", systemImage: "music.note")
                }

            RootView()
                .tabItem {
                    Label("Visuals", systemImage: "sparkles")
                }
        }
    }
}

#Preview {
    MainTabView()
}
