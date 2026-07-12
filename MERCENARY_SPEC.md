# 自製佣兵 NPC — KOD Mod 規格

新增佣兵 class `Mercenary`：綁定主人（poMaster）的不死女性 NPC，
會跟隨、補血、自動打怪、定身控場。

## 非目標（第一版不做）
雇用/薪資機制（admin 直接生成）、裝備系統、多佣兵編隊、升級成長。

## 實作原則
- 先調查後實作：Phase 0 調查回報並經確認後，才開始寫 code
- 繼承重用既有 class，不複製貼上
- 數值一律做成 properties 方便調整
- 分階段實作（跟隨 → 補血 → 打怪），每階段測試通過才進下一階段

## Phase 0：原始碼調查（唯讀，逐項回報）

從 kod/ 查出：

1. 佣兵基底：monster 繼承結構中最適合的 class（會戰鬥的 guard 類？會跟隨的 animate/pet 類？）
2. 跟隨機制：既有 NPC 跟隨玩家的實作；跨房間跟隨監聽什麼訊息；主人死亡重生是否觸發同一訊息
3. AI 迴圈：monster 移動/AI 的驅動方式與 tick 間隔
4. 戰鬥目標：怪物選定攻擊目標的機制；佣兵如何得知「主人被攻擊」
5. 治療：對玩家加 HP 的正確 message；加值是否自動 clamp 到上限
6. 傷害類型與法術：物理/魔法傷害如何區分；抗性怎麼判定；
   Hold 類定身法術的效果 message 與持續機制；NPC 能否對怪施放
7. 經驗歸屬:怪物死亡時經驗如何分配；把佣兵的 credit 轉給主人的做法
8. 生成：admin console 生成怪物並綁定主人的指令；女性 NPC 圖像資源（.bgf）名稱與外觀屬性
9. 編譯部署：新增 .kod 要動的 makefile/include；.bof/.rsc 部署流程
   （client 端更新後必跑 scripts/sync-rsc.sh）

## 行為規格

### Phase 1 跟隨
- 距主人 > N 格朝主人移動，≤ 2 格停止
- 主人換房間或死亡重生：佣兵直接傳送到主人身邊
- 主人登出：原地待命

### Phase 2 補血
- 主人 HP < 70% 時治療；每次 50 HP、冷卻 2 秒（皆為 property）
- 寧可超補不可少補，超過上限截斷至滿血
- 治療時 broadcast 訊息（字串進 .rsc）

### Phase 3 打怪
- 觸發：主人被攻擊 / 主人攻擊怪 / 敵對怪進入視野
- 目標優先序：打主人的怪 > 主人在打的怪 > 最近的怪；補血優先於攻擊
- 經驗：佣兵的傷害/擊殺，經驗一律歸主人
- 攻擊：物理＋魔法雙型態,目標物理打不動時切魔法（最簡實作即可）
- 定身：對「攻擊主人的怪」或圍攻怪群之一施放 Hold；冷卻 10 秒、持續 8 秒（可調）
- 禁止：攻擊玩家、攻擊其他佣兵、對玩家施放定身

### 數值與外觀
- 女性人形，重用既有女性 NPC 圖像資源
- HP 5000、攻擊力比照中階怪（調查後定）、移速與玩家相近
- 不死（雙重保險）：傷害使 HP ≤ 0 時攔截為 HP=1 並跳過死亡流程；每 tick 回血 100。
  攔截點必須在死亡判定 message 之前（Phase 0 第 3、6 項確認位置）

## 測試與版控
- 每 Phase：編譯 → 部署（含 client 同步）→ 重啟 server → admin 生成驗證 → 表格回報
- 每 Phase 一個 commit：`[merc] Phase N: <摘要>`；本地 mod 不推 upstream

---

# Phase 0 調查結論（已確認，不要重查）

