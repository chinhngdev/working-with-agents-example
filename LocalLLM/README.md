# LocalLLM

Ứng dụng học tiếng Anh dùng LLM chạy on-device (local, không cần internet/server). Định vị cuối: **privacy-first, offline-first**.

## Lộ trình

**macOS trước (công cụ test/kiểm chứng) → iOS sau (đích thương mại).**

Ban đầu dự định làm iOS trước, nhưng đổi sang macOS trước vì:

- Vòng lặp dev nhanh hơn hẳn: build-and-run không cần simulator/thiết bị, test target chạy native, debug bằng Instruments trực tiếp.
- Mac Apple Silicon có RAM hợp nhất lớn hơn iPhone nhiều — thử được model 7B–13B để dò "trần chất lượng" trước khi thu hẹp xuống 1–4B khả thi trên iPhone.
- Rủi ro kỹ thuật lớn nhất nằm ở LLM Engine (load model, streaming, quản lý bộ nhớ, chất lượng prompt), không phải UI di động — nên validate phần khó nhất trước trên nền tảng dễ debug nhất.
- Kiến trúc tách `DomainKit`/`LLMEngineKit`/`PersistenceKit` khỏi UI ngay từ đầu nên các package này build được cho cả 2 platform mà không cần viết lại — chỉ tầng View khác biệt.

**Quan trọng — macOS không phải kênh phát hành thương mại.** Nghiên cứu thị trường không tìm thấy bằng chứng nào cho thấy macOS là thị trường khả thi cho app học ngôn ngữ: Apple không tách báo cáo doanh thu Mac App Store riêng (quá nhỏ so với iOS), không có đối thủ macOS-native nghiêm túc nào trong mảng này, không có case "macOS-first rồi mới iOS" nào từng thành công trong edtech/AI companion, và kỳ vọng giá của cộng đồng local-LLM trên Mac nghiêng hẳn về miễn phí/one-time fee thấp. Vai trò của bản macOS là **công cụ nội bộ để kiểm chứng model/prompt/kiến trúc**, không phải bước đi go-to-market — không đầu tư polish UI/marketing cho nó như một sản phẩm bán được.

### Cách bật macOS trên project hiện tại

Project scaffold hiện tại (`LocalLLM.xcodeproj`) đang cấu hình `SDKROOT = iphoneos`, chỉ target iOS. Thêm macOS như một Supported Destination bổ sung của cùng target (SwiftUI multiplatform app), không tạo project/target riêng:

1. Target `LocalLLM` → tab **General** → **Supported Destinations** → bấm **+** → thêm **Mac**.
2. Tab **Signing & Capabilities**: App Sandbox mặc định bật cho macOS — thêm entitlement **Outgoing Connections (Client)** để tải model từ Hugging Face, và **Audio Input** cho luyện phát âm.
3. Minimum deployment target: **macOS 15 (Sequoia)** — đủ cho MLX Swift + Swift 6 concurrency runtime.
4. Bọc UI khác biệt nền tảng bằng `#if os(macOS)` / `#if os(iOS)` — chỉ ở lớp View gốc.
5. `DomainKit`, `PersistenceKit`, `LLMEngineKit` giữ nguyên, không cần sửa vì protocol-first, không phụ thuộc UIKit/AppKit.

### Tiêu chí chuyển sang iOS

Coi bản macOS là "xong giai đoạn 1" khi:

- Đã chọn được model + cấu hình prompt cho ít nhất 2–3 feature MVP (Grammar Checker, Vocabulary Builder, Conversation Practice) cho kết quả chấp nhận được **ở mức model 1–4B**, không chỉ ở mức 7B+.
- Đã đo được ngân sách bộ nhớ/tốc độ thực tế (qua Model Comparison View) để suy ra model nào khả thi trên iPhone.
- `LLMEngineKit` đã ổn định về API (load/unload/stream/cancel) để không phải đổi lại khi thêm engine Foundation Models cho iOS.

