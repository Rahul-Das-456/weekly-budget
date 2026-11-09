import SwiftUI
import PhotosUI
import Vision

// MARK: - Reading a screenshot

/// One line of text found in a screenshot. Rect is normalized (0...1) with the origin at the top left.
struct OCRLine {
    var text: String
    var rect: CGRect
}

/// A charge read from a card app screenshot, waiting for the user to review it.
struct ScannedTransaction: Identifiable {
    let id = UUID()
    var merchant: String
    var amount: Double
    /// Nil when the row said "Pending" or had no date: those count as today.
    var date: Date?
    var categoryID: UUID?
    var include = true
    /// Why it starts unchecked, shown under the row.
    var warning: String?
}

enum ScreenshotReader {
    /// Runs Apple's on-device text recognition. Nothing leaves the phone.
    static func lines(in image: CGImage) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // merchant names aren't words
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let b = obs.boundingBox
            return OCRLine(text: text.trimmingCharacters(in: .whitespaces),
                           rect: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
    }

    private static let amountPattern = /^-?\$\s?[\d,]+\.\d{2}$/
    private static let monthDay = /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.? \d{1,2}(, \d{4})?$/
    private static let slashDate = /^\d{1,2}\/\d{1,2}(\/\d{2,4})?$/

    static func amount(_ s: String) -> Double? {
        guard s.wholeMatch(of: amountPattern) != nil else { return nil }
        let digits = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(digits)
    }

    static func date(_ s: String, now: Date = .now) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let cleaned = s.replacingOccurrences(of: ".", with: "")
        for format in ["MMM d, yyyy", "MMMM d, yyyy", "M/d/yyyy", "M/d/yy"] {
            f.dateFormat = format
            if let d = f.date(from: cleaned) { return d }
        }
        // No year: pick this year, or last year if that would be in the future (a January screenshot of December).
        let cal = Calendar.current
        for format in ["MMM d", "MMMM d", "M/d"] {
            f.dateFormat = format
            guard let d = f.date(from: cleaned) else { continue }
            var parts = cal.dateComponents([.month, .day], from: d)
            parts.year = cal.component(.year, from: now)
            if let withYear = cal.date(from: parts) {
                return withYear > now ? cal.date(byAdding: .year, value: -1, to: withYear) : withYear
            }
        }
        return nil
    }

    static func isDateLine(_ s: String) -> Bool {
        s.wholeMatch(of: monthDay) != nil || s.wholeMatch(of: slashDate) != nil
    }

    /// Turns the text of a transaction list into charges.
    ///
    /// Many bank apps show the running balance right under each charge; those are skipped. Each charge owns the
    /// left-hand text from just above it down to the next charge: a date or "Pending", then the merchant.
    static func transactions(from lines: [OCRLine], now: Date = .now) -> [ScannedTransaction] {
        let all = lines.filter { amount($0.text) != nil && $0.rect.midX > 0.5 }.sorted { $0.rect.minY < $1.rect.minY }
        guard !all.isEmpty else { return [] }

        // A running balance sits right under its charge, almost touching it. Rows are much further apart.
        // So when an amount has another one tucked just below it, the lower one is a balance and is skipped.
        var amounts: [OCRLine] = []
        var i = 0
        while i < all.count {
            amounts.append(all[i])
            if i + 1 < all.count, all[i + 1].rect.minY - all[i].rect.maxY < all[i].rect.height * 0.5 { i += 2 } else { i += 1 }
        }

        let gaps = zip(amounts, amounts.dropFirst()).map { $1.rect.minY - $0.rect.minY }.sorted()
        let rowHeight = gaps.isEmpty ? 0.1 : gaps[gaps.count / 2]
        let left = lines.filter { $0.rect.minX < 0.5 && amount($0.text) == nil }

        var result: [ScannedTransaction] = []
        for (i, a) in amounts.enumerated() {
            guard let value = amount(a.text), value > 0 else { continue }   // payments and refunds are negative
            let top = a.rect.minY - a.rect.height / 2
            let bottom = i + 1 < amounts.count ? amounts[i + 1].rect.minY - amounts[i + 1].rect.height / 2 : a.rect.minY + rowHeight
            let row = left.filter { $0.rect.midY > top && $0.rect.midY < bottom }.sorted { $0.rect.minY < $1.rect.minY }
            var date: Date?
            var merchant: String?
            for line in row {
                if line.text.lowercased().hasPrefix("pending") { continue }
                if isDateLine(line.text) { date = date ?? Self.date(line.text, now: now); continue }
                if merchant == nil { merchant = line.text }
            }
            result.append(ScannedTransaction(merchant: merchant ?? "Unknown", amount: value, date: date))
        }
        return result
    }

    private static let usStates: Set<String> = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]

    /// "TST*PARLOR PIZZA - RIVER" → "Parlor Pizza - River", "TACO BELL 733484" → "Taco Bell".
    static func cleanName(_ raw: String) -> String {
        var s = raw.uppercased()
        for prefix in ["TST* ", "TST*", "TST ", "SQ *", "SQ*", "SP * ", "SP *", "SP ", "PY *", "DD *", "PP*", "PAYPAL *"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count); break
        }
        // Trailing " CHICAGO IL" when the city is on the same line. Only one city word, so a name isn't eaten.
        if let m = s.firstMatch(of: /\s[A-Z]+\s([A-Z]{2})$/), usStates.contains(String(m.1)) {
            s.removeSubrange(m.range)
        }
        s = s.replacing(/\s+#?\d{3,}$/, with: "")                  // store numbers
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? raw : s.capitalized
    }
}

