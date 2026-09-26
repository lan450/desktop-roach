# Astra 建模交接：DesktopRoach

目标：只优化桌面蟑螂的三维外形建模。不要重新搜索项目、外部资料或做代码调试；项目事实和建模边界已在此整理。交付建模改动后停止，由其他 AI 负责构建错误、运行故障和测试调试。

## 当前项目状态

- 项目：`/Users/maltjuice/Projects/desktop-roach`
- 当前分支：`master`，HEAD `9a3108b`（Review fixes: antenna/cercus euler signs, SCNShape layering comments, repo hygiene）。
- 来源：从本机 `Projects/desktop-fly` 的 `32b0001`（DesktopFly v1.1.0）分叉，新增蟑螂身体；不要把上游果蝇仓库改动混入本任务。
- 蟑螂主模型：`RoachModel.swift`；预览图 `assets/roach.png` 是当前快照，果蝇和锹甲对照分别在 `assets/fly.png`、`assets/beetle.png`。
- 最近已处理的问题：修正触角的欧拉角方向、尾须方向、`SCNShape` 厚度/层叠注释，补充了蟑螂预览图。不要回退这些调整。

## 已读取的项目资料

已通读项目 `CLAUDE.md`、`README.md`、`EVALUATION.md`、`RoachModel.swift`、`BeetleModel.swift`，并读取 `FlyModel.swift` 中的身体契约、公共几何构造和翅鞘动画。对照查看三张 `assets/*.png`。不用为了理解建模再遍历或搜索仓库。

## 模型是什么

这是 SceneKit 程序化建模的美洲大蠊外观，运行在透明桌面覆盖层中。顶部正交视角（相机沿 `-Z` 俯视，屏幕上 `+Y` 朝前，`+Z` 朝上，地面 `z=0`）是用户主要看到的视角。蟑螂只是果蝇神经/行为模拟驱动的替换身体，并没有蟑螂神经系统；本任务只改视觉几何/材质/造型，不调整生物仿真或行为。

当前轮廓识别点：低矮扁平身体；前胸背板（pronotum）宽盾状、遮住小头；棕红色革质前翅（tegmina）中缝明显、向腹部后方收尖；长鞭状触角向前伸展；六条外展分节足；腹端短尾须（cerci）。当前模型几何较简化，以平面轮廓挤出、球体、胶囊、圆锥构成。可以在 `RoachModel.swift` 内改几何与材质、位置、比例、层次、腿部造型和附件。默认画面参考 `assets/roach.png`：白底快照中盾状前胸偏矩形圆角，前翅近似水滴/长椭圆并有两道纵脉，六足和触角为分段胶囊。当前图不是生物学尺寸或准确性标准，只作为现有外观基线。

## 重要坐标/SceneKit 约束

- `RoachModel.swift` 顶部写明局部坐标：`+Y` 向前、`+Z` 向上；视角从 `-Z` 看下来。
- `SCNShape` 挤出厚度对称分布在节点局部 `z` 的正负两侧（例如 depth 2 是 `z=-1..+1`），不能按“只向下挤出”估算层级。当前 `RoachModel.swift` 的注释记录了实测结论。
- SceneKit `eulerAngles` 的这组姿态要结合轴顺序和视角判断。触角目前 `root.eulerAngles = (1.15, 0, -side*0.45)`，目的是抬离地面且左右外展；正负号在 HEAD 中已修正。不要盲目复制果蝇的负 pitch。
- 触角/腿/尾须等沿 `+Y` 的胶囊需将几何节点放在半长度，后续关节枢轴放在段末端；多段触角靠父子节点局部变换累积。
- `SCNShape` 用 `NSBezierPath` 建俯视轮廓，可用 `curve`、`flatness`、`chamferRadius` 控制外形和边缘；侧别路径通常通过 `side` 镜像，而不是缩放节点，以便两边旋转符号对称。

## 当前 RoachModel 结构（已读）

- 文件私有配色：`tegminaRed`、`bodyDark`、`rimTan`、`veinDark`。
- `tegmenShape(side:)`：前翅轮廓，内侧直边构成中缝，向后延伸约 15.6 个局部单位，外缘隆起并带倒角。
- `buildVeins(side:)`：每侧两条胶囊纵脉，作为前翅子节点，随前翅打开。
- `hindwingShape(side:)`：半透明膜质后翅，是动画实际拍动的翅；收拢时位于前翅下方，尾端有意稍微露出。路径预先旋转以抵消落地时固定的 `side*0.13` 折叠角。
- `pronotumShape()`：宽盾形前胸背板；浅棕色放大的底层 rim 与深色上层 shield 叠出边缘。
- `buildAntenna(side:)`：从头部前方起始的三节渐细长触角，当前正 pitch 抬高、左右镜像外展；视觉识别的重要部件。
- `buildCercus(side:)`：腹端成对锥形尾须，仅装饰，不接入传感器。
- `buildRoachModel()`：构建小头、眼、触角、前胸背板、腹部、六足、两片拍动后翅、前翅/脉络和尾须，并返回统一 `FlyModel`。
- 身体大部分 dorsal 表面高度约在 `z=5..6`，低于果蝇（10+）；`root.scale = FLY_SCALE`。所有坐标均为模型局部单位，别将局部单位说成真实长度。

## 不可破坏的身体接口

`FlyModel` 在 `FlyModel.swift` 定义，行为层不区分具体身体类型。`buildRoachModel() -> FlyModel` 必须继续提供：

- `root`
- 恰好 6 个 `legs`，顺序 RF、LF、RM、LM、RH、LH（供控制器索引）
- `foldedWings` 下恰好 2 个实际拍动翼面
- `blurWingL`、`blurWingR`
- 可被行为层呼吸缩放的 `abdomen` 空/父 pivot；腹部自身的压扁比例放在子几何节点上，避免被行为基础缩放覆盖
- 两个可选 `elytraL`、`elytraR`：蟑螂前翅（tegmina）挂在这两个节点上，沿用翅鞘展示动画
- 如调整拍动翼张开范围，身体级 `wingFlightSpread` 可按既有模型方式设置

`FlyModel.updateElytra` 只做展示：飞行时打开，受威胁姿态时抬起，回到地面时关闭；两片翅鞘保持角度，不跟随 `flapPhase` 高频摆动。外观改动不能改成新的行为规则，也不要触碰 `FlyModel.swift` 的控制逻辑。各身体共用 `buildLeg(...)` 与腿部运动学，所以建模可调整腿的附着点、长度和外观参数，不能更改控制顺序/运动代码。

## 建模任务边界与交付

只做蟑螂几何和外观：优先修改 `RoachModel.swift`，必要时只改蟑螂专属资源。不要改神经网络、行为、动力学、调度、平台适配或测试；不负责排查/修复编译、运行或测试问题，不扩展到果蝇/锹甲，不新增依赖，不联网找参考。

可以用现有 `assets/roach.png` 与既有快照入口作视觉参照。如果视觉检查需要构建/运行而遇到问题，记下具体阻塞并交给后续调试 AI；不要顺手修调试问题。结束时报告改过的建模文件、外形变化和未处理事项，停止在模型改动完成处。

相关快照入口（供后续负责验证的 AI 使用）：`./DesktopRoach --snapshot <输出.png> --top --roach`。仓库 `CLAUDE.md` 还描述了构建与测试，但本建模工作不要求执行这些调试/测试流程。
