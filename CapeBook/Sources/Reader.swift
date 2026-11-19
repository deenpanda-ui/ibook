import UIKit
import SwiftUI
import CoreMotion

// MARK: - Одна страница

final class PageViewController: UIViewController {
    let chapter: Int
    let page: Int
    private let pages: ChapterPages      // держит вёрстку главы, пока страница на экране
    private let textView: UITextView
    private let numberLabel = UILabel()
    private let insets: UIEdgeInsets
    private let pageSize: CGSize

    init(chapter: Int, page: Int, pages: ChapterPages, insets: UIEdgeInsets, pageSize: CGSize,
         settings: ReaderSettings, pageNumber: String, delegate: UITextViewDelegate?) {
        self.chapter = chapter
        self.page = page
        self.pages = pages
        self.insets = insets
        self.pageSize = pageSize
        textView = UITextView(frame: CGRect(origin: .zero, size: pageSize), textContainer: pages.containers[page])
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = settings.theme.background
        if let img = settings.theme.image {
            let bg = UIImageView(image: img)
            bg.contentMode = .scaleToFill
            bg.frame = view.bounds
            bg.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(bg)
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.tintColor = UIColor(red: 0.30, green: 0.66, blue: 0.36, alpha: 1)   // зелёное выделение
        textView.delegate = delegate
        view.addSubview(textView)
        numberLabel.text = pageNumber
        numberLabel.adjustsFontSizeToFitWidth = true
        numberLabel.font = Typesetter.font(size: 13, bold: false, italic: false)
        numberLabel.textColor = settings.theme.text.withAlphaComponent(0.55)
        numberLabel.textAlignment = .center
        view.addSubview(numberLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setNumber(_ s: String) { numberLabel.text = s }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        textView.frame = CGRect(x: insets.left, y: insets.top, width: pageSize.width, height: pageSize.height)
        // номер страницы — у самого низа экрана, над полоской «домой»
        let safeBottom = view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        let textBottom = insets.top + pageSize.height
        let y = max(textBottom + 1, view.bounds.height - max(safeBottom, 12) * 0.5 - 14)
        numberLabel.frame = CGRect(x: insets.left + 60, y: min(y, view.bounds.height - 16), width: max(40, view.bounds.width - insets.left - insets.right - 120), height: 18)
    }
}

// MARK: - Читалка

final class ReaderViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
                                  UITextViewDelegate, UIGestureRecognizerDelegate {
    private var book: Book
    private let content: BookContent
    private var settings = ReaderSettings.load()
    private var pageVC: UIPageViewController!
    private var chapters: [Int: ChapterPages] = [:]
    private var pageCache: [String: PageViewController] = [:]
    private var laidOutSize: CGSize = .zero
    private var current: (chapter: Int, page: Int) = (0, 0)
    private var chromeHidden = true
    private let progressLabel = UILabel()
    private var backButton = UIButton()
    private var tocButton = UIButton()
    private var settingsButton = UIButton()
    private var chromeButtons: [UIButton] { [backButton, tocButton, settingsButton] }
    // общий счёт страниц по всей книге: число страниц в каждой главе (считается постепенно)
    private var pageCounts: [Int?] = []
    private var countingKey = ""
    private let slider = UISlider()
    private let timer: ReadingTimer
    private let sideTap = UITapGestureRecognizer()
    private var turning = false

    init(book: Book, content: BookContent) {
        self.book = book
        self.content = content
        self.timer = ReadingTimer(bookID: book.id, startProgress: book.progress)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: жизненный цикл
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = settings.theme.background
        pageVC = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                      options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)])
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.isDoubleSided = false
        addChild(pageVC)
        view.addSubview(pageVC.view)
        pageVC.view.frame = view.bounds
        pageVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageVC.didMove(toParent: self)

