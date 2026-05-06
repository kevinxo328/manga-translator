# PaddleOCR Root Cause Investigation

## Goal

釐清為什麼 app 內的 PaddleOCR 實作，和 `scripts/convert_model/verify.py` 在相同 detector-crop 場景下有明顯辨識落差。

調查原則：

- 不瞎猜，每個結論都要有實驗或 artifact 支撐
- 把原因區分成 confirmed root cause、contributing factor、ruled out hypothesis
- 優先用同一批 detector crops 做 parity，比較 app runtime 與 `verify.py`

## Current Findings

目前已確認：

- `verify.py` 的 crop-level parity 正常，量化模型本身不是主因
- app 與 `scripts/convert_model/mlx_output` 使用的是同一份模型權重
- `max_pixels=1003520` 與 `max_tokens=300` 單獨不會重現 app 的 major regression
- app `smartResizeClampedDimensions()` 缺少官方 `min_pixels` 邏輯，會造成部分精度下降
- app production path 會大量產生 empty output 或 newline-only output，這是 `verify.py` 沒有的現象
- `verify.py` 使用的 `mlx_vlm` processor 預設 normalization 也是 `[0.5, 0.5, 0.5] / [0.5, 0.5, 0.5]`
- app 與 `verify.py` 的更大差異在 vision runtime 形狀與解碼策略，不是單純 mean/std
- `buildInputIds()` 與官方 tokenizer / chat template 逐 token 完全一致
- 額外 stop token `100272` 單獨不會改變 `book1` 114 crops 輸出
- `100272 + noRepeatNgramSize=3` 只會改變少數標點 / linebreak 樣本，仍不會產生空輸出
- `PaddleOCRVLRecognizer.cleanRecognizedText()` 單獨就會改掉 `18/294` 個 `verify.py` 輸出
- resize interpolation 會影響 tiny punctuation 的標點長度，但 `bicubic` / `bilinear` 仍無法單獨重現 empty output

## Evidence

### 1. `verify.py` crop-level parity 正常

命令：

```bash
scripts/convert_model/.venv/bin/python scripts/convert_model/verify.py \
  --test-images examples/book1 \
  --detector-json-output /private/tmp/paddle-detector-book1.json \
  --report-json /private/tmp/paddle-verify-book1.json
```

結果摘要：

- samples: `114`
- `avg_cer=0.0045`
- `fail_count=3`
- `empty_output_count=0`
- `quantized_loop_count=0`

Artifacts：

- detector JSON: `/private/tmp/paddle-detector-book1.json`
- report JSON: `/private/tmp/paddle-verify-book1.json`

判定：

- 同一批 detector crops 下，`verify.py` 的辨識結果整體正常
- 問題不在「量化後模型完全失真」

### 2. app 與 `mlx_output` 使用相同模型

比較檔案：

- `scripts/convert_model/mlx_output/model.safetensors`
- `~/Library/Containers/com.chunweiliu.MangaTranslator/Data/Library/Application Support/MangaTranslator/Models/PaddleOCR-VL/model.safetensors`

結果摘要：

- SHA256 完全一致：
  - `47deb4116b6d23e830b3e1e1f4d8cf82c5346197b2d9e80c2941da417429462c`

額外確認：

- container 內 `generation_config.json` 與 local 一致
- 內容只有 `eos_token_id`、`pad_token_id`、`use_cache`
- 沒有獨立的 `max_length` 或 app-only generation override

判定：

- 問題不是模型檔案版本不一致

### 3. `max_pixels` / `max_tokens` 不是主因

實驗目的：

- 驗證 app 的 `max_pixels=1003520` 與 fallback `max_tokens=300` 是否足以單獨造成 major regression

方法：

- 用同一份量化模型
- 用同一批 114 個 detector crops
- 只改 generation / processor 參數，對照 baseline 與 app-like 設定

比較設定：

- baseline: `max_pixels=2822400`, `max_tokens=1024`
- app-like: `max_pixels=1003520`, `max_tokens=300`

結果摘要：

- `diff_count 0 total 114`

判定：

- 這兩個參數單獨不會造成目前觀察到的 app regression

### 4. app resize 與官方 processor 不一致，且會傷精度

相關實作：

- app: [MangaTranslatorMLX/PaddleOCREngine.swift](../../../MangaTranslatorMLX/PaddleOCREngine.swift)
- function: `smartResizeClampedDimensions()`

已驗證差異：

- app 只處理 max-pixels clamp
- 沒有實作官方 `smart_resize` 的 `min_pixels` 下限

114 個 detector crops 的尺寸比較：

- `diff_dims 110`
- `avg_pixel_ratio_all 9.05`
- `avg_pixel_ratio_diff 9.34`
- `max_pixel_ratio 38.0`

代表樣本：

- `014#region-007`: crop `(41, 107)` / official `(224, 532)` / app `(28, 112)` / ratio `38.0`
- `007#region-012`: crop `(49, 62)` / official `(308, 364)` / app `(56, 56)` / ratio `35.75`

同模型、同 crops，只改 resize target 的辨識比較：

- `diff_count 10 total 114`
- `avg_cer 0.3184`
- `max_cer 1.0`

代表差異：

- `010#region-009`
  - official: `・・・・・・・・`
  - app-sized: `……`
- `010#region-010`
  - official: `・・・・`
  - app-sized: `・メメメ`
- `001#region-001`
  - official: `醸覧しを俺は教え子たちに速富深部を目指す`
  - app-sized: `艱聴しちゃん俺は、宗教の子供に注文深部も目指す`

判定：

- 缺少 `min_pixels` 是 confirmed contributing factor
- 但它只能解釋部分落差，不能單獨解釋大量空輸出

### 5. app production path 會產生 empty / newline-only outputs

命令：

```bash
xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark \
  -destination 'platform=macOS' \
  -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testFullBenchmark
```

測試結果：

- test succeeded
- app runtime 在 log 中大量出現：
  - `[PaddleOCREngine] Warning: Empty OCR result from smart_resize path. Tokens: []`
  - `[PaddleOCREngine] Warning: Empty OCR result from smart_resize path. Tokens: [23]`
  - `[PaddleOCREngine] Warning: Empty OCR result from smart_resize path. Tokens: [23, 23, 23]`

額外驗證：

- token `23` 可解碼為 newline `\n`
- 代表 app 有不少 case 只生成空序列或換行序列，最後被 trim 成空字串

benchmark 摘要：

- `PaddleOCR vs MangaOCR paired: 223`
- `PaddleOCR vs Vision paired: 38`
- `Unmatched PaddleOCR (vs Manga): 0`
- `Unmatched PaddleOCR (vs Vision): 185`
- `Unmatched MangaOCR: 71`
- `Unmatched Vision: 58`

Artifact：

