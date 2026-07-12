# Meridian59 Server 除錯指引（Claude Code 必讀）

## 除錯原則（最高優先）

1. **禁止盲測**：每次修改前必須先說明「假設是什麼、依據是什麼」，修改後回報驗證結果。
2. **先搜尋、後動手**：遇到錯誤時，先用以下工具查既有解法，再開始修改：
   - `WebSearch` 搜尋關鍵字，例如 `Meridian59 client cannot login`、`Meridian59 blakserv WSL2`
   - `gh search issues --repo Meridian59/Meridian59 <關鍵字>`（如 login、connect、timeout）
   - `WebFetch` 讀取 repo 的 README 與 wiki 相關頁面
3. 搜尋後先整理出「常見原因清單」，再對照本機環境逐一驗證，每項都要回報檢查結果（通過 / 失敗 / 不適用）。
4. 不要重複嘗試已被排除的方向。

## Meridian59 登入問題檢查清單（依序驗證）

### A. WSL2 網路

**第一步：確認網路模式**（在 WSL2 內執行）：

```bash
wslinfo --networking-mode
```

**若為 `mirrored` 模式**：
- [ ] Windows 與 WSL2 共用網路介面，client 直接連 `127.0.0.1:5959` 即可，**不需要**查 WSL2 IP
- [ ] 確認 Windows 防火牆對 loopback / Hyper-V 介面的規則沒有擋連線（mirrored 模式下防火牆行為與 NAT 不同）
- [ ] 若外部機器也要連入，檢查 `.wslconfig` 是否需要 `[experimental] hostAddressLoopback=true` 等相關設定

**若為 `nat` 模式（預設）**：
- [ ] 先試 `127.0.0.1:5959`——NAT 模式有 `localhostForwarding`（預設開啟），Windows → WSL2 方向通常可通
- [ ] 若 127.0.0.1 不通，改用 WSL2 的 IP：`ip addr show eth0` 查詢後讓 client 連該 IP（注意此 IP 每次重開機會變動）
- [ ] `netsh interface portproxy show all`（Windows 端）確認是否有 port forwarding 干擾

### B. Port 與防火牆
- [ ] Server 預設 port 為 **5959**，用 `ss -tlnp | grep 5959` 確認 blakserv 有在監聽
- [ ] 確認監聽位址是 `0.0.0.0` 而非 `127.0.0.1`
- [ ] Windows 防火牆是否放行該 port（inbound rule）

### C. Server 設定
- [ ] 檢查 `blakserv.cfg` 內的 socket / port 設定
- [ ] 檢查 server console 是否有錯誤訊息或 channel log（`channel/` 目錄下的 log 檔）

### D. 帳號
- [ ] 帳號是否已建立？需在 server admin console 建立帳號（`create account` 相關指令）
- [ ] 確認帳號 credentials 與 client 輸入一致

### E. Client 設定
- [ ] `meridian.ini` 內的 server IP / port 是否正確指向 WSL2
- [ ] Client 版本與 server build 是否同步

### F. 資源檔
- [ ] `.rsc` 資源檔版本是否與 server 相符（版本不符會導致登入失敗或下載迴圈）
- [ ] Client 是否能完成 resource download 階段

## Client 版本選擇（重要結論，已查證）

**自架 server 必須用同一份 repo 自行編譯的 client，不要用 Steam 版。**

理由：
1. 官方 README 指定的本機測試方式就是用編譯出的 client 直連：
   `meridian.exe /U:帳號 /W:密碼 /H:localhost /P:5959`
2. Steam 版 client 是給官方 101/102 server 用的，protocol 與資源版本鎖定官方伺服器，且會自動更新，與 GitHub master 編譯的 server 幾乎必然版本不符
3. Client 與 server 的 .rsc 資源和 protocol 必須出自同一份原始碼，版本不符會觸發「登入 → 強制下載資源 → crash」（見下方 #1449）

## 版本一致性檢查（必做）

Client（clientd3d/）與 server（blakserv/）同在一個 repo，但仍需驗證兩件事：

**1. Repo 是否為最新版（是否落後 upstream master）**：
```bash
git remote -v                          # 確認 origin 指向 Meridian59/Meridian59
git fetch origin
git status                             # 檢查是否 behind origin/master
git log --oneline HEAD..origin/master  # 列出落後的 commits；有輸出就代表不是最新
```
- 若落後 → `git pull` 後 **client 與 server 都要重新編譯**

**2. Client 與 server 是否出自同一次 build**：
```bash
git log -1 --format=%H                 # 記下目前 commit
# 比對 client（Windows 端）與 server binary 的編譯時間是否接近同一時段
ls -l --time-style=long-iso blakserv/blakserv 2>/dev/null || find . -name "blakserv*" -newer .git -type f
```
- 常見漏洞：`git pull` 後只重編了 server、忘了重編 client（或反過來），導致 protocol / .rsc 不一致
- 結論：**任何一次 pull 之後，client、server、資源檔三者都要重新產出**

