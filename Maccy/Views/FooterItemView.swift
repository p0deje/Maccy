import SwiftUI

struct FooterItemView: View {
    @Bindable var item: FooterItem
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        ConfirmationView(item: item) {
            BaseItemView(
                id: item.id,
                shortcuts: item.shortcuts,
                isSelected: item.isSelected,
                help: item.help
            ) {
                HStack(spacing: 10) {
                    // Action Icon với hiệu ứng đơn giản
                    Image(systemName: iconForAction(item.title))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconColor)
                        // Chỉ giữ lại pressed effect, loại bỏ hover scaling
                        .scaleEffect(isPressed ? 0.95 : 1.0)

                    Text(LocalizedStringKey(item.title))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(textColor)

                    Spacer()
                }
                // Giảm scale effect
                .scaleEffect(isPressed ? 0.98 : 1.0)
            }
            // Đảm bảo toàn bộ BaseItemView có thể click được
            .contentShape(Rectangle())
        }
        // Đảm bảo toàn bộ ConfirmationView có thể click được
        .contentShape(Rectangle())
        // Tăng padding để có click area rộng hơn
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            // Background đơn giản hơn - chỉ opacity change
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .opacity(backgroundOpacity)
        }
        .overlay {
            // Border đơn giản - chỉ khi hover
            RoundedRectangle(cornerRadius: 6)
                .stroke(ThemeColors.accentColor.opacity(0.3), lineWidth: 1)
                .opacity(isHovered ? 1 : 0)
        }
        .onHover { hovering in
            // Animation đơn giản và nhanh
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .pressEvents {
            // Loại bỏ animation cho press - instant feedback
            isPressed = true
        } onRelease: {
            isPressed = false
        }
        // Loại bỏ hover scale để giảm CPU usage
        .contentShape(Rectangle())
        // Tăng hit testing area thêm nữa
        .frame(minHeight: 40)
    }

    // MARK: - Computed Properties - Đơn giản hóa

    private var iconColor: Color {
        if isPressed {
            return ThemeColors.accentColor
        } else if item.isSelected {
            return ThemeColors.selectedTextColor
        } else {
            return ThemeColors.secondaryTextColor
        }
    }

    private var textColor: Color {
        if item.isSelected {
            return ThemeColors.selectedTextColor
        } else if isHovered {
            return ThemeColors.primaryTextColor
        } else {
            return ThemeColors.secondaryTextColor
        }
    }

    // Đơn giản hóa background - loại bỏ gradient phức tạp
    private var backgroundColor: Color {
        if item.isSelected {
            return ThemeColors.selectedBackgroundColor
        } else if isHovered {
            return ThemeColors.accentColor.opacity(0.1)
        } else {
            return Color.clear
        }
    }

    private var backgroundOpacity: Double {
        if item.isSelected {
            return 1.0
        } else if isHovered {
            return 1.0
        } else {
            return 0.0
        }
    }

    // MARK: - Helper Functions

    private func iconForAction(_ title: String) -> String {
        switch title.lowercased() {
        case let str where str.contains("clear") && str.contains("all"):
            return "trash.fill"
        case let str where str.contains("clear"):
            return "xmark.circle"
        case let str where str.contains("quit"):
            return "power"
        case let str where str.contains("about"):
            return "info.circle"
        case let str where str.contains("settings"), let str where str.contains("preferences"):
            return "gearshape"
        default:
            return "square.and.pencil"
        }
    }
}

// MARK: - Press Events Extension
extension View {
    func pressEvents(onPress: @escaping () -> Void = {}, onRelease: @escaping () -> Void = {})
        -> some View
    {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}
