import Defaults
import SwiftUI

struct FooterView: View {
    @Bindable var footer: Footer

    @Environment(AppState.self) private var appState
    @Environment(ModifierFlags.self) private var modifierFlags
    @Default(.showFooter) private var showFooter
    @State private var showDropdown = false
    @State private var clearOpacity: Double = 1
    @State private var clearAllOpacity: Double = 0
    @State private var dropdownButtonHovered = false

    var clearAllModifiersPressed: Bool {
        let clearModifiers = footer.items[0].shortcuts.first?.modifierFlags ?? []
        let clearAllModifiers = footer.items[1].shortcuts.first?.modifierFlags ?? []
        return !modifierFlags.flags.isEmpty
            && !modifierFlags.flags.isSubset(of: clearModifiers)
            && modifierFlags.flags.isSubset(of: clearAllModifiers)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Enhanced Divider với gradient - Clickable footer row
            HStack {
                // Toàn bộ footer row clickable với arrow ở giữa
                HStack {
                    Spacer()

                    // Arrow indicator ở giữa - Enhanced visibility
                    Image(systemName: showDropdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))  // Giảm size cho nhỏ gọn hơn
                        .foregroundColor(
                            dropdownButtonHovered
                                ? ThemeColors.accentColor
                                : ThemeColors.primaryTextColor
                        )
                        .scaleEffect(dropdownButtonHovered ? 1.1 : 1.0)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)  // Giảm padding
                        .background {
                            // Background để highlight arrow
                            RoundedRectangle(cornerRadius: 4)  // Giảm corner radius
                                .fill(
                                    dropdownButtonHovered
                                        ? ThemeColors.accentColor.opacity(0.15)
                                        : Color.secondary.opacity(0.08)  // Giảm opacity
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            dropdownButtonHovered
                                                ? ThemeColors.accentColor.opacity(0.3)
                                                : Color.secondary.opacity(0.15),  // Giảm opacity
                                            lineWidth: 0.5
                                        )
                                }
                        }

                    Spacer()
                }
                .padding(.horizontal, 8)  // Giảm horizontal padding
                .padding(.vertical, 4)  // Giảm vertical padding để footer nhỏ hơn
                .contentShape(Rectangle())  // Toàn bộ area clickable
                .background {
                    RoundedRectangle(cornerRadius: 6)  // Giảm corner radius
                        .fill(
                            dropdownButtonHovered
                                ? ThemeColors.accentColor.opacity(0.05)  // Giảm opacity
                                : Color.clear
                        )
                        .animation(.easeInOut(duration: 0.15), value: dropdownButtonHovered)
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDropdown.toggle()
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        dropdownButtonHovered = hovering
                    }
                }
                .help("Click to show actions")  // Tooltip
            }

            // Dropdown content - Loại bỏ stagger animation
            if showDropdown {
                VStack(spacing: 2) {  // Giảm spacing
                    // Clear và Clear All với animation đơn giản
                    ZStack {
                        FooterItemView(item: footer.items[0])
                            .opacity(clearOpacity)
                            .scaleEffect(clearOpacity)
                        FooterItemView(item: footer.items[1])
                            .opacity(clearAllOpacity)
                            .scaleEffect(clearAllOpacity)
                    }
                    .onChange(of: modifierFlags.flags) {
                        // Animation đơn giản hơn
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if clearAllModifiersPressed {
                                clearOpacity = 0
                                clearAllOpacity = 1
                                footer.items[0].isVisible = false
                                footer.items[1].isVisible = true
                                if appState.footer.selectedItem == footer.items[0] {
                                    appState.selection = footer.items[1].id
                                }
                            } else {
                                clearOpacity = 1
                                clearAllOpacity = 0
                                footer.items[0].isVisible = true
                                footer.items[1].isVisible = false
                                if appState.footer.selectedItem == footer.items[1] {
                                    appState.selection = footer.items[0].id
                                }
                            }
                        }
                    }

                    // Các items khác - Loại bỏ staggered animation
                    ForEach(footer.items.suffix(from: 2)) { item in
                        FooterItemView(item: item)
                            .transition(.opacity)  // Animation đơn giản
                    }
                }
                .padding(.horizontal, 4)  // Giảm horizontal padding
                .padding(.vertical, 6)  // Giảm vertical padding
                .background {
                    RoundedRectangle(cornerRadius: 8)  // Giảm corner radius
                        .fill(ThemeColors.cardBackgroundColor.opacity(0.6))
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ThemeColors.borderColor.opacity(0.3), lineWidth: 0.5)
                        }
                    // Loại bỏ shadow để giảm GPU usage
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))  // Đơn giản hóa transition
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .task(id: geo.size.height) {
                        appState.popup.footerHeight = geo.size.height
                    }
            }
        }
        .opacity(showFooter ? 1 : 0)
        .frame(maxHeight: showFooter ? nil : 0)
        .clipped()
        .animation(.easeInOut(duration: 0.3), value: showFooter)
    }
}