## Kiến trúc

**MVVM + Clean-lite trên nền Observation** (Swift 6, `@Observable`), không dùng TCA — chi phí boilerplate của TCA không xứng đáng khi phần phức tạp nhất nằm ở tầng Data/Engine chứ không phải state UI.

Ba tầng: **View (SwiftUI)** → **ViewModel (`@Observable`, `@MainActor`)** → **Domain (protocol-first services)** → **Data (SwiftData repositories + LLM Engine)**. ViewModel chỉ phụ thuộc protocol của Domain, không biết implementation cụ thể — nền tảng để test bằng mock.

**Nguyên tắc:** View là nơi duy nhất được phép khác biệt giữa 2 platform. ViewModel và Domain luôn dùng chung.

### Modul hóa qua Swift Package Manager

| Package | Vai trò |
|---|---|
| `DomainKit` | Models thuần Swift (Codable/Sendable) + protocol service, không import SwiftData/UIKit/AppKit |
| `PersistenceKit` | SwiftData models + repository, conform protocol của DomainKit |
| `LLMEngineKit` | Protocol trừu tượng LLM engine + implementation cụ thể (MLX, sau này Foundation Models) |
| `DesignSystemKit` | Component UI dùng chung, chỉ SwiftUI (tùy chọn) |

Khai báo mỗi package `platforms: [.macOS(.v15), .iOS(.v18)]` trong `Package.swift` — nếu lỡ `import AppKit` vào package dùng chung, build iOS fail ngay, đóng vai trò cơ chế bắt lỗi tự nhiên. Dependency injection diễn ra ở composition root (`LocalLLMApp.swift`); app target chỉ phụ thuộc DomainKit qua protocol.

### Local LLM Engine — trừu tượng qua protocol

```swift
protocol LLMEngine: Sendable {
    func loadModel(_ descriptor: ModelDescriptor) async throws
    func unloadModel() async
    var loadedModel: ModelDescriptor? { get async }
    func generate(prompt: LLMPrompt, config: GenerationConfig)
        -> AsyncThrowingStream<LLMToken, Error>
}
```

- Implementation cụ thể (`MLXEngine`, sau này `FoundationModelsEngine`) đều conform `LLMEngine`, sống trong `LLMEngineKit` — chọn qua factory, không lock vào 1 SDK.
- Mỗi engine là một `actor`, serialize truy cập model để tránh race khi load/unload, tự quản lý vòng đời bộ nhớ GPU/Neural Engine.
- Streaming: token trả về qua `AsyncThrowingStream`; ViewModel `for try await` trên `@MainActor`, engine chạy nền trên executor riêng.
- Quản lý bộ nhớ: `ModelManager` actor riêng theo dõi model đang load, evict khi có cảnh báo memory pressure. Trên macOS có thể giữ model loaded lâu dài (RAM dư dả); trên iOS cần logic unload chủ động hơn.
- Lưu trữ: weights nằm dạng file trong `Application Support/<bundle-id>/Models/<modelID>/`, tải qua `URLSession` riêng (background session) — SwiftData chỉ lưu metadata (`ModelDescriptor`), không lưu blob nặng.

### UI đặc thù macOS

- Root navigation: macOS dùng `NavigationSplitView` 3 cột (sidebar 6 feature → danh sách → detail); iOS dùng `TabView` + `NavigationStack` trong mỗi tab. Tách qua `RootView_macOS.swift`/`RootView_iOS.swift`, dùng chung `RootViewModel`.
- **Multi-window:** Conversation Practice và Flashcards hỗ trợ mở cửa sổ riêng qua `WindowGroup(id:)` + `openWindow(id:)`. Thiết kế mỗi window có `NavigationPath` riêng ngay từ đầu để không phải refactor khi thêm iOS (chỉ 1 window).
- **Menu bar commands:** `CommandMenu` trong `App` cho action chính (New Conversation ⌘N, Check Grammar ⌘G) — chỉ macOS.
- **Layout responsive bắt buộc:** `.frame(minWidth:idealWidth:)` thay vì kích thước cố định, vì cửa sổ Mac resize tự do.

