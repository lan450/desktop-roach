# 评审报告：蟑螂形态 + 繁殖殖民地 → Windows Electron 移植

- 评审对象：`~/Projects/desktop-roach` 未提交改动（git diff + 新文件 windows/src/roachmodel.js、windows/tools/）
- 评审方式：逐段对照 Swift 原版与 JS 移植的实际代码；关键数值用 node 做了数值验证（three r169）
- 已知基线（不复核）：npm test 46 项全过；Swift 三套件全过；快照视觉验收对齐参考图；白条问题已按 Phong 光强调材质

## 总览

移植总体质量高：几何公式逐项对照无符号/索引/翻转错误，RoachBreeding 全部常量与 colony tick 数学与 Swift 逐行一致，`withoutSharedRandom` 的种子流保护设计正确且必要，两处 Swift 修复逻辑均正确。发现 1 个 P1（`--demo-pair` 的 IPC 竞态，命令在 overlay 加载前发出会被丢弃）、2 个 P2（顶点色混合色彩空间跨平台漂移、一处测试强度低于 Swift 原版）及若干 P3。

---

## P1（必须修）

### P1-1 `--demo-pair` 的三条 cmd 在 overlay 加载前发送，会被静默丢弃

- 位置：`windows/main.js:412-416`（`app.whenReady()` 内）
- 问题：`createOverlay()` → `loadFile()` 是异步的；紧随其后的 `send(overlay,'cmd',{name:'addFly'})` ×2 和 `setBreedingSpeed` 在同一同步块内执行，此时渲染进程尚未 spawn、preload 的 `ipcRenderer.on('cmd')`（`windows/preload.mjs:17`）尚未注册。Electron 对"页面未加载完"的 `webContents.send` 不做排队，消息直接丢失——demo 模式大概率表现为"什么都没发生"（偶尔竞态成功，难以稳定复现）。
- 依据：同文件自己已展示了正确模式——`overlay.webContents.once('did-finish-load', publishGeometry)`（`windows/main.js:401`）。macOS 侧 `main.swift:887-893` 用 `enqueue{}` 把动作推迟到渲染循环首轮执行，因此不存在此问题；这是移植时把"入队"译成"立即发 IPC"引入的时序缺陷。
- 建议：把三条命令缓存，在 `did-finish-load` 回调里发送（或加一个 `overlayReady` 标志后 flush）。

---

## P2（应修）

### P2-1 `mixed()` 的色彩空间与 Swift 不同：所有顶点色中间调跨平台漂移

- 位置：`windows/src/roachmodel.js:44-47`（mixed）与 `RoachModel.swift:19-21`；涉及 tegmen/pronotum/abdomen/触角/腿的全部混色调用
- 问题：Swift 先在 sRGB（calibrated）分量上 `blended(withFraction:of:)`，再在 `vertex()` 里一次性转线性（`RoachModel.swift:34-41`）；JS 的调色板在模块加载时已由 `srgb()` 转成线性（`roachmodel.js:34-42`），`mixed()` 实际是在线性空间做 lerp。两种顺序结果不同。数值验证（three r169，ColorManagement.enabled=true）：`mixed(wingBlack, tegminaRed, 0.13)` 的 r 通道，Swift 路径 = 0.0066，JS 路径 = 0.0108（JS 偏亮 ~64%）。任何一个 amount 非 0/1 的混色都受影响，amount 越大偏差越大。
- 依据：`roachmodel.js:23-28` 的注释声称"srgb() 转线性与 Swift 的逐顶点 linear() 等价"——对最终写入是等价的，对**混合过程**不等价，注释覆盖不了这层。快照验收是对照参考照片做的且材质已调，因此视觉上被掩盖，但两个平台并排看时中间调会漂。
- 建议：要么忠实移植（在 sRGB 空间 lerp 再转线性：给 `mixed()` 传 sRGB 原始分量、输出前再 `srgb()`），要么把这一有意偏差写进文件头注释。二选一，不要让注释声称错误的对等。

### P2-2 "colony clock 压缩"的 JS 测试比 Swift 原版弱：`update()` 的时钟集成回归测不出来