// MARK: - Picking a category

enum MerchantCategorizer {
    private static let learnedKey = "import.merchantCategories"

    /// What the user picked for each merchant last time, so the next import gets it right.
    static func remember(_ merchant: String, _ id: UUID) {
        var map = UserDefaults.standard.dictionary(forKey: learnedKey) as? [String: String] ?? [:]
        map[merchant.uppercased()] = id.uuidString
        UserDefaults.standard.set(map, forKey: learnedKey)
    }

    private struct Rule { var merchantWords: [String]; var categoryWords: [String] }

    // Order matters: "UBER EATS" is food, a tea bar is coffee before it's food.
    private static let rules = [
        Rule(merchantWords: ["UBER EATS", "UBEREATS", "DOORDASH", "GRUBHUB", "CAVIAR", "SEAMLESS"], categoryWords: ["food", "dining", "restaurant", "eat"]),
        Rule(merchantWords: ["JEWEL", "WHOLE FOODS", "WHOLEFDS", "TRADER JOE", "MARIANO", "ALDI", "COSTCO", "KROGER", "SAFEWAY", "GROCER", "H MART", "FOOD 4 LESS", "INSTACART", "SUPERMARKET", "MARKET", "TARGET", "WALMART"], categoryWords: ["grocer"]),
        Rule(merchantWords: ["STARBUCKS", "DUNKIN", "COFFEE", "CAFE", "TEA", "ESPRESSO", "BOBA", "PEET", "INTELLIGENTSIA", "BLUE BOTTLE", "LATTE"], categoryWords: ["coffee", "cafe", "tea"]),
        Rule(merchantWords: ["UBER", "LYFT", "VENTRA", "CTA", "DIVVY", "METRA", "TAXI", "CURB", "PARKING", "SHELL", "BP ", "CHEVRON", "SPEEDWAY"], categoryWords: ["uber", "lyft", "ride", "transit", "transport", "travel", "car", "gas"]),
        Rule(merchantWords: ["NETFLIX", "SPOTIFY", "HULU", "AMC", "REGAL", "TICKETMASTER", "STUBHUB", "STEAM", "PLAYSTATION", "XBOX", "NINTENDO", "CINEMA", "THEATER", "THEATRE", "DISNEY", "HBO", "MAX.COM", "BOWL", "CONCERT", "MUSEUM"], categoryWords: ["entertain", "fun", "movie", "game"]),
        Rule(merchantWords: ["TST", "SQ ", "SQ*", "PIZZA", "TACO", "BURGER", "GRILL", "KITCHEN", "CHIPOTLE", "MCDONALD", "SUBWAY", "SUSHI", "THAI", "RESTAURANT", "DINER", "BBQ", "WINGSTOP", "CHICK-FIL-A", "PANERA", "SWEETGREEN", "CAVA", "POTBELLY", "PORTILLO", "WENDY", "POPEYES", "KFC", "FIVE GUYS", "SHAKE SHACK", "RAMEN", "PHO", "BAKERY", "DELI", "TAVERN", "PUB"], categoryWords: ["food", "dining", "restaurant", "eat"]),
    ]

    private static func category(matching words: [String], in categories: [BudgetCategory]) -> UUID? {
        categories.first { c in words.contains { c.name.lowercased().contains($0) } }?.id
    }

    /// Best guess: what the user chose for this merchant before, then keywords, then Food.
    static func guess(raw: String, clean: String, in categories: [BudgetCategory]) -> UUID? {
        let map = UserDefaults.standard.dictionary(forKey: learnedKey) as? [String: String] ?? [:]
        if let saved = map[clean.uppercased()], let id = UUID(uuidString: saved), categories.contains(where: { $0.id == id }) {
            return id
        }
        let upper = " " + raw.uppercased() + " "
        for rule in rules where rule.merchantWords.contains(where: { word in
            // Short words must stand alone so "TEA" doesn't match "STEAK".
            word.count <= 3 ? upper.contains(" \(word) ") || upper.contains(" \(word)*") : upper.contains(word)
        }) {
            if let id = category(matching: rule.categoryWords, in: categories) { return id }
        }
        // Most card charges that match nothing are restaurants.
        return category(matching: ["food", "dining", "restaurant", "eat"], in: categories) ?? categories.first?.id
    }
}

// MARK: - Review sheet

/// Where the screenshots come from: the photo picker, or files in Documents (for testing).
enum ImportSource {
    case photos([PhotosPickerItem])
    case files([URL])
}