## 已知 Bug：登入後下載資源即 crash（#1449）

**症狀**：client 連上 server、登入後進入資源更新下載，下載完成即 crash（`table.c:91`）。

**根因**：PR #1314 在下載路徑加入 `FreeResources()`，但資源表在 `LoadResources()` 執行前為 NULL，`table_destroy` / `table_delete` 未做 NULL 檢查即解參考。

**修復**：PR #1449，於 **2026-06-11** merge。若 client build 早於此日期即會踩到。

**驗證與處理步驟**：
```bash
# 確認目前 checkout 是否包含修復
git log --oneline -5 -- clientd3d/table.c   # 或全 repo: git log --oneline --since=2026-06-01
```
- 若無該修復 → `git pull` 更新到最新 master 後重新編譯 client
- 重編後用命令列參數直連（排除 meridian.ini 干擾）：
  `meridian.exe /U:xxx /W:xxx /H:127.0.0.1 /P:5959`

**其他已知 crash issue（供交叉比對）**：
- #776（open）：software renderer 除以零 crash
- #770 / #771（closed）：client renderer / owner-drawn lists crash
- #993（closed）：重新進入遊戲時 renderer crash

## 回報格式

完成檢查後，用以下格式總結：

```
| 檢查項目 | 結果 | 證據 / 指令輸出摘要 |
|---------|------|-------------------|
```

找到根因後，先提出修復方案與風險，經確認再執行。

---

# Part 2：.rsc 資源檔缺失查修（目前進度，從此處開始執行）

## Part 1 已完成的結論（不要重查）

- Repo 未落後 upstream（本地領先 2 commits，為暫時修補）
- #1449 修復已包含（table.c:91、114 有 NULL 檢查）
- WSL2 mirrored 模式正常、port 0.0.0.0:5901／5960 監聽正常（**本專案自訂 port，非預設 5959**）
- Server log 證實帳號可成功登入，但數秒內斷線
- **Crash 點**：client 登入後在 `merintr.dll` 固定位移 `0xa6948` 100% 重現崩潰
- **判定根因**：client 的 `resource/` 目錄下 **0 個 .rsc 檔案**

## 因果鏈（假設，待驗證）

.rsc 是編譯 KOD 時由 blakcomp 產出的資源對照檔（ID → 字串/檔名）。
merintr.dll 是 client 的遊戲介面模組。登入成功後 server 推送遊戲狀態，
merintr 以資源 ID 查詢字串，因 .rsc 缺失查無結果、且該處無防禦性檢查
→ 固定 offset crash → 連線斷開。

## 查修步驟（依序執行）

1. **確認 server 端有無 .rsc**：
   ```bash
   find . -name "*.rsc" | head -20
   ```
   正常應在 run/server/rsc/ 或類似路徑，由編譯 KOD 時產出

2. **若 server 端也是 0 個** → KOD 從未編譯，先執行 KOD 編譯步驟產出 .rsc

3. **若 server 端有** → 檢查 build 流程中「複製資源到 client」的步驟
   （makefile / postbuild 腳本）為何沒執行，將 .rsc 補到 client 的 resource/ 目錄

4. **檢查 blakserv.cfg 資源下載設定**（download 路徑）：
   正常情況 client 連線時版本不符應觸發自動下載，這次完全沒下載，
   代表 server 端下載路徑可能也沒配置好——一併修正

5. **重測**：補上 .rsc 後重新登入，確認 merintr.dll `0xa6948` crash 是否消失，
   並回報 server log 是否仍有數秒斷線現象

## 後續追蹤（登入修復後才做）

merintr.dll「資源查詢失敗未檢查就使用」是防禦性缺失的真 bug（與 #1449 同類）。
登入問題解決後：
- 用 offset `0xa6948` 定位對應原始碼位置（merintr 模組）
- 加上查詢失敗檢查
- 已有 100% 重現步驟＋固定 offset，可向 upstream 開 issue 或 PR

---

# Part 3：根因已確認，執行修復（從此處開始執行）

## Part 2 查修結論（已驗證，不要重查）

**真正根因：資源包解壓覆蓋，不是建置鏈斷掉。**

時間戳證據鏈：
- KOD 編譯產出的 .rsc（run\server\rsc 共 1137 個）時間戳 07-11 03:56
- `instrsc.bat` 當時有正確將 .rsc 雙邊複製到 run\server\rsc 與 run\localclient\resource
- run\localclient\resource 資料夾建立時間 05:40（晚於 KOD 編譯）——
  解壓美術/音效資源包時**重建了整個資料夾**，把先前複製進去的 .rsc 全部清掉