- 位置：`windows/test/behaviortest.js:405-411`
- 问题：JS 版只断言 `daySecondsNow === 0.3`（纯 getter 检查）。Swift 对应检查（`main.swift:692-703`）建一只 Fly、设 100x、跑 60 次 `update(dt: 0.2)`，断言 12 s 真实时间长了 ~40 模拟天。如果 `windows/src/flymodel.js:797-798` 的 `dt / day` 被回归成 `dt / RoachBreeding.daySeconds`（丢掉 multiplier），JS 套件照样全绿，而 Swift 套件会红——同一行为在两平台测试强度不一致。
- 建议：照搬 Swift 版：跑 N 帧 update 后断言 `ageDays` 增量在 20..60 区间（记得保存/恢复 speedMultiplier）。

---

## P3（建议/备注）

### P3-1 colonyCap 的注释已过时（"每只蟑螂独享 ~30k 顶点网格"）

- 位置：`windows/src/flymodel.js:87-89`、`FlyModel.swift:32-34`
- BodyFactory 之后几何体全共享，每只克隆只新增节点（约 750 个 Object3D）。cap 仍是有效的内存/性能闸，但注释描述的模型已不成立，且 tray 提供 200 上限（`windows/main.js:240`），200 只 × ~750 节点的每帧 update 成本才是新的瓶颈。建议改注释并把 200 档的风险提示一下。

### P3-2 达到 cap 时孵化直接丢弃整窝卵鞘（两平台一致，确认是否有意）

- 位置：`windows/renderer/overlay.js:259-269`、`main.swift:975-983`
- `if (flies.length >= colonyCap) break;` 内层立刻 break，随后仍 `hatchDone()`——满员时母虫的卵鞘凭空消失并进入下一轮冷却。逻辑两平台逐行一致（parity 成立），但"到顶即绝育+弃卵"值得在注释里写明是设计而非疏漏。

### P3-3 渲染进程持有 RoachBreeding 真值，tray 只存"上次点过的值"

- 位置：`windows/main.js:43-45` vs `windows/renderer/overlay.js:463-465`
- speed/cap 的权威值在 overlay 模块里；overlay 崩溃重载后回落默认值（1x/48），tray 的 radio 勾选和 `colonyStatus` 仍是旧值。`colony-status`（每 5 s）已回传 `speed`/`cap`，但 `main.js:431-435` 只用于文案、没用来对齐 radio。低危（overlay 很少重载），建议用 status 里的值刷新 radio 勾选态。

### P3-4 `colony-status` 每 5 s 重建整个 tray 菜单

- 位置：`windows/main.js:431-436` → `refreshTray()`
- Windows 上 `setContextMenu` 在用户正打开菜单时会使其关闭。建议 label 未变化时跳过 rebuild。

### P3-5 渲染进程从不调 `warmBodyTemplates()`：首次切形态有一次同步建模板卡顿

- 位置：`windows/src/flymodel.js:445-447`；调用方仅 `windows/test/behaviortest.js:26`
- 生产路径首次 `setBodyForm('fly')` 在 cmd 处理器里懒建 fly 模板 + 48 次克隆，一次性几十毫秒。macOS 的 BodyFactory 同样懒建（parity 成立），故只算体验备注：可在启动 idle 时预热。

### P3-6 `setBodyForm` 命令缺同形态 no-op 保护

- 位置：`windows/renderer/overlay.js:458-462` vs `main.swift:1018` 的 `guard BODY_FORM != form`
- 当前 tray 只在切换时发送，触发不到；但与 Swift 的防御不对称，将来新入口可能造成整群无谓重建。

### P3-7 `key.position.set(...Object.values(...))` 依赖对象键插入顺序

- 位置：`windows/renderer/overlay.js:460`、`windows/tools/snapshot-scene.js:32`
- `{x,y,z}` 的 values 顺序目前正确但属隐式契约，建议显式 `pos.x, pos.y, pos.z`。（灯位数学本身我已独立验算：roach (0, sin.35, cos.35)·900、fly (sin.30, sin.35·cos.30, cos.35·cos.30)·900，与 main.swift:48 的 yaw 约定完全一致。）