### Feature modules

Conversation Practice · Vocabulary Builder · Grammar Checker · Pronunciation Practice · Flashcards/Spaced Repetition · Progress Tracking — mỗi feature theo pattern View + ViewModel + Domain service, chỉ phụ thuộc protocol của `DomainKit` và `LLMEngine`, không phụ thuộc chéo lẫn nhau.

### Concurrency & testability

- ViewModel: `@MainActor @Observable`.
- Engine và domain service điều phối: `actor`; SwiftData truy cập qua `ModelActor` để an toàn cross-actor.
- Test: `LLMEngine` là protocol → `MockLLMEngine` trả stream giả lập (kể cả lỗi, delay, cancel) để test ViewModel không cần model thật. Test target chạy native trên macOS, không cần simulator — nhanh hơn nhiều so với chờ boot iOS simulator.

### Cấu trúc thư mục

Một target, hai Supported Destinations (macOS + iOS):

```
LocalLLM/
├── LocalLLM/                    # App target (destinations: macOS, iOS)
│   ├── App/                     # Composition root, DI container, Commands/ (macOS menu)
│   ├── Root/                    # RootView_macOS.swift, RootView_iOS.swift, RootViewModel.swift
│   ├── Features/
│   │   ├── Conversation/
│   │   ├── Vocabulary/
│   │   ├── GrammarChecker/
│   │   ├── Pronunciation/
│   │   ├── Flashcards/
│   │   └── Progress/            # #if os() chỉ khi layout khác nhau thật sự
│   └── Resources/
├── Packages/
│   ├── DomainKit/
│   ├── PersistenceKit/
│   ├── LLMEngineKit/            # Protocols · MLX (giai đoạn 1) · Foundation Models (giai đoạn 2) · ModelManager
│   └── DesignSystemKit/
├── LocalLLMTests/
└── LocalLLMUITests/
```

**Thứ tự triển khai:** `DomainKit` protocols → `LLMEngineKit` (bắt đầu với mock engine + MLX engine thật) → `PersistenceKit` → composition root → Conversation làm vertical slice tham chiếu cho các feature sau.

## Tech stack

### Inference: Ollama để dò UX nhanh, MLX Swift để xây kiến trúc ship thật

| | Ollama | MLX Swift |
|---|---|---|
| Tốc độ bắt đầu | Nhanh nhất — chỉ cần cài + `pull` | Cần tích hợp Swift package trước |
| Kiến trúc | Process riêng, gọi qua HTTP — không "embedded" | Swift package thuần, embed trực tiếp |
| Hiệu năng Apple Silicon | llama.cpp bên dưới + overhead HTTP | Native, unified memory + Metal — nhanh nhất |
| Port sang iOS | Không — Ollama không chạy trên iOS | Có — cùng package, cùng API |
| Vai trò | Prototype UX/prompt, loại bỏ trước khi ship | Kiến trúc chính thức, giữ nguyên khi sang iOS |

Dùng Ollama để chốt UX/prompt engineering thật nhanh, nhưng chuyển sang MLX Swift càng sớm càng tốt ngay khi UX rõ hình hài — không để lối viết code gọi HTTP ăn sâu vào kiến trúc.

**Giai đoạn iOS sau này:** bổ sung Apple Foundation Models framework (iOS 26+) làm engine mặc định (model ~3B của Apple Intelligence, zero-setup, structured output có sẵn); MLX Swift giữ lại làm fallback cho máy không hỗ trợ hoặc cần model tùy chỉnh.

Không ưu tiên: llama.cpp binding trực tiếp, Core ML qua coremltools, MediaPipe LLM Inference.

### Model để thử nghiệm trên macOS (mlx-community, 4-bit)