- xcresult:
  - `/Users/chunweiliu/Library/Developer/Xcode/DerivedData/MangaTranslator-cypkamvngiuemhbwfzfuitswnslk/Logs/Test/Test-OCRBenchmark-2026.05.05_22-41-07-+0800.xcresult`

判定：

- `verify.py` 沒有 empty outputs，但 app production path 有
- 問題已縮小到 app 自製 runtime / preprocessing / generation 路徑，而不是資料集或模型版本

### 6. prompt/template 形狀目前沒有證據是主因

已確認：

- 官方 prompt 形式為：
  - `<|begin_of_sentence|>User: <|IMAGE_START|><|IMAGE_PLACEHOLDER|><|IMAGE_END|>...Assistant: `
- 官方 processor 會用 repeated image token 展開 `<|IMAGE_PLACEHOLDER|>`
- app `buildInputIds()` 也是用：
  - BOS
  - `User: `
  - `visionStartTokenId`
  - repeated `visionTokenId`
  - `visionEndTokenId`
  - prompt text
  - `\nAssistant: `

判定：

- 目前沒有證據顯示 prompt 組裝本身就是主因
- 仍需做 input-id / image-token-count parity 才能正式排除

### 7. `verify.py` 路徑的 normalization 與 app 一致，不是新 root cause

比對來源：

- `scripts/convert_model/.venv/lib/python3.14/site-packages/mlx_vlm/models/paddleocr_vl/processing_paddleocr_vl.py`
- app: [MangaTranslatorMLX/PaddleOCREngine.swift](../../../MangaTranslatorMLX/PaddleOCREngine.swift)

結果摘要：

- `mlx_vlm` `ImageProcessor` 預設：
  - `image_mean = [0.5, 0.5, 0.5]`
  - `image_std = [0.5, 0.5, 0.5]`
- app `ImagePreprocessor` 也是：
  - `(px - 0.5) / 0.5`

判定：

- 「app 和 `verify.py` 因為 normalization 不同而落差很大」這個假設不成立
- 先前看到的 OpenAI CLIP mean/std 來自 Hugging Face 原始 `image_processing.py`，不是 `verify.py` 實際使用的 `mlx_vlm` processor

### 8. app 與 `verify.py` 的主要未驗證差異已縮到 vision runtime / decoder

已確認的實作差異：

- `verify.py` / `mlx_vlm`
  - processor 先輸出 patchified `pixel_values`
  - 同時提供 `image_grid_thw`
  - vision model 依 `grid_thw` 做 embedding / projector / rope index
- app
  - 直接把整張 NHWC resize 圖送進自製 `MangaVisionEncoder`
  - 自行計算 patch grid、rope 與 projector merge
  - generation 額外加入 `100272` stop token、`noRepeatNgramSize=3` 與 loop break

判定：

- root cause 目前更集中在自製 Swift runtime
- 接下來的 parity 應優先比較：
  - vision features
  - merged input embeddings
  - first-step logits
  - decoder stop behavior

### 9. `buildInputIds()` 與官方 tokenizer 完全一致

實驗目的：

- 驗證 app 手動組裝的 prompt token ids 是否和官方 tokenizer 產生結果完全一致

方法：

- 用同一份 tokenizer
- 比較官方 chat template 展開後的 `input_ids`
- 比較 app 等價組裝：
  - `100273`
  - `User: `
  - `101305`
  - repeated `100295`
  - `101306`
  - prompt text + `\nAssistant: `

結果摘要：

- `n=1 same True`
- `n=4 same True`
- `n=16 same True`

判定：

- prompt / input id 組裝不是原因

### 10. app 額外 stop token 單獨不是原因

實驗目的：

- 驗證 app 額外 stop token `<|end_of_sentence|>` 是否會單獨造成輸出變空或大面積分岔

方法：

- 同一批 `book1` 114 detector crops
- 官方 `mlx_vlm.generate()` baseline
- baseline + `eos_tokens=['<|end_of_sentence|>']`

結果摘要：

- `diff_count 0 total 114`
- `empty_with_app_stop 0`

判定：

- 額外 stop token 單獨不是主因

### 11. app 的 decoder guard 會改變少量樣本，但不會單獨造成空輸出

實驗目的：

- 驗證 app 的 `100272` stop token + `noRepeatNgramSize=3` 是否足以重現問題

方法：

- 同一批 `book1` 114 detector crops
- 官方 `mlx_vlm.generate()` baseline
- baseline + `<|end_of_sentence|>` + custom no-repeat-3 logits processor

結果摘要：

- `diff_count 7 total 114`
- `empty_app_like 0`
- 受影響樣本主要是：
  - `001#region-006`: `・・・・・・` → `・・・`
  - `010#region-009`: `・・・・・・` → `・・・`
  - `010#region-010`: `・・・・` → `・・・`
  - `004#region-009`: line breaks 被合併
  - `007#region-010`, `009#region-006`: `ふふ` → `ふぷ`

判定：

- decoder guard 是 contributing factor
- 但它不是 empty-output 的主因

### 12. 官方 `verify.py` 在完整 `examples/` 38 頁資料上仍然正常

命令：

```bash
scripts/convert_model/.venv/bin/python scripts/convert_model/verify.py \
  --test-images examples \
  --detector-json-output /private/tmp/paddle-detector-examples.json \
  --report-json /private/tmp/paddle-verify-examples.json
```

結果摘要：

- pages: `38`
- samples: `294`
- `avg_cer=0.0085`
- `fail_count=5`
- `empty_output_count=0`

Artifacts：

- detector JSON: `/private/tmp/paddle-detector-examples.json`
- report JSON: `/private/tmp/paddle-verify-examples.json`

判定：

- 官方 `verify.py` 在 benchmark 同資料集規模上沒有空輸出
- 問題仍在 app path

### 13. benchmark 的空輸出已定位到具體頁面與 region

方法：

- 重跑 `OCRBenchmarkTests/testFullBenchmark`
- 在 app path 記錄空輸出的 page / region bbox / token warning

已捕捉到的案例：

- `examples/book1/001.jpg`
  - detector found `6` regions
  - region 2: bbox `(292.07, 669.73, 22.07, 71.12)` → empty, tokens `[]`
  - region 3: bbox `(963.39, 1138.78, 21.46, 70.95)` → empty, tokens `[]`
  - region 4: bbox `(969.21, 668.66, 23.69, 73.52)` → empty, tokens `[]`
  - region 5: bbox `(275.82, 1141.30, 20.51, 71.04)` → empty, tokens `[]`
- `examples/book1/002.jpg`
  - detector found `12` regions in app benchmark run
  - region 9: bbox `(244.27, 942.52, 72.40, 141.10)` → empty, tokens `[]`
  - region 11: bbox `(126.51, 1080.30, 25.95, 44.41)` → empty, tokens `[]`
