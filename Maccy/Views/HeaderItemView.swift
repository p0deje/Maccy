//
//  HeaderItemView.swift
//  Maccy
//
//  Created by Lucian Mocan on 23/01/2025.
//  Copyright © 2025 p0deje. All rights reserved.
//

import SwiftUI

struct HeaderItemView: View {
  @Bindable var item: FooterItem

  var body: some View {
    ConfirmationView(item: item) {
      ListItemView(id: item.id, shortcuts: item.shortcuts, isSelected: item.isSelected) {
        Text(LocalizedStringKey(item.title))
      }
    }
  }
}