### P3-8 `speedMultiplier` 只在 overlay 入口做 `Math.max(1, …)` 钳制

- 位置：`windows/src/flymodel.js:79-80`、`windows/renderer/overlay.js:464`
- 模块本体无下限，若被置 0，`update()` 里 `dt / day` → Infinity。建议把钳制收进 setter 或 RoachBreeding 内部（Swift 同样只在 setter 钳制，属同源弱点）。

### P3-9 snapshot 工具：非法参数路径依赖 20 s 超时兜底

- 位置：`windows/tools/snapshot.mjs:41-43`（`app.quit()` 在 whenReady 前调用可能不生效）、`snapshot.mjs:103-107`
- 非法 form 会一路走到 `snapshot-scene.js:32` 的 `KEY_POSITIONS[form]` 抛错，靠 20 s 超时退出。建议把校验挪到 whenReady 内用 `app.exit(1)`。

### P3-10 测试小项

- `behaviortest.js:447` 的 `const ootheca = { attached: false }` 占位对象是无用包装，直接布尔变量即可。
- `behaviortest.js:371-386` 共享几何只验证了 legs[0] 的股节一个 mesh；其他节点若被误克隆材质（每实例一份）不会被发现。可加一条"全 mesh 材质引用数 ≤ 模板数"的粗检查。
- `behaviortest.js:371` 的 `ms < 150` 是计时断言，慢机上可能抖动（Swift 同款阈值，parity 成立，仅备注）。
- `behaviortest.js:413-444` 未直接测 `canMate` 对 `broodCooldownDays > 0` 的拒绝（sleeper 用例同时被 cooldown/state 两道闸挡住，无法区分是哪道生效）。加一条 cooldown-only 的直接断言更干净。

---

## 分项对照结论（抽样与全查记录）

### A. RoachModel.swift ↔ roachmodel.js —— 无移植错误

逐公式对照全对：`tegmenPoint`（width/crown/±side 镜像）、`tegmenShape`（双层 z-0.12、`(side<0)!==(layer===1)` 翻转、周边 rim 闭合与 `side<0` flip、layerSize 索引）、`buildVeins`（8+10 条、`f*(2-f)` 缓入、z+radius*0.65 —— JS 里 `p[2]+=` 作用在每次新建的数组上，无别名问题）、`hindwingShape`（4 段三次贝塞尔逐控制点一致；rotateZ(-side*0.13) 等价路径 AffineTransform，挤出轴不受影响；translate -d/2 对称化）、`pronotumShape`（14 点 Catmull-Rom、`j*14/112` 取段、环形索引回绕、底盖绕向）、`buildAntenna`（65 点、sides=7、ringContrast 0.10、根位与球茎）、`buildCercus`、`buildAbdomen`（8 板 × 5×25、pivot scale 0.9/1.5/0.75）、`detailLeg`（kneeOffset 三档、股/胫 normal、前后腿刺数 3/5 与 4/7、跗节 5 节+双爪——`child.isMesh` 移除与 Swift `geometry != nil` 等价）、`buildRoachModel`（6 腿 specs 数值、foldedWings/tegmina/cerci/blurWing 位置与角度、返回契约字段全同，wingFlightSpread 0.8）。索引构建越界检查通过（逐 mesh 顶点数远小于 65535，three 自动选 index 类型）。逐顶点色：调色板九色数值逐一相符；alpha 分量被丢弃（Swift 写入但材质不透明，无损）。法线累积与零法线兜底 (0,0,1) 一致。有意漂移（已知项）：specular/shininess 全表重调（如 tegmen 0.56/0.78 → 0.03/50）、hindwing 膜色 0.43/0.30/0.16 → 0.16/0.11/0.06、球体细分 24→24×18——均为注释中说明的光照单位差补偿。唯一未声明的系统性漂移是 P2-1 的混合空间。

### B. FlyModel.swift ↔ flymodel.js —— 常量与数学一致