| Model | Vai trò |
|---|---|
| Qwen2.5-7B / Mistral-7B-v0.3 | Baseline "trần chất lượng" |
| Llama-3.1-8B / Gemma-3-9b / Phi-3.5-mini | Dải giữa |
| Llama-3.2-3B / Llama-3.2-1B / Qwen2.5-3B | **Mô phỏng giới hạn iPhone — nhóm quan trọng nhất** |

### Các thành phần khác

| Layer | Lựa chọn macOS (giai đoạn dev) | Giữ khi sang iOS? |
|---|---|---|
| Cấu trúc project | 1 target, Supported Destinations +Mac | Giữ nguyên |
| Deployment target | macOS 15 (Sequoia) | Tương ứng iOS 18 |
| UI | SwiftUI, `NavigationSplitView` + menu commands | Core views giữ nguyên |
| Speech-to-text | `SFSpeechRecognizer` (on-device) | Giữ nguyên, chỉ khác UI xin quyền |
| Text-to-speech | `AVSpeechSynthesizer` | Giữ nguyên |
| Dữ liệu app | SwiftData | Giữ nguyên |
| Tải model weights | `URLSession` background session tự viết | Giữ nguyên (Background Assets Managed cần OS 26+) |
| Concurrency | Swift Concurrency, actor cho engine | Giữ nguyên |
| Testing | Swift Testing, chạy trực tiếp destination macOS | Thêm iOS simulator ở CI |
| CI/CD | GitHub Actions, macOS runner, build matrix 2 destination | Giữ nguyên |
| Distribution | Developer ID + notarization (nội bộ/beta) | App Store/TestFlight cho iOS |
| Analytics | TelemetryDeck hoặc MetricKit-only | Giữ nguyên, khớp privacy-first |

### Entitlements & lưu ý macOS Sandbox

- Speech: entitlement `com.apple.security.device.audio-input` + khai báo `NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription`.
- Tải model: entitlement `com.apple.security.network.client` (Outgoing Connections).
- Model weights lưu tại `~/Library/Application Support/<bundle-id>/Models/` — trong App Sandbox nằm ở container riêng của app, dùng `FileManager` bình thường.

## Tính năng

### Dev-tool nội bộ — chỉ để đánh giá model/prompt

Mục tiêu chính của bản macOS là quyết định model/prompt nào dùng được cho iOS — nhóm này ưu tiên tốc độ lặp hơn UI đẹp, có thể gộp vào một "Developer Console" tách biệt khỏi trải nghiệm người dùng cuối.

- **Model Comparison View** — chạy song song N model với cùng 1 prompt, hiện output cạnh nhau + latency + tokens/giây.
  Input: `{prompt, systemPrompt, models: [...], params: {temperature, maxTokens, topP}}`
  Output mỗi model: `{modelId, text, latencyMs, tokensPerSec, tokenCount}`
- **Prompt / Parameter Lab** — chỉnh system prompt, temperature, max tokens, top-p, repetition penalty trực tiếp; lưu preset theo feature để so sánh.
- **Inference Log Inspector** — log mọi lần gọi LLM (prompt đầy đủ, raw output, thời gian load/generate, RAM dùng), export JSON/CSV.
- **Model Manager (quick switch)** — sidebar model đã tải (size, quant level), load/unload nhanh để test ngân sách RAM.

### MVP — cho người dùng cuối, tận dụng bối cảnh Mac

1. **Conversation Practice** (cửa sổ riêng, mở cả ngày) — hội thoại theo kịch bản (nhà hàng, phỏng vấn). Lịch sử giới hạn 4–6 lượt, output ngắn 1–2 câu.
   `Input: {scenario, history: [...], userLevel}` → `Output: {reply, corrections: [{original, fixed, explain}]}`
2. **Grammar & Style Checker** (paste đoạn dài) — textarea lớn, output JSON có highlight.
   `Input: {text, checkStyle}` → `Output: {issues: [{span, type, issue, suggestion}], overallScore}`