- Server 端 run/server/rsc 未被解壓動到，1137 個檔案完好

**附帶發現（獨立問題，本次不處理）**：
Windows 端 KOD 編譯鏈是斷的（nmake 卡在 blakcomp 的 unistd.h 找不到，
blakcomp.exe 不存在），目前 .rsc 靠 WSL2 端編譯產物。
之後若要在 Windows 端改 KOD 會撞牆，先記錄於此。

## 修復步驟（依序執行）

1. **確認來源基準**：
   ```bash
   ls /home/idarfan/Meridian59/run/server/rsc/*.rsc | wc -l   # 應為 1137
   ```

2. **複製 .rsc 回 client**：將 run/server/rsc 下全部 .rsc 複製到
   Windows 端 `run\localclient\resource`，完成後確認 client 端數量同為 1137

3. **重測登入**：
   - 確認 merintr.dll `0xa6948` crash 是否消失
   - 確認 server log 不再出現數秒內斷線
   - 確認可正常進入遊戲世界

4. **防復發措施**（重測通過後執行）：
   - 建立同步腳本（如 `sync-rsc.sh` 或 `.bat`）：一鍵將 .rsc 從
     run/server/rsc 複製到 run\localclient\resource
   - 在建置說明（README 或本檔）加註：
     **「解壓美術資源包後，必須重跑 .rsc 同步步驟」**

5. **最終回報**：用表格總結修復前後狀態與各項驗證結果

## Part 3 完成後的待辦（依優先序）

1. merintr.dll 防禦性 bug（見 Part 2「後續追蹤」）——定位 offset 0xa6948
   對應原始碼、加查詢失敗檢查、考慮向 upstream 開 issue/PR
2. Windows 端 blakcomp 編譯鏈修復（unistd.h 問題）——僅在需要於
   Windows 端改 KOD 時處理

---

# Part 4：0xa6948 崩潰根因確認（已解決，非猜測）

## 手段：WinDbg 讀 crash dump（`C:\Users\mrida\AppData\Local\CrashDumps\meridian.exe.<pid>.dmp`）

用 `winget install Microsoft.WinDbg` 裝好後，用內附 `cdb.exe` 搭配已存在的
`meridian.pdb`（`clientd3d\debug\`）與 `merintr.pdb`（`module\merintr\debug\`，
均為 Debug 組態編譯產物，不需重編）跑：

```
cdb.exe -z <dump路徑> -y "C:\Meridian59-Build\clientd3d\debug;C:\Meridian59-Build\module\merintr\debug" -c ".lines; !analyze -v; kb; q"
```

`!analyze -v` 的自動分析因缺 OS 公開符號而誤判（`WRONG_SYMBOLS`），可忽略；
`kb` 指令產出的堆疊完全正確、帶原始碼行號：

```
merintr!strncpy+0x38          [strncpy.asm]
merintr!AddVerbAlias+0x260    [module/merintr/alias.c @ 413]
merintr!CmdAliasInit+0x12e    [module/merintr/alias.c @ 199]
merintr!InterfaceInit+0xd3    [module/merintr/mermain.c @ 61]
meridian!ModuleLoadByRsc      [clientd3d/modules.c @ 173]
meridian!HandleLoadModule     [clientd3d/server.c @ 1395]
meridian!MainReadSocket       [clientd3d/winmsg.c @ 553]
```
（Access violation 0xc0000005，`rdx=0`，"Attempt to read from address 0"）

## 根因（原始碼真實 bug，非本地環境問題）

`module/merintr/alias.c:59-69` 定義的 `_szDefaultVerbAliases` 是內嵌 `\0`
的多重字串（9 組別名接在一起，`GetPrivateProfileSection` 那種雙 NUL
結尾格式）：

```c
static const char* _szDefaultVerbAliases =
   "chuckle=emote chuckles.\0"
   "giggle=emote giggles.\0"
   ...
   "\0";