- RoachBreeding 全部常量逐一相等：30 / 1 / ootheca 2 / interval 4 / maturity 90 / nymph [0.38,0.52] / adult [0.8,1.25] / eggs [6,9]（+0.999 取整语义一致）/ cap 48 / pairDistance 70 / chance 0.2；`daySecondsNow` getter 一致。
- BodyFactory：`Object3D.clone(true)` 确实共享 geometry 与 material（three r169），与 `SCNNode.clone()` 共享 SCNGeometry 对应；blurWing 材质每实例私有化正确补偿了"SceneKit opacity 是节点属性、three opacity 是材质属性"的差异，且有测试锁定（behaviortest:371）。腿 spec 复制 + `leg.apply()` 恢复静止姿态与 Swift 一致。模板命名查找无歧义。
- `withoutSharedRandom`：设计正确——`rnd()` 走 `Math.random`（`src/util.js:3`），测试里被 `test/random.js` 播种；three 每个 Object3D 构造/clone 消耗一次 Math.random 生成 uuid，不隔离则换形态必然错位种子流。构建路径全程同步、无嵌套消费游戏随机（buildRoachModel/buildFlyModel 本身无 rnd 调用），无重入风险。
- colony tick（flymodel.js:796-812 ↔ FlyModel.swift:791-804）：逐行一致，含 `state!=='flying'` 时才写 scale、飞行中由 applyAltitude（已含 sizeScale）接管的细节；`land()` 与 `applyAltitude` 的 sizeScale 均对齐。
- updateElytra（flymodel.js:1194-1203 ↔ FlyModel.swift:1183-1191）：公式 0.62/0.85、左右符号、欧拉顺序映射一致。
- syncOotheca/hatchDone/tryFertilize/swapBody：与 Swift 修复后版本逐行一致；swapBody 复制 position/scale/rotation、复位渲染缓存、按 state 恢复 blur 可见性、重挂卵鞘。

### C. main.swift ↔ overlay.js —— 概率与顺序一致

- breedingTick：日志 5 s 节流、mothers 先快照后处理、每只孵化受 `flies.length < cap` 内层闸、courtship 前置 `>= cap return`、外层 `canMate` 过滤、内层 j>i、`dx²+dy² < 70²` 短路后才掷 `rnd < min(1, 0.2×speed×dt)`、每 tick 至多一次配对后 break——与 main.swift:956-1000 逐条等价。新增的 colony-status 每 5 s 上报是 Electron 特有扩展，无对应物、无害。
- forceMating：最近对选择、绕过 sleep 闸、`carrying=0 / interval / interval×0.5` 三连——等价。
- addFly：首只 size 1.0、后续 rnd(0.65,1.4)、锚点半径 rnd(40,75)（恰好跨越 pairDistance 70）±60 钳制——等价；首只的 onAnyScreen 24 次重试是"虚拟桌面为多屏并集"所需的合理 Windows 特有补充。
- key light：`keyLightPositionFor` 与 main.swift:48 的 `roach→yaw 0` 约定一致（数学已独立验算，见 P3-7）。

### D. 并发/内存/边界

- IPC：除 P1-1 外，命令单向下行、colony-status 5 s 上行，渲染线程内串行处理，无竞态面。
- 内存：卵鞘懒建单实例、hatchDone 即时摘除置空；swapBody 旧根只被移除不 dispose（几何与模板共享，正确地不做 dispose）；removeFly 连根回收。无泄漏点。
- 边界：100x 时孵化间隔 0.6 s、每窝 ≤9 只、cap 双闸（孵化内层 + courtship 前置），不会出现无界"hatch 风暴"；dt 被 0.05 钳制，概率上限 min(1,…) 兜底。

### E. 测试质量