- `examples/book1/004.jpg`
  - detector found `14` regions in app benchmark run
  - region 12: bbox `(806.29, 1452.31, 33.96, 98.47)` → empty, tokens `[23]`
  - region 13: bbox `(125.41, 1151.96, 146.31, 375.12)` → empty, tokens `[]`

判定：

- empty outputs 不是抽象現象，已能定位到具體 tiny punctuation regions 與部分較大的 tall regions
- `tokens []` 與 `tokens [23]` 都存在

### 14. `crop expansion` 與 `min_pixels` 單獨不足以重現 `book1/001` 的空輸出

實驗目的：

- 驗證 `book1/001` 的四個 tiny punctuation regions，是否只要套 app crop expansion / app resize 就能在官方 runtime 重現空輸出

方法：

- 用同一份量化模型
- 針對 `book1/001#region-003` 到 `#region-006`
- 比較：
  - exact detector crop
  - app-expanded crop
  - app-expanded crop + app-size resize

結果摘要：

- exact crop：`'………'`
- expanded crop：`'……'`
- expanded crop + app-size resize：仍為 `'……'`
- 沒有任何一個 case 變成 empty

代表樣本：

- `book1/001#region-003`
  - exact box `(292, 670, 22, 71)` → `'………'`
  - expanded box `(282, 651, 43, 109)` → `'……'`
  - official size `(224, 532)` / app size `(56, 112)` → 都是 `'……'`

判定：

- `crop expansion` 會改變標點輸出長度
- 缺少 `min_pixels` 也會縮小圖像
- 但這兩者單獨或合併，仍無法在官方 runtime 重現 app benchmark 的 empty outputs
- 因此 tiny-region empty output 的核心原因仍在 Swift runtime

### 15. app post-processing 會單獨造成額外文字差異

相關實作：

- [MangaTranslatorMLX/PaddleOCRVLRecognizer.swift](../../../MangaTranslatorMLX/PaddleOCRVLRecognizer.swift)
- function: `cleanRecognizedText(_:)`

實驗目的：

- 量化 app recognizer 的文字清洗，單獨會把多少 `verify.py` raw decode 結果改掉

方法：

- 讀取 `/private/tmp/paddle-verify-examples.json` 的 `quantized_text`
- 套用與 app 完全相同的：
  - repeated punctuation collapse
  - phrase-loop cleanup
- 比較清洗前後是否不同

結果摘要：

- `changed_count 18 total 294`

代表樣本：

- `book1/001#region-003`
  - before: `……`
  - after: `…`
- `book2/001#region-011`
  - before: `◆別れの時は、すぐそこまで……。`
  - after: `◆別れの時は、すぐそこまで…。`
- `book1/012#region-007`
  - before: `えっと...\n......`
  - after: `えっと.\n.`

判定：

- `cleanRecognizedText()` 是 confirmed contributing factor
- 它會直接改變 app 最終對外結果，即使 raw engine decode 原本非空
- 這能解釋一部分標點長度與省略號表現不一致，但不能解釋 raw empty outputs

### 16. interpolation 會改變 tiny punctuation 輸出，但 `bicubic` / `bilinear` 不會單獨產生 empty

實驗目的：

- 驗證縮放插值方式是否可能把 `book1/001` 的 tiny punctuation regions 單獨推成空輸出

方法：

- 針對 benchmark 已定位的 `book1/001` 四個 tiny punctuation boxes
- 套 app crop expansion
- 用官方 `min_pixels` smart resize 放大後，比較不同 interpolation：
  - `bicubic`
  - `bilinear`
  - `nearest`
- 其餘維持同一份量化模型與同一個 prompt

結果摘要：

- region 1 to 4:
  - `bicubic` → `……`
  - `bilinear` → `……`
  - `nearest` → `・・・・・・` / `………`
- 沒有任何一個 case 在 `bicubic` 或 `bilinear` 下變成 empty

判定：

- interpolation 是 confirmed contributing factor
- 但它不是 tiny-region empty-output 的單獨原因
- `CIContext.render()` / Core Image 縮放細節仍值得後續做 tensor parity，但目前不能把 empty 直接歸因於 interpolation

### 17. 官方 `mlx_vlm` vision path 與 app 自製 Swift runtime 在介面上確實不同

比對來源：

- `scripts/convert_model/.venv/lib/python3.14/site-packages/mlx_vlm/models/paddleocr_vl/vision.py`
- `scripts/convert_model/.venv/lib/python3.14/site-packages/mlx_vlm/models/paddleocr_vl/paddleocr_vl.py`
- [MangaTranslatorMLX/PaddleOCREngine.swift](../../../MangaTranslatorMLX/PaddleOCREngine.swift)

已確認差異：

- 官方 `mlx_vlm` 先產生 patchified `pixel_values`，再配合 `image_grid_thw` 進 vision path
- app 直接把整張 NHWC 圖送進自製 `MangaVisionEncoder`
- 官方 `PaddleOCRProjector.pre_norm` 的 `eps` 是 `1e-6`
- app `MangaMultiModalProjector.preNorm` 的 `eps` 是 `1e-5`
- 官方 vision MLP 使用 `GELU(approx=\"precise\")`
- app vision MLP 使用 `geluApproximate(...)`

判定：

- 這些是 direct source-level implementation mismatches，不是推測
- 是否足以單獨造成 empty outputs，還需要中間值 parity 才能確認
- 目前最可疑的責任範圍仍是 app 自製 Swift vision / projector / generator 路徑

### 18. benchmark 已定位的 8 個 empty cases，全部都能在官方 runtime 產生非空輸出

實驗目的：

- 驗證 benchmark 真正失敗的 empty cases，是否只要把同一個 bbox 丟回官方 runtime，就仍然能得到正常文字

方法：

- 使用 benchmark 已定位的 8 個 empty bboxes：
  - `book1/001` 4 個 tiny punctuation regions
  - `book1/002` 2 個 regions
  - `book1/004` 2 個 regions
- 逐一比較：
  - exact crop
  - app crop expansion + official-size resize
  - app crop expansion + app-size resize
- 其餘維持同一份量化模型與同一個 prompt

結果摘要：

- 8/8 cases 在官方 runtime 都是非空
- `book1/001` 的 4 個 tiny punctuation regions：
  - exact: `………`
  - expanded official/app-size: `……`
- `book1/002#region-009`：
  - exact / expanded official / expanded app-size: 都是 `そうと決まれば！`
- `book1/002#region-011`：
  - exact / expanded official / expanded app-size: 都是 `？`
- `book1/004#region-012`：
  - exact / expanded official / expanded app-size: 都是 `はい!`
- `book1/004#region-013`：
  - exact / expanded official / expanded app-size: 都是非空長句，只是 line break 位置不同

判定：

- benchmark 的已知 empty cases 不是「bbox 本身太難」或「官方 runtime 也會空」
- empty outputs 已進一步鎖定為 Swift runtime 特有問題
- crop expansion、resize、插值都會影響文字內容，但仍不足以把這 8 個具體案例推成 empty