```

`alias.c:190` 用 `strdup(_szDefaultVerbAliases)` 複製它——但 `strdup()`
內部呼叫 `strlen()`，只要遇到第一個 `\0` 就停止，**只複製了第一組**
`"chuckle=emote chuckles."`，配置的記憶體也只有這一組的長度。

`CmdAliasInit`（alias.c:196-201）的解析迴圈處理完這唯一一組別名後，用
`pVerb = pCommand + strlen(pCommand) + 1` 往後移，這一步已經**超出
`strdup` 配置範圍**，屬於 heap 越界讀取。讀到的垃圾資料讓
`strtok` 解析失敗、`pCommand` 變成 NULL，傳進 `AddVerbAlias`
（alias.c:347）。該函式只檢查了 `pszVerb` 是否為 NULL/空字串，
**完全沒檢查 `pszCommand`**，直接在 alias.c:412
`strncpy(pAlias->text, pszCommand, MAX_ALIASLEN)` 對 NULL 指標解參考
→ 崩潰。

## 觸發條件

只有當 `meridian.ini` 缺少 `[CommandAliases]` section時，
`GetPrivateProfileSection` 才會返回空、觸發 `_szDefaultVerbAliases`
fallback，才會踩到這個 bug。本次 `C:\Meridian59-Build\run\localclient\
meridian.ini` 正好缺這個 section。

## 已執行的修復

**環境層（已生效，不動原始碼）**：在該 ini 補上 `[Aliases]`／
`[CommandAliases]` section（內容取自 WSL2 端 repo 的預設值），繞開
fallback 分支。三項驗證全過：
1. `merintr.dll` 0xa6948 crash 消失（Application Error 事件無新記錄）
2. 進入遊戲世界（視窗標題正確顯示房間名 `Raza Inn`，畫面截圖確認）
3. TCP 連線持續 `ESTAB` 40+ 秒未斷

## 待辦（原始碼真正的 bug，尚未修，供之後 patch／回報 upstream）

- `alias.c:190` 的 `strdup()` 用法錯誤，應改用正確處理多重字串長度的
  複製方式（例如手動算總長度含結尾雙 NUL，或改寫 `_szDefaultVerbAliases`
  為陣列而非單一內嵌字串常數）
- `AddVerbAlias`（alias.c:347）應比照 `pszVerb` 的檢查方式，加上
  `if (!pszCommand) return FALSE;`
- 已有 100% 重現步驟＋精確行號＋完整堆疊，證據齊全，適合直接開
  GitHub issue 或 PR 給 upstream

---

# Final Part：畫面解析度差／軟體渲染問題（已解決）

## 症狀

登入進遊戲後（Part 3 修復完成、可正常操作），畫面明顯模糊、色塊感重。

## 根因

`C:\Meridian59-Build\run\localclient\config.ini` 的 `[config]` 區塊：

```
gpuefficiency=true
softwarerenderer=true
rendererfailedonce=false
```

`clientd3d/d3ddriver.c` 驗證：

1. **`softwarerenderer=true`**（d3ddriver.c:48-53）：`D3DDriverProfileInit()`
   一開始就檢查這個 ini 值，若為 `true` **完全不嘗試**硬體 Direct3D，
   直接強制用 CPU 軟體渲染——這是畫面模糊、色塊感重的主因。這個旗標是
   「一次寫死、之後每次沿用」，不會自動恢復嘗試硬體渲染
   （d3ddriver.c:351-360：只有硬體 D3D 初始化檢查失敗時才會被自動寫入
   `true`，且與 `rendererfailedonce` 同時寫入——但本次
   `rendererfailedonce=false` 與 `softwarerenderer=true` 同時存在,
   這種組合不是這段程式碼正常執行的結果,研判是這份 config.ini
   本來就是以這個狀態被準備好、而非真的偵測失敗過)。

2. **`gpuefficiency=true`**（d3ddriver.c:65-75）：決定遊戲內部渲染畫布
   解析度，`true` 固定 800x600（4:3），`false` 則為 1920x1080（16:9）。
   視窗開得再大，畫面本質上都是把 800x600 內容放大填滿，因而模糊。

## 已執行的修復

把 `config.ini` 改為：
```
gpuefficiency=false
dynamiclighting=false
softwarerenderer=false
rendererfailedonce=false
```

風險低、可逆：若顯卡真的不支援硬體 D3D，程式碼會自動偵測失敗、跳出
提示訊息、自動寫回 `softwarerenderer=true` 並改用軟體渲染，不會卡死
或黑屏。

## 附帶排除：一度懷疑「鍵盤無法移動角色」與 `/Q`（quickstart）有關

**已證實無關，純屬測試方式造成的假象，非 client 或上述修復的問題。**

用 PowerShell `Start-Process` 自動啟動 client 並用 `SetForegroundWindow`
+ `SendKeys` 模擬操作，發現方向鍵完全無法移動角色；但比對命令列
（`Get-CimInstance Win32_Process`）發現，使用者親自雙擊桌面捷徑啟動的
**同樣帶 `/Q` 參數**的 instance 卻可以正常移動——證明 `/Q` 本身不是原因。

真正差異在於**啟動方式**：自動化背景啟動的視窗雖然在 Win32 API
層級「看起來」是前景視窗（`GetForegroundWindow()`、螢幕截圖都正常），
但這是 Windows 系統層級的「焦點竊取保護」（focus-stealing prevention）
機制所致——非使用者真實互動觸發建立的視窗，作業系統不會把真正的鍵盤
輸入路由完整交給它。使用者直接雙擊桌面捷徑（真實互動路徑）即可正常
操作，無需修改任何設定或原始碼。
