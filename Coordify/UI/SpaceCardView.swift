import AppKit

/// SpaceCardView の表示に必要な情報をまとめたビューモデル
struct SpaceCardViewModel {
    let spaceIndex: Int
    let spaceName: String
    let shortcutKey: String?
    let isCurrent: Bool
    let isSelected: Bool
    let isFullscreen: Bool
    let thumbnail: CGImage?
    let wallpaper: NSImage?
    let apps: [AppInfo]
    let allApps: [AppInfo]
    let extraAppCount: Int
    var isSelectable: Bool = true
}

/// スイッチャー上で1つのスペースを表現するカードビュー
final class SpaceCardView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private var isHovered = false
    private var isSelected = false
    private var isSelectable = true
    private var trackingArea: NSTrackingArea?
    private let spaceContainer = NSView()
    private let borderOverlay = NSView()
    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()
    private let separator = NSBox()
    private let appListContainer = NSView()
    private let appStackView = NSStackView()
    private var separatorTopConstraint: NSLayoutConstraint?

    static let cardWidth: CGFloat = 200
    static let thumbnailHeight: CGFloat = cardWidth / 1.6
    static let maxApps = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        setupSpaceContainer()
        setupThumbnailView()
        setupNameLabel()
        setupShortcutLabel()
        setupSeparator()
        setupAppList()
        setupBorderOverlay()

        separatorTopConstraint = separator.topAnchor.constraint(equalTo: appListContainer.bottomAnchor, constant: 8)

        // ビュー階層の組み立て
        appListContainer.addSubview(appStackView)
        spaceContainer.addSubview(thumbnailView)
        spaceContainer.addSubview(nameLabel)
        spaceContainer.addSubview(shortcutContainer)
        spaceContainer.addSubview(separator)
        spaceContainer.addSubview(appListContainer)
        spaceContainer.addSubview(borderOverlay)
        addSubview(spaceContainer)

        setupConstraints()
    }

    private func setupSpaceContainer() {
        spaceContainer.wantsLayer = true
        spaceContainer.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor
        spaceContainer.layer?.cornerRadius = 6
        spaceContainer.layer?.masksToBounds = true
        spaceContainer.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupThumbnailView() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupNameLabel() {
        nameLabel.font = .systemFont(ofSize: 12, weight: .light)
        nameLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        nameLabel.alignment = .left
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func setupShortcutLabel() {
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        shortcutLabel.textColor = NSColor(red: 0.75, green: 0.8, blue: 0.9, alpha: 1.0)
        shortcutLabel.alignment = .center
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)

        shortcutContainer.wantsLayer = true
        shortcutContainer.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1.0).cgColor
        shortcutContainer.layer?.cornerRadius = 4
        shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.addSubview(shortcutLabel)
    }

    private func setupSeparator() {
        separator.boxType = .custom
        separator.isTransparent = false
        separator.borderWidth = 0
        separator.fillColor = NSColor(white: 0.2, alpha: 1.0)
        separator.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupAppList() {
        appListContainer.translatesAutoresizingMaskIntoConstraints = false
        appStackView.orientation = .vertical
        appStackView.alignment = .leading
        appStackView.spacing = 8
        appStackView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupBorderOverlay() {
        borderOverlay.wantsLayer = true
        borderOverlay.layer?.cornerRadius = 6
        borderOverlay.layer?.masksToBounds = true
        borderOverlay.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // spaceContainer がカード全体を埋める
            spaceContainer.topAnchor.constraint(equalTo: topAnchor),
            spaceContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            spaceContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            spaceContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Border overlay: spaceContainer と同サイズ
            borderOverlay.topAnchor.constraint(equalTo: spaceContainer.topAnchor),
            borderOverlay.leadingAnchor.constraint(equalTo: spaceContainer.leadingAnchor),
            borderOverlay.trailingAnchor.constraint(equalTo: spaceContainer.trailingAnchor),
            borderOverlay.bottomAnchor.constraint(equalTo: spaceContainer.bottomAnchor),

            // Thumbnail: spaceContainer の上辺に重なる
            thumbnailView.topAnchor.constraint(equalTo: spaceContainer.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: spaceContainer.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: spaceContainer.trailingAnchor),
            thumbnailView.widthAnchor.constraint(equalTo: thumbnailView.heightAnchor, multiplier: 1.6),

            // App list container: サムネイルの下
            appListContainer.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 14),
            appListContainer.leadingAnchor.constraint(equalTo: spaceContainer.leadingAnchor),
            appListContainer.trailingAnchor.constraint(equalTo: spaceContainer.trailingAnchor),

            // App stack: container 内のパディング
            appStackView.topAnchor.constraint(equalTo: appListContainer.topAnchor),
            appStackView.leadingAnchor.constraint(equalTo: appListContainer.leadingAnchor, constant: 12),
            appStackView.trailingAnchor.constraint(equalTo: appListContainer.trailingAnchor, constant: -12),
            appStackView.bottomAnchor.constraint(equalTo: appListContainer.bottomAnchor),

            // 区切り線
            separatorTopConstraint!,
            separator.leadingAnchor.constraint(equalTo: spaceContainer.leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: spaceContainer.trailingAnchor, constant: -12),
            separator.heightAnchor.constraint(equalToConstant: 1),

            // Name label: 区切り線の下
            nameLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: spaceContainer.leadingAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: spaceContainer.bottomAnchor, constant: -10),

            // Shortcut container: nameLabel の右、右端揃え
            shortcutContainer.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
            shortcutContainer.trailingAnchor.constraint(equalTo: spaceContainer.trailingAnchor, constant: -12),
            shortcutContainer.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            // Index label: container 内にパディング付き配置
            shortcutLabel.topAnchor.constraint(equalTo: shortcutContainer.topAnchor, constant: 2),
            shortcutLabel.bottomAnchor.constraint(equalTo: shortcutContainer.bottomAnchor, constant: -2),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 6),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -6),
        ])
    }

    /// ビューモデルの内容でカードの表示を更新する
    /// - Parameter viewModel: 表示データ
    func configure(with viewModel: SpaceCardViewModel) {
        configureThumbnail(viewModel)
        configureLabels(viewModel)
        configureCurrentSpaceAppearance(isCurrent: viewModel.isCurrent)
        configureSelectionHighlight(viewModel)
        configureAppList(viewModel)
    }

    private func configureThumbnail(_ viewModel: SpaceCardViewModel) {
        if let cgImage = viewModel.thumbnail {
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            thumbnailView.image = NSImage(cgImage: cgImage, size: size)
        } else if let wallpaper = viewModel.wallpaper {
            thumbnailView.image = wallpaper
        } else {
            thumbnailView.image = nil
            thumbnailView.layer?.backgroundColor = NSColor.darkGray.cgColor
        }
    }

    private func configureLabels(_ viewModel: SpaceCardViewModel) {
        nameLabel.stringValue = viewModel.spaceName
        if let key = viewModel.shortcutKey {
            shortcutLabel.stringValue = key
            shortcutContainer.isHidden = false
        } else {
            shortcutContainer.isHidden = true
        }
    }

    private func configureCurrentSpaceAppearance(isCurrent: Bool) {
        spaceContainer.layer?.backgroundColor = isCurrent
            ? NSColor(white: 0.18, alpha: 1.0).cgColor
            : NSColor(white: 0.12, alpha: 1.0).cgColor
        separator.fillColor = isCurrent
            ? NSColor(white: 0.28, alpha: 1.0)
            : NSColor(white: 0.2, alpha: 1.0)
        shortcutContainer.layer?.backgroundColor = isCurrent
            ? NSColor(white: 0.25, alpha: 1.0).cgColor
            : NSColor(white: 0.18, alpha: 1.0).cgColor
    }

    private func configureSelectionHighlight(_ viewModel: SpaceCardViewModel) {
        isSelected = viewModel.isSelected
        isSelectable = viewModel.isSelectable
        if viewModel.isSelected {
            borderOverlay.layer?.borderWidth = 2
            borderOverlay.layer?.borderColor = NSColor.controlAccentColor.cgColor
            separatorTopConstraint?.constant = 14
        } else {
            borderOverlay.layer?.borderWidth = 1
            borderOverlay.layer?.borderColor = (isHovered && isSelectable)
                ? NSColor.controlAccentColor.cgColor
                : NSColor(white: 0.22, alpha: 1.0).cgColor
            separatorTopConstraint?.constant = 8
        }
    }

    private func configureAppList(_ viewModel: SpaceCardViewModel) {
        appStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let expanded = viewModel.isSelected && viewModel.extraAppCount > 0
        let appsToShow = expanded ? viewModel.allApps : viewModel.apps

        if appsToShow.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "no apps")
            emptyLabel.font = .systemFont(ofSize: 11)
            emptyLabel.textColor = NSColor(white: 0.4, alpha: 1.0)
            appStackView.addArrangedSubview(emptyLabel)
        }

        for app in appsToShow {
            appStackView.addArrangedSubview(createAppRow(icon: app.icon, name: app.appName))
        }

        if !expanded, viewModel.extraAppCount > 0 {
            let moreLabel = NSTextField(labelWithString: "+\(viewModel.extraAppCount) more")
            moreLabel.font = .systemFont(ofSize: 12)
            moreLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
            moreLabel.translatesAutoresizingMaskIntoConstraints = false
            moreLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true
            appStackView.addArrangedSubview(moreLabel)
        }
    }

    private func createAppRow(icon: NSImage, name: String) -> NSView {
        let iconView = NSImageView()
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 14)
        label.textColor = NSColor(white: 0.82, alpha: 1.0)
        label.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }
}

// MARK: - Event Handling

extension SpaceCardView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
        updateHoverBorder()
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        updateHoverBorder()
    }

    private func updateHoverBorder() {
        guard !isSelected else { return }
        borderOverlay.layer?.borderColor = (isHovered && isSelectable)
            ? NSColor.controlAccentColor.cgColor
            : NSColor(white: 0.22, alpha: 1.0).cgColor
    }

    override func mouseDown(with _: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with _: NSEvent) {
        onRightClick?()
    }
}