### 19. Python `mlx_vlm` 的 text decoder 使用三軸 multimodal RoPE，Swift runtime 不是同一條路徑

比對來源：

- `scripts/convert_model/.venv/lib/python3.14/site-packages/mlx_vlm/models/paddleocr_vl/language.py`
- `.xcodebuild-env/SourcePackages/checkouts/paddleocr-vl.swift/Sources/PaddleOCRVL/LanguageModel.swift`
- [MangaTranslatorMLX/PaddleOCREngine.swift](../../../MangaTranslatorMLX/PaddleOCREngine.swift)

已確認差異：

- Python `mlx_vlm`：
  - `rope_theta = 500000`
  - `mrope_section = [16, 24, 24]`
  - 會依 `image_grid_thw` 計算三軸 `position_ids`
  - `LanguageModel.__call__()` 會維護 `_position_ids` / `_rope_deltas`
  - attention 端使用 `apply_multimodal_rotary_pos_emb(...)`
- Swift package / app 路徑：
  - `LanguageModel.swift` 只有普通 1D `RoPE(offset:)`
  - 沒有 `image_grid_thw`
  - 沒有 `_position_ids` / `_rope_deltas`
  - app `GeneratorRuntime` 直接：
    - `mergeInputIdsWithImageFeatures(...)`
    - `languageModel.forward(mergedEmbeds, cache: cache)`
    - `lmHead(...)`

判定：

- 這是 confirmed implementation mismatch
- app / Swift runtime 並沒有走 `verify.py` 那條 multimodal position path

### 20. 移除 Python `mlx_vlm` 的 multimodal position path 後，首步 logits 會明顯改變，但不是每個 sample 都立即翻 top-1

實驗目的：

- 驗證 `image_grid_thw + multimodal RoPE` 對第一步 decoder logits 的實際影響

方法：

- 用同一份 Python 模型與同一份 merged image/text embeddings
- 比較：
  - official：`model(..., pixel_values=..., image_grid_thw=...)`
  - naive 1D：先手動 merge image features，再直接呼叫 `model.language_model(...)`，不提供 `image_grid_thw / position_ids`
- 先針對代表樣本，再抽樣 `book1` 的 20 個 detector crops

代表樣本結果：

- `tiny-punct`
  - `max_diff 1.125`
  - `mean_diff 0.1529`
- `tall-empty`
  - `max_diff 1.9375`
  - `mean_diff 0.3163`
- `normal`
  - `max_diff 2.7422`
  - `mean_diff 0.3896`

20 個 `book1` samples 抽樣結果：

- `first_token_top1_diff_count 1 / 20`
- 其餘多數 sample 雖然 top-1 沒翻，但 `max_abs_diff` 普遍仍在 `0.84` 到 `2.98` 之間
- 已觀察到至少一個 sample 首 token 直接翻轉：
  - `001#region-006`
  - official top-1: `96377`
  - naive 1D top-1: `2703`

判定：

- 缺少 multimodal position path 會實際改變 decoder logits，不是理論差異
- 但從目前抽樣看，它不像是「所有 sample 第一 token 都立刻壞掉」
- 目前較合理的分類是 confirmed contributing factor；是否為 empty-output 的直接主因，仍需做多步 token parity

### 21. 官方 `stream_generate()` 在已知 empty cases 上，不會自然以 newline token `23` 起手

實驗目的：

- 驗證 benchmark 已定位的 empty cases，在官方 `mlx_vlm.generate()` 路徑上，前幾步 token 是否本來就很快走向 `[23]` 或空序列

方法：

- 使用 `mlx_vlm.stream_generate()`，直接記錄每一步 token id
- 觀察：
  - first token
  - newline token `23` 出現位置
  - EOS token `2` 出現位置
  - 最終 `generate()` text

結果摘要：

- tiny punctuation cases（`book1/001` 那 4 個空框）：
  - tokens: `[2703, 2]`
  - first token = `2703`（`……`）
  - 第 2 步就 EOS
  - 不會先吐 `23`
- `？` case（`book1/002` 的小框）：
  - tokens: `[94105, 2]`
  - first token = `94105`（`？`）
  - 第 2 步就 EOS
  - 不會先吐 `23`
- tall non-empty case：
  - 前 12 token 內會出現 `23`，但位置在第 5 步之後
  - 最終仍是正常多行文字，不是 empty

判定：

- 官方路徑在這些已知 empty cases 上，不是「先產生 newline 然後被 trim 掉」
- app log 裡的 `[]` / `[23]` 現象，仍屬 Swift runtime 特有異常

### 22. app engine 已直接驗證：known failing crops 在 Swift runtime 內部就是 `[]` / `[23]`

測試入口：

- `OCRBenchmarkTests/OCRBenchmarkTests.swift`
- `testCaptureDebugTokenTracesForBenchmarkEmptyRegions()`

方法：

- 對 benchmark 已定位的 failing detector boxes
- 套用和 app 一樣的 crop expansion
- 直接呼叫 `DefaultPaddleOCREngine.inferDebug(image:)`
- 記錄：
  - `rawText`
  - `trimmedText`
  - `generatedTokens`

結果摘要：

- `book1/001#r2`
  - `rawText=""`
  - `trimmedText=""`
  - `tokens=[]`
- `book1/001#r3`
  - `rawText=""`
  - `trimmedText=""`
  - `tokens=[]`
- `book1/002#r9`
  - `rawText=""`
  - `trimmedText=""`
  - `tokens=[]`
- `book1/004#r12`
  - `rawText=""`
  - `trimmedText=""`
  - `tokens=[23]`
- `book1/004#r13`
  - `rawText=""`
  - `trimmedText=""`
  - `tokens=[]`

對照官方路徑：

- 同一批 expanded crops 在 `mlx_vlm.generate()` 下是非空
- tiny punctuation / `？` 類 case 甚至是：
  - content token
  - 然後立刻 EOS

判定：

- 這不是後處理或 benchmark 配對問題
- app engine 內部的 autoregressive decode 在這些 case 上第一步就已經走偏：
  - `[]` 代表 first-step argmax 直接是 stop token
  - `[23]` 代表 first-step argmax 直接是 newline token
- root cause 已進一步縮到 Swift runtime 的 prefill / first-step decode 行為

## Confirmed Causes

### Missing `min_pixels` in app smart resize

證據：

- 114 個 crops 中有 110 個 target dimensions 與官方不同
- 平均像素量差約 `9.05x`
- 同模型同 crop 實驗下，確實造成 10 個樣本輸出差異

判定：

- confirmed contributing factor

### App runtime emits empty or newline-only generations

證據：

- `OCRBenchmarkTests` production path 出現大量空輸出警告
- token `23` 已驗證為 newline
- `verify.py` 在同批 detector crops 上 `empty_output_count=0`