- **基底 class 就用 `Monster`**（`kod/object/active/holder/nomoveon/battler/monster.kod`）。不用另找 pet 特化基底——`Animate`（詔喚不死）法術（`spell/animate.kod`）已經是現成雛型：拿 Skeleton/Zombie/Mummy（都繼承 Monster）當臨時佣兵用，跟隨/打怪/不打玩家全靠 `SetMaster` + 行為旗標達成，沒有另寫 AI。
- **跟隨**：`AI_MOVE_FOLLOW_MASTER`（`blakston.khd:1478`）旗標由 `brain.kod` 的 `MoveToMaster` 邏輯讀取；換房間跟隨是 `Monster.SomethingLeft`→`GotoMaster()`（monster.kod:933-980），對主人 `NewHold` 傳送過去，都是既有引擎行為，不用新寫。主人死亡重生是否觸發同一路徑：brain.kod 有「mourning the death of his master」的既有概念但沒有完整追完，Phase 1 順便驗證。
- **補血**：`Send(oTarget,@GainHealthNormal,#amount=X)`，Monster/Player 各自實作、都自動 clamp 上限，`Heal` 法術本身就這樣呼叫（`spell/heal.kod:129`）。Phase 2 直接用。
- **打怪/定身**：`SomethingAttacked(what,victim,use_weapon)` 廣播可判斷「主人被攻擊」；`Hold` 法術有公開 API `DoHold(what=施法者,otarget=目標,iDurationSecs=$)`（`spell/hold.kod:207`）可直接給 NPC 呼叫，不用重寫定身邏輯。Phase 3 用。
- **經驗歸屬（重要修正）**：M59 沒有「擊殺 XP 池」，技能成長是每次揮擊/施法當下依機率即時判定，只有 Player 有技能、Monster 沒有。**沒有現成的 credit 轉移機制**，佣兵打怪的技能成長天生不會歸主人——Phase 3 要決定：接受佣兵打怪不產生技能成長（最簡單），或另寫程式碼把技能成長算在 `poMaster` 頭上。
- **外觀**：`monster/lich.kod` 是「不死＋女性」的現成範例（`viGender = GENDER_FEMALE`, `licha.bgf`/`lichb.bgf`），已借用 `lichb.bgf`／`lichbx.bgf`（死亡圖）。
- **編譯部署**：`monster/makefile` 的 `BOFS` 清單要手動加檔名，不是自動掃描。**修正舊筆記錯誤**：`scripts/sync-rsc.sh` 這個檔案不存在，實際靠 Linux `makefile.linux` 的 `%.bof:%.kod` rule 自動把 `.rsc` 複製到 `run/server/rsc`；client（Windows 端 `run/localclient/resource`）要手動另外複製一份。

# Phase 1 實作記錄（跟隨，場測通過，已定案）

**新增檔案**：`kod/object/active/holder/nomoveon/battler/monster/mercenary.kod`
- `Mercenary is Monster`，`viGender = GENDER_FEMALE`，外觀借用 `lichb.bgf`
- `GetMaxHitPoints()` 覆寫回傳 5000（經 `Fuzzy()` 隨機化，等同其他怪物的 HP 算法）
- `viDefault_behavior = AI_MOVE_FOLLOW_MASTER`
- `BindMaster(oMaster=$)`：呼叫 `Send(self,@SetMaster,#oMaster=oMaster)` + 設 `pbDontDispose=TRUE`，讓 admin console 可以直接綁定主人；同時啟動 `LeashTimer`
- `SomethingAttacked` 覆寫：**主人打佣兵不會反擊**（見下方事故記錄），其餘情境（例如主人被別人攻擊）正常 propagate，留給 Phase 3 用
- `SomethingLeft` 覆寫：主人離開房間一律 `Post(self,@GotoMaster)`，不像 `Monster` 原生邏輯要求「離開當下需在 3 格內」才傳送
- `LeashTimer`（每 2 秒跑一次）：不同房間，或同房間但距主人 > 10 格（`MERC_LEASH_DISTANCE_SQ`），直接 `GotoMaster` 瞬移貼身——原生 `brain.kod` 的 `MoveToMaster` 只是龜速走位 tick，追不上戰鬥情境的節奏

**修改**：`monster/makefile` 的 `BOFS` 加入 `mercenary.bof`

**場測踩到的坑與修法**：
1. **主人誤攻擊佣兵，佣兵反擊把主人打死了**——`Monster.SomethingAttacked` 預設一律轉給 `poBrain` 判斷反擊，沒有「不能打自己主人」的例外。修法：`Mercenary` 覆寫 `SomethingAttacked`，`victim=self AND what=poMaster` 時直接跳過，不轉發給 brain。已用 admin console 模擬「主人攻擊佣兵」驗證：反擊目標維持 `$`（沒有設定）。
2. **同房間內跟隨太慢（10+ 秒才追到，戰鬥時人都死了）**——原生 `MoveToMaster` 走位 tick 速度是設計給一般怪物用的，不是為了緊貼跟隨。修法：加 `LeashTimer` 距離判斷，超過閾值直接瞬移，不等她走過去。
3. **`reload system` 熱重載後，舊的佣兵物件 ID 會被重新分配**（跟角色本身的 object ID 一樣，reload 時會換號），導致舊的（因為 `pbDontDispose=TRUE` 沒被回收）跟新建的同時存在，變成「兩隻佣兵」。**以後每次 `reload system` 之後，要先查一遍場上有沒有殘留舊佣兵再新建**，或改用 `send object <舊id> Delete` 清掉。

**部署驗證**：
1. `make -f makefile.linux`（在 `kod/` 下）編譯成功，`mercenary.bof`/`.rsc` 自動複製到 `run/server/{loadkod,rsc}`
2. 手動把 `mercenary.rsc` 複製到 Windows 端 `run/localclient/resource`（沒有 `sync-rsc.sh`，手動 cp）
3. `reload system` 熱重載（不斷線）
4. `create object Mercenary` → `BindMaster` → `NewHold` 到角色房間/位置
5. **實機驗收（你確認）**：跟隨速度 OK、換房間會傳送、攻擊她不會還手 ✅

**未處理，留給後續 Phase**：不死雙重保險（HP≤0攔截）、每 tick 回血、補血、打怪、定身、經驗歸屬——皆按規格分階段做。