struct ImportReviewView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    let source: ImportSource
    @State private var items: [ScannedTransaction] = []
    @State private var loading = true
    @State private var failed = false

    private var chosen: [ScannedTransaction] { items.filter { $0.include && $0.categoryID != nil && $0.amount > 0 } }

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading screenshot…").foregroundStyle(.secondary)
                    }
                    .themedRow()
                } else if items.isEmpty {
                    ContentUnavailableView("No charges found", systemImage: "text.viewfinder",
                                           description: Text(failed
                                                             ? "Couldn't open that image. Try another screenshot."
                                                             : "Use a screenshot of your card app's transaction list, with the amounts showing."))
                        .themedRow()
                } else {
                    Section {
                        ForEach($items) { $item in
                            ImportRow(item: $item)
                        }
                    } header: {
                        Text("Found \(items.count) charge\(items.count == 1 ? "" : "s")")
                    } footer: {
                        Text("Check the category and amount for each one. Unchecked rows aren't added. Next time, merchants go to the category you pick now.")
                    }
                    .themedRow()

                    let totals = store.categories.compactMap { c -> (BudgetCategory, Double)? in
                        let sum = chosen.filter { $0.categoryID == c.id }.reduce(0) { $0 + $1.amount }
                        return sum > 0 ? (c, sum) : nil
                    }
                    if !totals.isEmpty {
                        Section("Adds to") {
                            ForEach(totals, id: \.0.id) { c, sum in
                                HStack {
                                    ThemedLabel(c.name, systemImage: c.icon)
                                    Spacer()
                                    Text(sum.money).monospacedDigit()
                                }
                            }
                        }
                        .themedRow()
                    }
                }
            }
            .themedList()
            .navigationTitle("Import charges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(chosen.count)") { addChosen() }
                        .disabled(chosen.isEmpty)
                        .accessibilityIdentifier("import-add")
                }
            }
            .task { await load() }
        }
        .themed()
    }

    private func addChosen() {
        for item in chosen {
            guard let id = item.categoryID else { continue }
            store.add(item.amount, to: id, note: item.merchant, date: item.date ?? .now)
            MerchantCategorizer.remember(item.merchant, id)
        }
        dismiss()
    }

    private func load() async {
        var images: [CGImage] = []
        switch source {
        case .photos(let picks):
            for p in picks {
                if let data = try? await p.loadTransferable(type: Data.self), let img = UIImage(data: data)?.cgImage { images.append(img) }
            }
        case .files(let urls):
            for u in urls {
                if let img = UIImage(contentsOfFile: u.path)?.cgImage { images.append(img) }
            }
        }
        failed = images.isEmpty
        let found = await Task.detached(priority: .userInitiated) {
            images.map { (try? ScreenshotReader.transactions(from: ScreenshotReader.lines(in: $0))) ?? [] }
        }.value
        items = prepare(found)
        loading = false
        #if DEBUG
        for t in items {
            print("IMPORT", t.merchant, t.amount, t.date.map { "\($0)" } ?? "pending",
                  store.category(t.categoryID ?? UUID())?.name ?? "-", t.include, t.warning ?? "")
        }
        #endif
    }

    /// Cleans names, guesses categories and unchecks rows that probably shouldn't be added.
    private func prepare(_ perImage: [[ScannedTransaction]]) -> [ScannedTransaction] {
        var out: [ScannedTransaction] = []
        func key(_ t: ScannedTransaction) -> String { "\(t.merchant.uppercased())|\(t.amount)|\(t.date?.timeIntervalSince1970 ?? 0)" }
        for list in perImage {
            // Screenshots taken while scrolling overlap: skip a row an earlier screenshot already had.
            let seen = Set(out.map(key))
            for var t in list {
                let raw = t.merchant
                t.merchant = ScreenshotReader.cleanName(raw)
                if seen.contains(key(t)) { continue }
                t.categoryID = MerchantCategorizer.guess(raw: raw, clean: t.merchant, in: store.categories)
                let upper = raw.uppercased()
                if upper.contains("AUTH HOLD") || upper.contains("TEMP HOLD") || upper.contains("PRE-AUTH") {
                    t.include = false
                    t.warning = "Temporary hold. The real charge usually replaces it."
                } else if let d = t.date, d < store.weekStart {
                    t.include = false
                    t.warning = "From a past week."
                } else if store.expenses.contains(where: { abs($0.amount - t.amount) < 0.005 && $0.note.caseInsensitiveCompare(t.merchant) == .orderedSame }) {
                    t.include = false
                    t.warning = "Already added this week."
                }
                out.append(t)
            }
        }
        return out
    }
}

private struct ImportRow: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @Binding var item: ScannedTransaction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { item.include.toggle() } label: {
                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.include ? theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.include ? "Included" : "Not included")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.merchant).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    TextField("0", value: $item.amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 100)
                }
                HStack {
                    Text(item.date.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Pending")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Category", selection: $item.categoryID) {
                        ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                if let w = item.warning {
                    Text(w).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .opacity(item.include ? 1 : 0.6)
        .padding(.vertical, 2)
    }
}