判定：

- confirmed root-cause area
- 但尚未定位是在 preprocess、vision path、merge 還是 generator 開始分岔

### Missing multimodal position handling in Swift runtime

證據：

- Python `mlx_vlm` 明確依 `image_grid_thw` 建立三軸 `position_ids`
- Swift runtime / Swift package 沒有對應的 multimodal RoPE state
- 在同一份 Python merged embeddings 上，拿掉這條 position path 會造成首步 logits 實際改變

判定：

- confirmed contributing factor
- 目前還不能單獨證明它就是 empty-output 的唯一主因

### App post-processing mutates final OCR strings

證據：

- `cleanRecognizedText()` 在 `294` 個 `verify.py` 輸出上，單獨改掉 `18` 個結果
- 變動不只純標點，也包含正文中的省略號與多行標點

判定：

- confirmed contributing factor
- 這是 final-output mismatch 的一部分來源

## Rejected Hypotheses

- 模型版本不一致
- `max_pixels=1003520` 單獨造成 major regression
- `max_tokens=300` 單獨造成 major regression
- 量化模型本身已壞掉
- `verify.py` 與 app 的 normalization 不同
- prompt / input id 組裝不同
- 額外 stop token `100272` 單獨造成空輸出
- `bicubic` / `bilinear` interpolation 單獨造成 tiny-region empty output
- benchmark 已定位 empty bboxes 在官方 runtime 也會自然產生空輸出

## Open Questions

- `ImagePreprocessor` 產出的 pixel tensor 是否與官方 processor 完全一致
- `buildInputIds()` 產出的 image token count 是否與官方一致
- `mergeInputIdsWithImageFeatures` 前後的 token 對位是否正確
- Swift `GeneratorRuntime` 的首 token logits 是否已經和 `mlx_vlm.generate()` 分岔
- 額外 stop token `100272` 與 `noRepeatNgramSize=3` 是否會放大空輸出比例
- `cleanRecognizedText()` 是否應該在 app path 停用、弱化，或至少不要壓縮日文省略號
- app benchmark run 中 detector region counts 與 `DetectorExportCLI` 匯出的 page summaries 是否完全一致
- 分岔點是在：
  - preprocess
  - vision encoder / projector
  - multimodal merge
  - decoder generation
- tiled path 是否也有獨立問題，或主要問題集中在 `smart_resize path`

## Additional Findings

### 23. app engine 已直接證明：known empty cases 的 stop token 就是 `EOS=2`

目的：

- 釐清 `Tokens: []` 是 stop token 立刻命中，還是 app 內部有其他隱藏後處理

測試入口：

- `OCRBenchmarkTests/testCaptureDebugTokenTracesForBenchmarkEmptyRegions`

命令：

```bash
xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark -destination 'platform=macOS' -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testCaptureDebugTokenTracesForBenchmarkEmptyRegions
```

樣本：

- `book1/001#r2`
- `book1/001#r3`
- `book1/002#r9`
- `book1/004#r12`
- `book1/004#r13`

結果摘要：

- `book1/001#r2`：`tokens=[]`、`terminationToken=2`
- `book1/001#r3`：`tokens=[]`、`terminationToken=2`
- `book1/002#r9`：`tokens=[]`、`terminationToken=2`
- `book1/004#r12`：`tokens=[23]`、`terminationToken=2`
- `book1/004#r13`：`tokens=[]`、`terminationToken=2`

判定：

- app empty output 不是 benchmark 配對問題，也不是 `trim()` 才變空
- 對 `[]` 這類 case，Swift runtime 在 first-step 就直接選到 `EOS=2`
- 對 `[23]` 這類 case，Swift runtime first-step 先選到 newline，第二步再選 `EOS=2`

### 24. Python official 與 Python naive-position 對這 5 個 empty cases 都不會 first-step 選 `EOS`

目的：

- 驗證缺少 multimodal position handling 是否足以直接造成這批 empty outputs

命令：

```bash
scripts/convert_model/.venv/bin/python /private/tmp/compare_paddle_positions.py
```

樣本：

- 同上面 5 個 benchmark empty cases，使用 app benchmark 相同的 expanded crops

結果摘要：

- `book1/001#r2`
  - official top-1: `2703` (`……`)
  - naive-position top-1: `2703` (`……`)
- `book1/001#r3`
  - official top-1: `2703` (`……`)
  - naive-position top-1: `2703` (`……`)
- `book1/002#r9`
  - official top-1: `86192` (`そう`)
  - naive-position top-1: `86192` (`そう`)
- `book1/004#r12`
  - official top-1: `95413` (`は`)
  - naive-position top-1: `95413` (`は`)
- `book1/004#r13`
  - official top-1: `34012` (`では`)
  - naive-position top-1: `34012` (`では`)

補充：

- 這些 case 的 `max_abs_diff` 約在 `1.125` 到 `2.3125`
- 代表缺 multimodal positions 仍然會改變 logits，但在這 5 個 empty cases 上，不會把 first-step 直接翻成 `EOS`

判定：

- `multimodal position handling mismatch` 仍是 confirmed contributing factor
- 但它不是這批 benchmark empty outputs 的直接主因

### 25. Swift runtime 的 first-step logits 已和 Python 路徑明顯分岔

目的：

- 驗證 empty output 是否已經在 Swift prefill / first-step decode 就發生

測試入口：

- `OCRBenchmarkTests/testCaptureDebugTokenTracesForBenchmarkEmptyRegions`

結果摘要：

- `book1/001#r2`
  - Swift top-1: `2`
  - Swift top-2: `2703`
- `book1/001#r3`
  - Swift top-1: `2`
  - Swift top-2: `2703`
- `book1/002#r9`
  - Swift top-1: `2`
  - Swift top-2: `23`
  - Swift top-5 才看到 `86192`
- `book1/004#r12`
  - Swift top-1: `23`
  - Swift top-2: `2`
  - Swift top-3: `95413`
- `book1/004#r13`
  - Swift top-1: `2`
  - Swift top-2: `23`

對照：

- Python official / naive-position 在同樣 5 個 case 上都不是 `2` 或 `23` top-1

判定：

- empty output 的直接來源已鎖到 Swift 自製 runtime 的 prefill / first-step logits
- 問題已不在 stop/trim/post-processing 階段
- 問題也不只是 decoder position handling；更可能在：
  - `ImagePreprocessor`
  - `MangaVisionEncoder`
  - `MangaMultiModalProjector`
  - `mergeInputIdsWithImageFeatures`

### 26. Swift projected image features 與官方 app-size visual features 已做逐值比對，差異很小

目的：

- 驗證 empty-output 問題是否其實還卡在 `ImagePreprocessor / MangaVisionEncoder / MangaMultiModalProjector`

測試入口：

