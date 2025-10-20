//
//  ContentView.swift
//  XCAChatGPT
//
//  Created by lixindong on 2025/10/19.
//

import SwiftUI
import BetterAuth

struct LoginView: View {
  @EnvironmentObject private var authClient: BetterAuthClient

  var body: some View {
    if let user = authClient.user {
      Text("Hello, \(user.name)")
    }

    if let session = authClient.session {
      Button {
        Task {
          try await authClient.signOut()
        }
      }
      label: {
        Text("Sign out")
      }
    } else {
      Button {
        Task {
          try await authClient.signIn.email(with: .init(email: "auv1107@gmail.com", password: "lixindong14TC@"))
        }
      }
      label: {
        Text("Sign in")
      }
    }
  }
}