8 项新检查总体能锁住行为：'form cycle'（behaviortest:446）直接锁定 syncOotheca 修复（4 次换形态后卵鞘仍挂在新 root 上）；'body swap'（341）锁定契约/状态保持/重挂载；'tegmina spread … steady'（289）用 jitter<0.05 区分"张开"与"随翅拍抖动"；'[roach] threat'（315）用 3 次重试规避 0.3% 自发起飞的假阴性而不弱化断言。locomotortest 的 `buildFlyModel()` 硬编码与 LocomotorTests.swift:30 对齐，且属必要修正（默认形态改为 roach 后，不修就会拿蟑螂腿当地力学基线）。弱点：P2-2（时钟压缩检查弱于 Swift）、P3-10 各条。

### F. Swift 侧两处修复 —— 均正确且无损

- `FlyModel.swift:693` `caseNode.parent !== model.root`：换形态后旧根的 parent 为 nil，旧判 `parent == nil` 会漏判"卵鞘还挂在被弃根上"；新判在已挂载时零开销（每 tick 仅一次指针比较），`addChildNode` 对已有父节点自动摘挂、不会重复。逻辑正确，行为面无回归（不携带时依旧只做 isHidden）。
- `FlyModel.swift:709-712` `mate` 形参：修复前当 rnd 选中 partner 当母亲时，`partner.broodCooldownDays` 先被设为 interval 再被 0.5 覆盖，而调用方 self 完全没有冷却，下一 tick 即可再配对；修复后母亲 interval、另一方 0.5×interval，双方必有冷却。不新增随机数消耗，种子流不变。备注：Swift 侧没有对应的"携带换形态"回归测试（JS 侧新增了 behaviortest:446），建议后续补一条。

---

## 结论

**需修后交付**：修掉 P1-1（--demo-pair 竞态，改动约五行）；P2-1 建议同一批处理（要么改 mixed 的色彩空间、要么改注释承认偏差）；P2-2 补一条测试即可。其余 P3 可随手或择机。

---

## 处置记录(2026-09-26,ZCode)

- **P1-1 --demo-pair IPC 竞态**:已修。tray/demo 命令现在入 `pendingCommands` 队列,与 publishGeometry 同在 `did-finish-load` 回调 flush(main.js)。
- **P2-1 mixed() 色彩空间**:已修。调色板改为保留原始 sRGB 分量,`mixed()` 在 sRGB 空间混合(NSColor.blended 语义),`RoachMesh.vertex` 写属性时一次性转线性(`linear()`,与 Swift 逐顶点转换同公式)。改后快照与 macOS 参考重新比对,观感一致且更接近。
- **P2-2 时钟压缩测试**:已加强。照 Swift 探针:100x 下跑 60 帧 update(0.2 s),断言 12 s 真实时间年龄增长 20..60 模拟天。
- **P3-1**:已修(两侧注释同步更新为"共享几何 + 节点/每 tick 成本"模型)。
- **P3-2**:已在 overlay.js 孵化处加注释说明"满员弃卵+冷却"是设计(与 main.swift 一致)。
- **P3-3**:已修,colony-status 回传的 speed/cap 现在同步刷新 tray radio 真值。
- **P3-4**:已修,label 未变化时跳过 setContextMenu 重建(避免 Windows 上打开中的菜单被关闭)。
- **P3-5**:已修,overlay 启动时调用 warmBodyTemplates()(同时是种子流卫生的一部分)。
- **P3-6**:已修,cmd 加同形态 no-op guard(对齐 main.swift)。
- **P3-7**:已修,key.position 显式 x/y/z(overlay 与 snapshot-scene)。
- **P3-8**:不修,与 Swift 保持同源(两侧都只在入口钳制);记录为已知对称弱点。
- **P3-9**:已修,form/pose 校验挪进 whenReady,非法参数 app.exit(1)。
- **P3-10**:ootheca 占位包装已简化;新增 cooldown-only 的 canMate 直接断言;全 mesh 材质引用数检查与 150ms 阈值保持现状(阈值与 Swift parity)。
- **F 备注(Swift 侧补"携带换形态"回归测试)**:记录为后续项,不在本批(JS 侧 behaviortest 'form cycle' 已锁定该行为)。

处置后回归:npm test 46/46 PASS;Swift build + simtest/behaviortest/locomotortest 全 PASS;快照(top/3-4/carry/fly)重新渲染并比对 macOS 参考图通过。