- `OCRBenchmarkTests/testCapturePrefillFeatureSummariesForBenchmarkEmptyRegions`
- `OCRBenchmarkTests/testExportSwiftProjectedFeaturesForBenchmarkEmptyRegions`

命令：

```bash
xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark -destination 'platform=macOS' -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testCapturePrefillFeatureSummariesForBenchmarkEmptyRegions

xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark -destination 'platform=macOS' -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testExportSwiftProjectedFeaturesForBenchmarkEmptyRegions

scripts/convert_model/.venv/bin/python /private/tmp/compare_swift_python_projected_features.py
```

Artifacts：

- Swift projected features：
  - `/Users/chunweiliu/Library/Containers/com.chunweiliu.MangaTranslator/Data/tmp/paddle-swift-projected-features.json`

樣本：

- 同樣 5 個 benchmark empty cases
- Python 端使用 app benchmark 相同 expanded crops，並固定到 app target size / app placeholder count

結果摘要：

- `book1/001#r2`
  - `max_abs_diff=0.6387`
  - `mean_abs_diff=0.0848`
  - `rmse=0.1131`
  - `cosine=0.9947`
- `book1/001#r3`
  - `max_abs_diff=0.7007`
  - `mean_abs_diff=0.0808`
  - `rmse=0.1092`
  - `cosine=0.9958`
- `book1/002#r9`
  - `max_abs_diff=1.2813`
  - `mean_abs_diff=0.0692`
  - `rmse=0.1040`
  - `cosine=0.9962`
- `book1/004#r12`
  - `max_abs_diff=0.6953`
  - `mean_abs_diff=0.0613`
  - `rmse=0.0891`
  - `cosine=0.9971`
- `book1/004#r13`
  - `max_abs_diff=2.8516`
  - `mean_abs_diff=0.1016`
  - `rmse=0.1745`
  - `cosine=0.9865`

判定：

- Swift `ImagePreprocessor + MangaVisionEncoder + MangaMultiModalProjector` 的最終 projected image features 已非常接近官方 app-size visual features
- 這組證據足以把主要懷疑從 vision/projector 移開
- empty-output 主責任已更集中到 text-side runtime

### 27. 即使把官方路徑限制到 app target size / app placeholder count，first-step 仍然不是 `EOS` / newline

目的：

- 驗證 empty outputs 是否只是因為 app target size 太小，導致模型自然在 first-step 就停掉

命令：

```bash
scripts/convert_model/.venv/bin/python /private/tmp/compare_official_on_app_size.py
```

結果摘要：

- `book1/001#r2`
  - app target: `56x112`
  - `image_grid_thw=[[1, 8, 4]]`
  - top tokens: `33460('…………')`, `2703('……')`, `73875('……………………')`
- `book1/001#r3`
  - app target: `56x112`
  - top tokens: `33460('…………')`, `2703('……')`, `73875('……………………')`
- `book1/002#r9`
  - app target: `112x224`
  - top tokens: `86192('そう')`, `97151('そ')`, `47277('それ')`
- `book1/004#r12`
  - app target: `56x140`
  - top tokens: `95413('は')`, `25667('ない')`, `99647('ほ')`
- `book1/004#r13`
  - app target: `196x560`
  - top tokens: `34012('では')`, `95393('で')`, `22000('です')`

判定：

- 把 `min_pixels` 影響拿掉後，官方路徑仍不會在這些 case 上 first-step 選 `EOS=2` 或 `newline=23`
- 所以 empty outputs 不是「app target size 太小就會自然停掉」

### 28. Python surrogate 的 `merged embeddings -> text model` 仍無法重現 `EOS` / newline

目的：

- 驗證問題是否只是「把 image features merge 完後直接送 text model」這件事本身

命令：

```bash
scripts/convert_model/.venv/bin/python /private/tmp/compare_python_fullpath_vs_embeddirect.py
```

方法：

- 使用官方 app-size image features
- 對照：
  - full multimodal path
  - `merged_embeds -> language_model.model(... position_ids=1D tiled ...) -> lm_head`

結果摘要：

- `book1/001#r2`
  - full path: `33460('…………') / 2703('……')`
  - embed-direct: `2703('……') / 33460('…………')`
- `book1/002#r9`
  - full path: `86192('そう')`
  - embed-direct: `86192('そう')`
- `book1/004#r13`
  - full path: `34012('では')`
  - embed-direct: `34012('では')`
- 5 個 case 全部都沒有翻成 `EOS=2` 或 `newline=23`

判定：

- 單靠「merged embeddings 直送 text model」或「Python surrogate 的 1D-tiled positions」仍不足以重現 Swift 的 empty behavior
- 因此目前最合理的剩餘 root-cause area 是：
  - Swift package `LanguageModel.swift` 的 text-side implementation mismatch
  - 或 Swift custom prefill 對 package text model 的呼叫方式與 Python 真實路徑仍有未覆蓋差異

### 29. 目前 root-cause 收斂狀態

已確認並保留為 contributing factors：

- `min_pixels` 缺失
- decoder guard / no-repeat
- post-processing (`cleanRecognizedText()`)
- interpolation 對 tiny punctuation 的敏感性
- 缺 multimodal position handling

目前最核心、且尚未完全展開的 root-cause area：

- Swift text-side runtime
  - `LanguageModel.swift`
  - `GeneratorRuntime.generateTrace(...)`
  - 更精確地說，是 `LanguageModel.swift` 的 first-step forward path

現階段可以負責任地說：

- vision/projector 已不是主要嫌疑
- empty outputs 的直接來源在 Swift first-step logits
- merge 也已不是主要嫌疑
- 而 first-step logits 的主要剩餘分岔點，已集中到 Swift text model / prefill path

### 30. Swift merged embeddings 已直接導出，且和 Python merged embeddings 幾乎一致

目的：

- 驗證 `mergeInputIdsWithImageFeatures(...)` 是否其實才是 first-step 分岔主因

測試入口：

- `OCRBenchmarkTests/testExportSwiftMergedEmbeddingsAndFirstStepLogitsForBenchmarkEmptyRegions`

命令：

```bash
xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark -destination 'platform=macOS' -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testExportSwiftMergedEmbeddingsAndFirstStepLogitsForBenchmarkEmptyRegions

scripts/convert_model/.venv/bin/python /private/tmp/compare_swift_merge_and_logits.py
```

Artifacts：

- Swift merged embeddings + first-step logits：
  - `/Users/chunweiliu/Library/Containers/com.chunweiliu.MangaTranslator/Data/tmp/paddle-swift-merged-embeddings-and-logits.json`

結果摘要：