3. **Vocabulary Builder** (sidebar + detail) — sidebar từ đã lưu, detail hiện định nghĩa/ví dụ/đồng nghĩa, ôn tập kiểu flashcard.
   `Input: {word, userContext}` → `Output: {definition, examples: [...], synonyms: [...], difficulty}`
4. **Writing Assistant / Rewrite tone** — bôi đen text, chọn tone (formal/casual/concise), hiện diff trước/sau.
5. **Listening Drill dạng transcript** — LLM sinh hội thoại + câu hỏi nghe-hiểu, đọc bằng `AVSpeechSynthesizer`.
6. **Daily Review Dashboard** — tổng hợp từ vựng/lỗi lặp lại trong tuần, thuần dữ liệu local + LLM phân tích log.

### Tận dụng model lớn (7B–8B) — thử để cân nhắc lộ trình iOS

Đo bằng Model Comparison View xem chênh lệch chất lượng so với 1–4B có lớn tới mức phải cắt tính năng hay cân nhắc gọi API cloud tùy chọn khi lên iOS:

- Phân tích văn phong sâu cho essay dài 500–1000 từ, chấm theo tiêu chí IELTS/TOEFL.
- Hội thoại đa vai/nhiều lượt phức tạp (roleplay nhiều nhân vật).
- Chấm ngữ pháp kèm giải thích quy tắc chi tiết, trích dẫn quy tắc ngôn ngữ học.
- So sánh 2 bản dịch/viết lại và giải thích khác biệt sắc thái (nuance).

### V2 (sau khi có bản iOS)

- Role-play tình huống nâng cao (thương lượng, tranh luận).
- Luyện thi TOEIC/IELTS theo dạng câu hỏi có template sẵn.
- Custom scenario builder — người dùng mô tả tình huống, model tự tạo kịch bản.
- Gamification nâng cao: leaderboard cá nhân, thử thách tuần, huy hiệu.

### Không nên làm trên bản macOS

- Bất cứ gì phụ thuộc cảm biến di động (GPS, accelerometer).
- Tính năng học "tranh thủ" kiểu widget lock screen/Live Activities/thông báo ngắn — vô nghĩa với phiên làm việc dài trên Mac.
- Layout ép vào tab bar hoặc màn hình nhỏ — sẽ phải viết lại khi đích cuối là `NavigationSplitView`.
- Ghi âm ngoài trời, "học khi lái xe", tối ưu pin/thermal đặc thù iPhone.

### Nên tránh/hoãn (áp dụng cả 2 platform)

Chấm luận văn dài đầy đủ (IELTS Writing Task 2), kiến thức chuyên ngành sâu, dịch thuật đa ngôn ngữ phức tạp, hội thoại mở hoàn toàn không kịch bản, fact-checking/kiến thức tổng quát — vượt năng lực đáng tin cậy của model nhỏ chạy on-device, rủi ro feedback sai gây hại hơn lợi.

### Nguyên tắc thiết kế prompt chung

Ép output JSON có schema cố định khi kết quả cần hiển thị có cấu trúc; giới hạn `max_tokens` nhỏ cho Conversation Practice để giữ tốc độ và mạch lạc; system prompt ngắn, cụ thể, kèm 1–2 ví dụ few-shot khi dùng model 1–2B.

### Thứ tự triển khai tính năng

Model Comparison View + Prompt Lab trước (để có công cụ đánh giá) → Conversation Practice + Grammar Checker song song (MVP dễ chứng minh giá trị, ít rủi ro) → Vocabulary Builder và Writing Assistant → nhóm "model lớn" thử nghiệm cuối để quyết định roadmap iOS.

---

*Tài liệu này tổng hợp từ các phiên nghiên cứu kiến trúc, thị trường, tech stack và tính năng — cập nhật lần cuối 2026-08-26. Xem thêm bản trình bày trực quan tại artifact "LocalLLM Blueprint".*