        let tap = UITapGestureRecognizer(target: self, action: #selector(centerTap(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
        sideTap.addTarget(self, action: #selector(sideTapped(_:)))
        sideTap.delegate = self
        view.addGestureRecognizer(sideTap)
        applyTapZones()

        // кнопки — по бокам от Dynamic Island, вместо часов, батареи и сети
        let tint = UIColor(red: 0.30, green: 0.66, blue: 0.36, alpha: 1)
        func make(_ symbol: String, _ action: Selector) -> UIButton {
            var cfg = UIButton.Configuration.glass()
            cfg.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            cfg.baseForegroundColor = tint
            cfg.cornerStyle = .capsule
            let b = UIButton(configuration: cfg)
            b.addTarget(self, action: action, for: .touchUpInside)
            b.alpha = 0
            b.isUserInteractionEnabled = false
            view.addSubview(b)
            return b
        }
        backButton = make("chevron.backward", #selector(close))
        tocButton = make("list.bullet", #selector(showToc))
        settingsButton = make("textformat.size", #selector(showSettings))
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        progressLabel.textColor = .secondaryLabel
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = UIColor(red: 0.30, green: 0.66, blue: 0.36, alpha: 1)
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.setToolbarHidden(true, animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(appBackground), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timer.start()
        applyOrientation()
        Diagnostics.log("книга открыта: \(book.title)")
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer.stop(progress: book.progress)
        savePosition()
        OrientationLock.set(.portrait, from: view.window)   // библиотека — всегда вертикально
    }
    /// В книге поворот разрешён, если не включено «Не поворачивать»
    private func applyOrientation() {
        guard let scene = view.window?.windowScene else { return }
        let mask: UIInterfaceOrientationMask
        if settings.lockOrientation {
            switch scene.effectiveGeometry.interfaceOrientation {
            case .landscapeLeft: mask = .landscapeLeft
            case .landscapeRight: mask = .landscapeRight
            default: mask = .portrait
            }
        } else { mask = .allButUpsideDown }
        OrientationLock.set(mask, from: view.window)
    }
    @objc private func appBackground() { timer.pause(progress: book.progress); savePosition() }
    @objc private func appForeground() { timer.resume() }

    override var prefersStatusBarHidden: Bool { true }      // в чтении часы, батарея и сеть не показываются
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { settings.theme.isDark ? .lightContent : .darkContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChromeButtons()
        let size = view.bounds.size
        guard size.width > 0, size != laidOutSize else { return }
        let firstLayout = laidOutSize == .zero
        laidOutSize = size
        let offset = firstLayout ? book.offset : currentOffset()
        let chapter = firstLayout ? min(max(0, book.chapter), max(0, content.chapterCount - 1)) : current.chapter
        relayout(goTo: chapter, offset: offset)
    }

    // MARK: вёрстка
    private var insets: UIEdgeInsets {
        let safe = view.window?.safeAreaInsets ?? view.safeAreaInsets
        return UIEdgeInsets(top: max(safe.top, 20) + settings.topInset, left: 26, bottom: max(safe.bottom, 12) + settings.bottomInset, right: 26)
    }
    private var pageSize: CGSize {
        let i = insets
        return CGSize(width: max(100, view.bounds.width - i.left - i.right), height: max(100, view.bounds.height - i.top - i.bottom))
    }
    private func pages(_ chapter: Int) -> ChapterPages {
        if let p = chapters[chapter] { return p }
        let text = Typesetter.build(content.blocks(chapter: chapter), settings: settings, pageSize: pageSize)
        let p = ChapterPages(text: text, pageSize: pageSize)
        chapters[chapter] = p
        // не держать в памяти далёкие главы
        for k in chapters.keys where abs(k - chapter) > 2 {
            chapters[k] = nil
            pageCache = pageCache.filter { !$0.key.hasPrefix("\(k)-") }
        }
        return p
    }
    private func pageController(_ chapter: Int, _ page: Int) -> PageViewController {
        let key = "\(chapter)-\(page)"
        if let vc = pageCache[key] { return vc }
        let p = pages(chapter)
        let vc = PageViewController(chapter: chapter, page: page, pages: p, insets: insets, pageSize: pageSize,
                                    settings: settings, pageNumber: numberText(chapter, page, p.count), delegate: self)
        pageCache[key] = vc
        return vc
    }
    // MARK: номера страниц по всей книге
    private func numberText(_ chapter: Int, _ page: Int, _ count: Int) -> String {
        guard let total = totalPages(), chapter < pageCounts.count else { return "" }   // пока не посчитано — без номера
        let before = pageCounts[0..<chapter].reduce(0) { $0 + ($1 ?? 0) }
        return "\(before + page + 1) из \(total)"
    }
    private func totalPages() -> Int? {
        guard !pageCounts.isEmpty, !pageCounts.contains(where: { $0 == nil }) else { return nil }
        return pageCounts.reduce(0) { $0 + ($1 ?? 0) }
    }
    /// Посчитать страницы всех глав — по одной главе за раз, не мешая листать; результат запоминается
    private func startCounting() {
        let s = settings, size = pageSize
        let key = "pc.\(book.id.uuidString).\(s.fontFamily).\(s.fontSize).\(s.lineSpacing).\(s.hyphenate).\(Int(size.width))x\(Int(size.height)).v2"
        countingKey = key
        let n = content.chapterCount
        if let saved = UserDefaults.standard.array(forKey: key) as? [Int], saved.count == n {
            pageCounts = saved
            refreshNumbers()
            return
        }
        pageCounts = Array(repeating: nil, count: n)
        for (c, p) in chapters { if c < n { pageCounts[c] = p.count } }
        countNext(key: key)
    }
    private func countNext(key: String) {
        guard key == countingKey else { return }               // настройки поменялись — старый счёт не нужен
        guard let c = pageCounts.firstIndex(where: { $0 == nil }) else {
            UserDefaults.standard.set(pageCounts.map { $0 ?? 0 }, forKey: key)
            refreshNumbers()
            return
        }
        if let p = chapters[c] { pageCounts[c] = p.count }
        else {
            let text = Typesetter.build(content.blocks(chapter: c), settings: settings, pageSize: pageSize)
            pageCounts[c] = ChapterPages(text: text, pageSize: pageSize).count
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.countNext(key: key) }
    }
    private func refreshNumbers() {
        for vc in pageCache.values {
            vc.setNumber(numberText(vc.chapter, vc.page, chapters[vc.chapter]?.count ?? 0))
        }
        if totalPages() != nil { pageChanged(turned: false) }
    }

    private func relayout(goTo chapter: Int, offset: Int) {
        chapters = [:]
        pageCache = [:]
        view.backgroundColor = settings.theme.background
        guard content.chapterCount > 0 else { return }
        let c = min(max(0, chapter), content.chapterCount - 1)
        let p = pages(c).page(containing: offset)
        countingKey = ""
        pageCounts = []
        Diagnostics.log("layout: view=\(view.bounds.size) insets=\(insets) page=\(pageSize) font=\(settings.fontFamily) \(settings.fontSize)")
        show(c, p, animated: false, forward: true)
        startCounting()
    }
    private func show(_ chapter: Int, _ page: Int, animated: Bool, forward: Bool) {
        let vc = pageController(chapter, page)
        pageVC.setViewControllers([vc], direction: forward ? .forward : .reverse, animated: animated)
        current = (chapter, page)
        pageChanged()
    }
    private func currentOffset() -> Int {
        guard let p = chapters[current.chapter], current.page < p.ranges.count else { return book.offset }
        return p.ranges[current.page].location
    }

    // MARK: позиция и прогресс
    private func pageChanged(turned: Bool = true) {
        let p = pages(current.chapter)
        let chapterFraction = Double(current.page + 1) / Double(max(1, p.count))
        let total = Double(max(1, content.chapterCount))
        var progress = (Double(current.chapter) + chapterFraction) / total
        if let total = totalPages(), total > 0 {
            let before = pageCounts[0..<current.chapter].reduce(0) { $0 + ($1 ?? 0) }
            progress = Double(before + current.page + 1) / Double(total)
        }
        if current.chapter == content.chapterCount - 1 && current.page == p.count - 1 { progress = 1 }
        book.progress = min(1, max(0, progress))
        book.chapter = current.chapter
        book.offset = currentOffset()
        progressLabel.text = "\(Int((book.progress * 100).rounded())) %"
        progressLabel.sizeToFit()
        if !slider.isTracking { slider.value = Float(book.progress) }
        if turned { timer.activity(pageTurn: true) }
    }
    private func savePosition() {
        // берём свежую запись (там могут быть новые закладки) и меняем только место чтения
        guard var fresh = Store.shared.book(book.id) else { return }
        fresh.progress = book.progress
        fresh.chapter = book.chapter
        fresh.offset = book.offset
        fresh.lastOpenedAt = Date()
        Store.shared.update(fresh)
        book = fresh
    }
    private var currentRange: NSRange {
        guard let p = chapters[current.chapter], current.page < p.ranges.count else { return NSRange(location: 0, length: 0) }
        return p.ranges[current.page]
    }
    private func updateBookmarkIcon() {
        let r = currentRange
        let marked = (Store.shared.book(book.id)?.bookmarks ?? []).contains { $0.chapter == current.chapter && NSLocationInRange($0.offset, r) }
        _ = marked
    }
    @objc private func toggleBookmark() {
        let r = currentRange
        let text = (chapters[current.chapter]?.text.string.string ?? "") as NSString
        let snipRange = NSRange(location: r.location, length: min(140, max(0, min(r.length, text.length - r.location))))
        let snippet = text.length > 0 && snipRange.location < text.length ? text.substring(with: snipRange) : ""
        let added = Store.shared.toggleBookmark(bookID: book.id, chapter: current.chapter, range: r,
                                                snippet: snippet.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
        UIImpactFeedbackGenerator(style: added ? .medium : .light).impactOccurred()
        updateBookmarkIcon()
    }

    // MARK: перелистывание
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let v = vc as? PageViewController else { return nil }
        let p = pages(v.chapter)
        if v.page + 1 < p.count { return pageController(v.chapter, v.page + 1) }
        if v.chapter + 1 < content.chapterCount { return pageController(v.chapter + 1, 0) }
        return nil
    }
    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let v = vc as? PageViewController else { return nil }
        if v.page > 0 { return pageController(v.chapter, v.page - 1) }
        if v.chapter > 0 { let prev = pages(v.chapter - 1); return pageController(v.chapter - 1, prev.count - 1) }
        return nil
    }
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let v = pvc.viewControllers?.first as? PageViewController else { return }
        current = (v.chapter, v.page)
        pageChanged()
        savePosition()
    }

    // MARK: касания
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        timer.activity(pageTurn: false)
        if touch.view is UIControl { return false }               // нажатие на кнопку — не перелистывание
        let x = touch.location(in: view).x
        if g === sideTap { return x <= view.bounds.width * 0.3 || x >= view.bounds.width * 0.7 }
        return x > view.bounds.width * 0.3 && x < view.bounds.width * 0.7
    }
    // тап-зоны: обычные — встроенные в перелистывание; поменянные — свои
    private func applyTapZones() {
        let swap = settings.swapTapZones
        for g in pageVC.gestureRecognizers where g is UITapGestureRecognizer { g.isEnabled = !swap }
        sideTap.isEnabled = swap
    }
    @objc private func sideTapped(_ g: UITapGestureRecognizer) {
        guard !turning, let cur = pageVC.viewControllers?.first else { return }
        let left = g.location(in: view).x < view.bounds.width / 2
        let forward = settings.swapTapZones ? left : !left
        let next = forward ? pageViewController(pageVC, viewControllerAfter: cur) : pageViewController(pageVC, viewControllerBefore: cur)
        guard let vc = next as? PageViewController else { return }
        turning = true
        pageVC.setViewControllers([vc], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
            self?.turning = false
        }
        current = (vc.chapter, vc.page)
        pageChanged()
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    @objc private func centerTap(_ g: UITapGestureRecognizer) {
        chromeHidden.toggle()
        for b in chromeButtons { b.isUserInteractionEnabled = !chromeHidden }
        UIView.animate(withDuration: 0.25) {
            for b in self.chromeButtons {
                b.alpha = self.chromeHidden ? 0 : 1
                b.transform = self.chromeHidden ? CGAffineTransform(scaleX: 0.85, y: 0.85) : .identity
            }
        }
    }
    /// Оглавление — слева сверху, «Аа» — справа сверху — на уровне Dynamic Island (там, где были время и батарея)
    private func layoutChromeButtons() {
        let safe = view.window?.safeAreaInsets ?? view.safeAreaInsets
        let size: CGFloat = 40, gap: CGFloat = 10
        let centerY = safe.top >= 40 ? safe.top * 0.5 + 1 : 12 + size / 2     // с «островком» — по его центру, иначе — у верхнего края
        let left = max(safe.left, 0) + 18, right = view.bounds.width - max(safe.right, 0) - 18
        let saved = chromeButtons.map { $0.transform }
        for b in chromeButtons { b.transform = .identity }
        _ = gap
        let w = view.bounds.width
        if safe.top >= 40 && w < view.bounds.height {
            // посередине между краем Dynamic Island (~126 pt шириной) и краем экрана
            let mid = (w - 126) / 4
            tocButton.frame = CGRect(x: mid - size / 2, y: centerY - size / 2, width: size, height: size)
            settingsButton.frame = CGRect(x: w - mid - size / 2, y: centerY - size / 2, width: size, height: size)
        } else {
            tocButton.frame = CGRect(x: left, y: centerY - size / 2, width: size, height: size)
            settingsButton.frame = CGRect(x: right - size, y: centerY - size / 2, width: size, height: size)
        }
        // «Назад» — внизу слева, в закруглении экрана
        let bottomY = view.bounds.height - size - max(safe.bottom, 12) * 0.25 - 4
        backButton.frame = CGRect(x: left + 12, y: bottomY, width: size, height: size)
        for (b, t) in zip(chromeButtons, saved) { b.transform = t }
        for b in chromeButtons { view.bringSubviewToFront(b) }
    }

    // MARK: меню выделения — «В цитаты» и «Поделиться»
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let s = textView.textStorage.string as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= s.length else { return nil }
        let text = s.substring(with: range)
        timer.activity(pageTurn: false)
        let quote = UIAction(title: "В цитаты", image: UIImage(systemName: "quote.opening")) { [weak self] _ in
            guard let self else { return }
            Store.shared.addQuote(text, book: self.book)
            textView.selectedRange = NSRange(location: 0, length: 0)
        }
        let share = UIAction(title: "Поделиться", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            guard let self else { return }
            let q = Quote(bookID: self.book.id, bookTitle: self.book.title, bookAuthor: self.book.author, text: text)
            self.share([q.signed], from: textView)
        }
        return UIMenu(children: [quote, share])
    }
    private func share(_ items: [Any], from source: UIView) {
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        avc.popoverPresentationController?.sourceView = source
        present(avc, animated: true)
    }

    // MARK: шкала книги — перемотка в любое место
    private func target(for v: Float) -> (chapter: Int, page: Int) {
        if let total = totalPages(), total > 0 {
            var g = min(total - 1, max(0, Int(Double(v) * Double(total))))
            for (c, n) in pageCounts.enumerated() {
                let k = n ?? 0
                if g < k { return (c, min(g, pages(c).count - 1)) }
                g -= k
            }
        }
        let n = max(1, content.chapterCount)
        let x = Double(min(max(v, 0), 1)) * Double(n)
        let c = min(n - 1, Int(x))
        let p = pages(c)
        let page = min(p.count - 1, max(0, Int((x - Double(c)) * Double(p.count))))
        return (c, page)
    }
    @objc private func sliderMoved() {
        progressLabel.text = "\(Int((slider.value * 100).rounded())) %"
        progressLabel.sizeToFit()
        timer.activity(pageTurn: false)
    }
    @objc private func sliderReleased() {
        let t = target(for: slider.value)
        show(t.chapter, t.page, animated: false, forward: true)
        savePosition()
    }

    // MARK: кнопки
    @objc private func close() { dismiss(animated: true) }
    @objc private func smaller() { changeFont(-1) }
    @objc private func larger() { changeFont(1) }
    private func changeFont(_ d: CGFloat) {
        let off = currentOffset()
        settings.fontSize = min(34, max(14, settings.fontSize + d))
        settings.save()
        relayout(goTo: current.chapter, offset: off)
    }
    private func themeMenu() -> UIMenu {
        UIMenu(children: PaperTheme.allCases.map { t in
            UIAction(title: t.name, state: t == settings.theme ? .on : .off) { [weak self] _ in
                guard let self else { return }
                let off = self.currentOffset()
                self.settings.theme = t
                self.settings.save()
                self.relayout(goTo: self.current.chapter, offset: off)
                self.setNeedsStatusBarAppearanceUpdate()
            }
        })
    }
    @objc private func showSettings() {
        let off = currentOffset()
        let host = UIHostingController(rootView: ReaderSettingsView(settings: settings) { [weak self] new in
            guard let self else { return }
            let needsLayout = new.fontSize != self.settings.fontSize || new.lineSpacing != self.settings.lineSpacing
                || new.fontFamily != self.settings.fontFamily
                || new.theme != self.settings.theme || new.topInset != self.settings.topInset
                || new.bottomInset != self.settings.bottomInset
                || new.fontWeight != self.settings.fontWeight || new.hyphenate != self.settings.hyphenate
            self.settings = new
            new.save()
            if needsLayout { self.relayout(goTo: self.current.chapter, offset: off) }
            self.applyOrientation()
            self.applyTapZones()
        })
        if let sheet = host.sheetPresentationController { sheet.detents = [.medium()]; sheet.prefersGrabberVisible = true }
        present(host, animated: true)
    }
    @objc private func showToc() {
        let entries = content.toc.isEmpty
            ? (0..<content.chapterCount).map { TocEntry(title: "Глава \($0 + 1)", chapter: $0, anchor: nil, block: nil, level: 1) }
            : content.toc
        let host = UIHostingController(rootView: TocView(entries: entries, currentChapter: current.chapter, bookID: book.id,
            onSelect: { [weak self] e in
                self?.dismiss(animated: true)
                self?.go(to: e)
            },
            onBookmark: { [weak self] bm in
                guard let self else { return }
                self.dismiss(animated: true)
                let p = self.pages(bm.chapter)
                self.show(bm.chapter, p.page(containing: bm.offset), animated: true, forward: bm.chapter >= self.current.chapter)
                self.savePosition()
            },
            currentPlace: (current.chapter, currentRange),
            onToggleBookmark: { [weak self] in self?.toggleBookmark() },
            progress: book.progress,
            liveSeconds: timer.currentSeconds,
            placeLabel: { [weak self] v in
                guard let self else { return "" }
                let c = min(max(0, self.content.chapterCount - 1), Int(v * Double(max(1, self.content.chapterCount))))
                return entries.last(where: { $0.chapter <= c })?.title ?? "Глава \(c + 1)"
            },
            onSeek: { [weak self] v in
                guard let self else { return }
                self.timer.activity(pageTurn: false)
                let t = self.target(for: Float(v))
                self.show(t.chapter, t.page, animated: false, forward: true)
                self.savePosition()
            }).environmentObject(Store.shared))
        if let sheet = host.sheetPresentationController { sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true }
        present(host, animated: true)
    }
    private func go(to e: TocEntry) {
        let p = pages(e.chapter)
        var offset = 0
        if let a = e.anchor, let o = p.text.anchors[a] { offset = o }
        else if let b = e.block, b < p.text.blockStarts.count { offset = p.text.blockStarts[b] }
        show(e.chapter, p.page(containing: offset), animated: true, forward: e.chapter >= current.chapter)
        savePosition()
    }
}

// MARK: - Таймер чтения: время идёт, только пока открыт текст и есть активность (20 с)

final class ReadingTimer {
    private let bookID: UUID
    private var startProgress: Double
    private var seconds = 0
    private var pages = 0
    private var sessionStart = Date()
    private var lastActivity = Date()
    private var lastTick = Date()
    private var tick: Timer?
    private let motion = CMMotionManager()
    static let idleLimit: TimeInterval = 20

    init(bookID: UUID, startProgress: Double) { self.bookID = bookID; self.startProgress = startProgress }

    func start() {
        sessionStart = Date(); lastActivity = Date(); lastTick = Date(); seconds = 0; pages = 0
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.25
            motion.startDeviceMotionUpdates()
        }
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.beat() }
    }
    func resume() { if tick == nil { start() } }
    var currentSeconds: Int { seconds }
    func activity(pageTurn: Bool) {
        lastActivity = Date()
        if pageTurn { pages += 1 }
    }
    private func beat() {
        let now = Date()
        if let m = motion.deviceMotion {
            let r = m.rotationRate, a = m.userAcceleration
            if r.x * r.x + r.y * r.y + r.z * r.z > 0.03 * 0.03 || a.x * a.x + a.y * a.y + a.z * a.z > 0.02 * 0.02 { lastActivity = now }
        }
        let d = now.timeIntervalSince(lastTick)
        lastTick = now
        if d > 0, d <= 5, now.timeIntervalSince(lastActivity) <= ReadingTimer.idleLimit { seconds += Int(d.rounded()) }
    }
    func pause(progress: Double) { flush(progress: progress); tick?.invalidate(); tick = nil; motion.stopDeviceMotionUpdates() }
    func stop(progress: Double) { pause(progress: progress) }
    private func flush(progress: Double) {
        if seconds >= 5 {
            Store.shared.addSession(ReadingSession(bookID: bookID, start: sessionStart, seconds: seconds, pages: pages,
                                                   progressFrom: startProgress, progressTo: progress))
        }
        startProgress = progress
        seconds = 0; pages = 0; sessionStart = Date()
    }
}

// MARK: - Поворот экрана: библиотека всегда вертикально, книга — по настройке

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
    static func set(_ m: UIInterfaceOrientationMask, from window: UIWindow?) {
        mask = m
        guard let window, let scene = window.windowScene else { return }
        var vc = window.rootViewController
        while let v = vc {
            v.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = v.presentedViewController
        }
        if m == .portrait || m == .landscapeLeft || m == .landscapeRight {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Diagnostics.installCrashHandlers()
        return true
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

// MARK: - SwiftUI-обёртка

struct ReaderScreen: UIViewControllerRepresentable {
    let book: Book
    func makeUIViewController(context: Context) -> UINavigationController {
        let url = Store.shared.fileURL(book)
        let root: UIViewController
        if let content = BookParser.open(url: url, format: book.format) {
            root = ReaderViewController(book: book, content: content)
        } else {
            root = UIHostingController(rootView: Text("Не удалось открыть книгу").foregroundStyle(.secondary))
        }
        let nav = UINavigationController(rootViewController: root)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }
    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
}