- merged embeddings diff
  - `book1/001#r2`
    - `max_abs=0.638672`
    - `mean_abs=0.019958`
    - `rmse=0.054868`
    - `cosine=0.994717`
  - `book1/001#r3`
    - `max_abs=0.700684`
    - `mean_abs=0.019021`
    - `rmse=0.052968`
    - `cosine=0.995814`
  - `book1/002#r9`
    - `max_abs=1.281250`
    - `mean_abs=0.038198`
    - `rmse=0.077274`
    - `cosine=0.996224`
  - `book1/004#r12`
    - `max_abs=0.695312`
    - `mean_abs=0.017026`
    - `rmse=0.046976`
    - `cosine=0.997083`
  - `book1/004#r13`
    - `max_abs=2.851562`
    - `mean_abs=0.085694`
    - `rmse=0.160256`
    - `cosine=0.986519`

- 同一份 Swift merged embeddings 丟回 Python text model（1D-tiled positions surrogate）後，top-1 仍然不是 `EOS=2` 或 `newline=23`
  - `book1/001#r2`
    - Python on Swift merged: `2703('……')`
    - Swift logits top-1: `2`
  - `book1/002#r9`
    - Python on Swift merged: `86192('そう')`
    - Swift logits top-1: `2`
  - `book1/004#r12`
    - Python on Swift merged: `95413('は')`
    - Swift logits top-1: `23`
  - `book1/004#r13`
    - Python on Swift merged: `34012('では')`
    - Swift logits top-1: `2`

- Python `py_merge_1d` vs `py(swift_merge)_1d` 的 logits 彼此很接近
  - `book1/001#r2`
    - `max_abs=1.687364`
    - `cosine=0.984738`
  - `book1/001#r3`
    - `max_abs=0.911167`
    - `cosine=0.992489`
  - `book1/002#r9`
    - `max_abs=0.759706`
    - `cosine=0.998871`
  - `book1/004#r12`
    - `max_abs=0.795223`
    - `cosine=0.999308`
  - `book1/004#r13`
    - `max_abs=1.058974`
    - `cosine=0.996670`

判定：

- `mergeInputIdsWithImageFeatures(...)` 不是 benchmark empty outputs 的主責任
- 即使直接使用 Swift 匯出的 merged embeddings，Python text model 仍然產生正常 first-step token
- root cause 已進一步縮到 Swift text model forward 本體，而不只是 merge 結果

### 31. 把 Python 端 rotary 改成 Swift 式 standard RoPE，仍然無法重現 `EOS` / newline

目的：

- 驗證剩下的差異是否只要用「Swift 那種 standard 1D RoPE」就能重現 empty behavior

命令：

```bash
scripts/convert_model/.venv/bin/python /private/tmp/compare_standard_rope_on_swift_merge.py
```

方法：

- 在 Python `mlx_vlm` 內 monkeypatch `apply_multimodal_rotary_pos_emb`
- 改成 Swift 類似的 standard RoPE 行為：
  - 不做 `mrope_section` split
  - 直接用單一 1D cos/sin 套滿整個 head dimension
- 對照同樣 5 個 empty cases 的 Swift merged embeddings

結果摘要：

- `book1/001#r2`
  - Python standard-RoPE on Swift merged top-1: `2703('……')`
  - Swift logits top-1: `2`
- `book1/002#r9`
  - Python standard-RoPE on Swift merged top-1: `86192('そう')`
  - Swift logits top-1: `2`
- `book1/004#r12`
  - Python standard-RoPE on Swift merged top-1: `95413('は')`
  - Swift logits top-1: `23`
- `book1/004#r13`
  - Python standard-RoPE on Swift merged top-1: `34012('では')`
  - Swift logits top-1: `2`

判定：

- 缺 `mrope_section` / 使用 standard RoPE 仍然是 confirmed contributing factor
- 但它仍不足以單獨重現 Swift 的 `EOS/newline` first-step 行為
- 所以剩下真正的主責任仍在 Swift text model forward implementation mismatch

### 32. `prefill with cache objects` 不是原因，Python 帶空 cache 的 first-step logits 完全相同

目的：

- 排除 Swift prefill 走 `cache = model.newCache()` 這件事本身是否會改變 first-step 結果

命令：

```bash
scripts/convert_model/.venv/bin/python /private/tmp/check_prefill_cache_effect.py
```

樣本：

- `book1/002#r9`

結果摘要：

- no-cache top-5：
  - `86192('そう')`
  - `97151('そ')`
  - `47277('それ')`
  - `97692('ど')`
  - `96447('う')`
- empty-cache-object prefill top-5：
  - 完全相同
- `max_abs_diff = 0.0`

判定：

- Swift prefill 在 first-step 傳入空 cache objects 不是 empty-output 主因

### 33. 把 Python attention 改成 Swift 同款 `matmul + softmax + matmul`，仍然無法重現 `EOS` / newline

目的：

- 驗證剩餘差異是否其實卡在 Swift `ERNIEAttention` 的手刻 attention forward

命令：

```bash
scripts/convert_model/.venv/bin/python /private/tmp/compare_manual_attention_on_swift_merge.py
```

方法：

- 使用 Swift 匯出的 merged embeddings
- Python 端 monkeypatch：
  - `apply_multimodal_rotary_pos_emb` → standard RoPE
  - `scaled_dot_product_attention` → Swift 同型的 `scores = qk^T * scale; softmax; weights @ v`
- 同時測：
  - bf16 softmax
  - float32 softmax 再 cast 回原 dtype

結果摘要：

- `book1/001#r2`
  - manual attention top-1: `2703('……')`
  - Swift logits top-1: `2`
- `book1/002#r9`
  - manual attention top-1: `86192('そう')`
  - Swift logits top-1: `2`
- `book1/004#r12`
  - manual attention top-1: `95413('は')`
  - Swift logits top-1: `23`
- `book1/004#r13`
  - manual attention top-1: `34012('では')`
  - Swift logits top-1: `2`
- `manual_bf16` 與 `manual_f32` top-k 實際上一致

判定：

- 單靠 attention kernel 形式差異，仍不足以重現 Swift empty behavior
- 也就是說，問題不只是「Swift 沒用 fast SDPA」

### 34. layer-by-layer hidden state parity：分岔從 layer 0 的小誤差開始，隨深度持續放大

目的：

- 確認 Swift text model 與 Python surrogate 的差異是某一層突然爆掉，還是從前層就開始累積

測試方式：

- Swift 端從 package checkout 加入 `forwardDebug(...)`
- 導出每層最後一個 token 的 hidden state
- Python 端用同一份 Swift merged embeddings、同一組 standard RoPE，逐層對比

命令：

```bash
xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark -destination 'platform=macOS' -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testExportSwiftMergedEmbeddingsAndFirstStepLogitsForBenchmarkEmptyRegions

scripts/convert_model/.venv/bin/python /private/tmp/compare_layer_hidden_states.py
```

結果摘要：

- `book1/001#r2`
  - layer 0: `mean_abs=0.009494`, `cosine=0.996369`
  - layer 1: `mean_abs=0.021309`, `cosine=0.972099`
  - layer 2: `mean_abs=0.041569`, `cosine=0.925573`
  - layer 9: `mean_abs=0.271586`, `cosine=0.695788`
  - layer 17: `mean_abs=0.782025`, `cosine=0.787198`
- `book1/002#r9`
  - layer 0: `mean_abs=0.009556`, `cosine=0.995797`
  - layer 1: `mean_abs=0.023099`, `cosine=0.968598`
  - layer 2: `mean_abs=0.045255`, `cosine=0.920862`
  - layer 9: `mean_abs=0.279719`, `cosine=0.665515`
  - layer 17: `mean_abs=0.994067`, `cosine=0.753144`
- `book1/004#r13`
  - layer 0: `mean_abs=0.009528`, `cosine=0.996681`
  - layer 1: `mean_abs=0.022779`, `cosine=0.967567`
  - layer 2: `mean_abs=0.044732`, `cosine=0.914414`
  - layer 9: `mean_abs=0.298231`, `cosine=0.638117`
  - layer 17: `mean_abs=0.917164`, `cosine=0.601511`

判定：

- 分岔不是到中後段才突然爆掉
- 從第一層開始就有小但穩定的數值偏差
- 這些偏差會沿層數累積，最後把 first-step logits 推翻成 `EOS/newline`
- 目前最準確的 root-cause 描述是：
  - Swift `LanguageModel.swift` 整體 forward path 存在持續性的 implementation / numeric mismatch
  - 而不是單一的 merge、cache、RoPE、或 attention-kernel 差異

### 35. 已鎖定第一個真正的主 root cause：Swift `MLXFast.RoPE` 路徑產生錯誤的 q/k rotary 結果

目的：

- 把 `LanguageModel.swift` 的 layer-0 偏差再切到更小，確認問題是出在 linear projections、RoPE、attention weights、還是 MLP

測試方式：

- Swift 端額外導出 first-layer attention internals：
  - raw q / k / v last token
  - rotary 後 q / k / v last token
  - attention weights last row
- Python 端對同一份 Swift merged embeddings，重建 layer-0 attention 流程後逐項比對

命令：

```bash
xcodebuild test -project MangaTranslator.xcodeproj -scheme OCRBenchmark -destination 'platform=macOS' -only-testing:OCRBenchmarkTests/OCRBenchmarkTests/testExportSwiftMergedEmbeddingsAndFirstStepLogitsForBenchmarkEmptyRegions

scripts/convert_model/.venv/bin/python /private/tmp/compare_first_layer_attention_internals.py
scripts/convert_model/.venv/bin/python /private/tmp/compare_first_layer_components.py
```

樣本：

- `book1/002#r9`

結果摘要：

- raw projections 在 RoPE 前其實很接近
  - `rawQueriesLastToken`
    - `max_abs=0.187889`
    - `mean_abs=0.013114`
    - `rmse=0.018897`
  - `rawKeysLastToken`
    - `max_abs=0.105089`
    - `mean_abs=0.016894`
    - `rmse=0.024959`
  - `rawValuesLastToken`
    - `max_abs=0.010648`
    - `mean_abs=0.000663`
    - `rmse=0.001098`

- 但一旦經過 Swift 的 RoPE 後，q/k 差異立刻暴增
  - `queriesLastToken`
    - `max_abs=6.380364`
    - `mean_abs=0.452640`
    - `rmse=0.911581`
  - `keysLastToken`
    - `max_abs=9.021080`
    - `mean_abs=0.668476`
    - `rmse=1.389368`
  - `valuesLastToken`
    - 仍維持很接近
    - `max_abs=0.010648`
    - `mean_abs=0.000663`
    - `rmse=0.001098`

- 後續 attention / residual / hidden state 偏差，都是從這個 q/k RoPE 分岔一路傳下去
  - `attentionOutput`
    - `mean_abs=0.007924`
    - `cosine=0.972950`
  - `layerOutput`
    - `mean_abs=0.009556`
    - `cosine=0.995797`
  - deeper layers 持續放大，最後翻成 `EOS/newline`

判定：

- 這次已經不是「text-side runtime 很可疑」這種大範圍結論
- 第一個真正的主 root cause 已鎖定：
  - Swift `LanguageModel.swift` 內 `ERNIEAttention` 使用的 `MLXFast.RoPE(...)`
  - 與 PaddleOCR-VL 期望的 text-side rotary 行為不一致
- 更精確地說：
  - q/k 在 RoPE 前仍大致對齊
  - q/k 在 RoPE 後立刻大幅分岔
  - 之後的 attention weights、layer outputs、first-step logits 只是連鎖結果

目前最合理的修正方向：

- 不要再用 `MLXFast.RoPE(...)` 直接套在 PaddleOCR-VL text model 上
- 改成對齊 Python `mlx_vlm.models.paddleocr_vl.language.PaddleOCRRotaryEmbedding + apply_multimodal_rotary_pos_emb` 的實作
- 即使先不補回完整 `mrope_section`，也至少要先把 text-side standard rotary 的數值行為做成和 Python 一致，而不是依賴 `MLXFast.RoPE`

## Next Experiments

### 1. Text-side runtime parity

目的：

- 既然 projected image features 與 merged embeddings 都已證明很接近官方，下一步應只集中到 Swift text-side runtime

驗證項：

- `LanguageModel.swift` first-step logits
- `GeneratorRuntime` 的 prefill / decode 呼叫時機
- Swift package text model 與 Python text model 的 attention / rope 行為差異

### 2. First-step text model parity

目的：

- 直接驗證 first-step logits 已在 package text model forward 內部分岔到哪一層

驗證項：

- first-step last hidden state
- layer-by-layer hidden state diff
- attention mask / rope / softmax 數值行為

### 3. First 5 to 10 generated tokens parity

目的：

- 已知一開始就錯，這一步改為確認 non-empty 但錯字樣本的分岔是否同樣來自 first-step

驗證項：

- 每一步生成 token
- stop condition 觸發時機
- newline / eos / pad 的處理方式

### 5. Locate divergence stage

目的：

- 把 root cause 鎖定到單一模組或最小責任範圍

候選模組：

- `mergeInputIdsWithImageFeatures`
- `LanguageModel.swift`
- `GeneratorRuntime`

## Acceptance Criteria

每個結論都必須附帶：

- 實驗目的
- 命令或測試入口
- 使用樣本
- 結果摘要
- 判定

最終調查完成時，所有問題都要落到以下其中一類：

- confirmed root cause
- contributing factor
- ruled out hypothesis

## Working Method

後續每完成一組實驗，就在這份筆記新增一筆：

- 日期時間
- 實驗目的
- 命令
- 樣本
- 結果
- 判定
- 下一步

若後續產生需要重複使用的中間檔，應在此 change 目錄下新增 `artifacts/`，並在本文記錄相對路徑，避免只依賴 `/private/tmp`。
