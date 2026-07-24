# IntentAgent Builder L0 架构

## 1. 整体定义

IntentAgent Builder 是一套用于构建 IntentAgent 的 Agent 工具链。它根据不同业务场景的意图体系、数据条件和复杂度要求，组织意图定义、数据准备、Agent 构建、评价与优化，最终交付满足场景需求的 IntentAgent。

工具链由一个负责完整开发流程的 IntentAgent Builder 和四个负责专业阶段的核心 Agent 组成：

- **IntentAgent Builder**：通过 Build Loop 组织并迭代完整开发流程；
- **Intent Ingestion Agent**：定义和规范化意图；
- **Data Factory Agent**：准备并检验数据；
- **IntentAgentDeveloper**：配置和拼装 IntentAgent；
- **Evaluation Agent**：评价、优化和自动回测。

四个核心 Agent 均可独立使用，也可以由 IntentAgent Builder 按需调用。

### 1.1 整体职责

- 将 IntentAgent 开发组织为可执行、可评价和可迭代的流程；
- 根据当前阶段渐进收集材料，不要求用户在启动时一次提供全部信息；
- 自动调用相应核心 Agent，并在阶段之间传递结果；
- 展示构建状态、发现的问题和可操作建议；
- 仅在缺少必要材料或业务语义必须由人判断时请求用户介入；
- 达到验收目标后交付可保存、可重新加载的 IntentAgent。

## 2. 系统输入与输出

### 2.1 整体输入

| 输入类别 | 主要内容 | 提供时机 |
| --- | --- | --- |
| 起始材料 | 包含 Intent 名称和描述的 Excel 或 CSV 清单，以及开发目标 | 启动构建时 |
| 意图设计要求 | Layer 分层原则 Markdown（说明意图层级的划分方法）、任务说明和运行配置 | 可选；定义意图阶段 |
| 数据材料 | 用户样例、已有数据集、FAQ 或知识内容 | 可选；准备数据阶段 |
| 构建要求 | 运行约束、构建配置和可用工具 | 可选；构建 Agent 阶段 |
| 评价要求 | 评测数据、Bad Case、验收目标、允许优化的范围和停止条件 | 可选；评价阶段 |
| 交互补充 | 系统无法自动获得的信息或需要用户判断的业务语义 | 按需 |

除起始材料外，其余输入都可以由用户预先提供，也可以由 Builder 在进入对应阶段后再收集。

### 2.2 整体输出

主要交付结果是经过评价并满足验收目标的 IntentAgent。该 IntentAgent 必须能够保存到本地，并在构建进程退出后重新加载。

系统同时保留下列结果，便于使用、复查和继续优化：

| 输出类别 | 主要内容 |
| --- | --- |
| IntentAgent | 可运行并可重新加载的最终 Agent |
| 有效配置 | 最终实际生效的构建与运行配置 |
| 评价结果 | 评测结果、问题分析和目标达成判断 |
| 优化记录 | 优化内容、自动回测结果及过程日志 |
| 阶段结果 | 标准 Intent 清单、变更记录（Change Log）、数据结果和构建信息 |
| 未完成反馈 | 未解决的问题、影响范围和下一步建议 |

## 3. 总体架构

![IntentAgent Builder 架构框图](../assets/intentagent-builder-architecture.png)

IntentAgent Builder 通过内部的 `Build Loop()` 自动组织四个阶段。Build Loop 复用已有材料和阶段结果，判断当前需要调用的核心 Agent，并根据 Evaluation Agent 的反馈继续优化相关阶段。

四个核心 Agent 之间不构成必须逐项传递的单一流水线：

- Intent Ingestion Agent 的结果可以交给 Data Factory Agent，也可以直接交付用户；
- Data Factory Agent 准备的数据主要用于开发和评价；
- IntentAgentDeveloper 根据构建要求、配置和可选工具拼装 IntentAgent，不以数据集作为必需输入；
- Evaluation Agent 组合 IntentAgent 候选、评测数据和验收目标完成评价与优化；
- Builder 负责在完整流程中选择调用顺序和传递必要结果。

## 4. 模块职责与输入输出

### 4.1 IntentAgent Builder

**职责**

- 理解开发目标并确定当前开发阶段；
- 通过 Build Loop 按需调用四个核心 Agent；
- 渐进收集当前阶段所需材料，并优先复用已有信息；
- 根据评价反馈自动调整相关阶段；
- 汇总构建状态和阶段结果，完成最终交付。

**主要输入**

- 包含名称和描述的 Intent 清单、Layer 分层原则等起始材料；
- IntentAgent 的开发目标；
- 随流程补充的数据、构建配置、验收目标和运行约束；
- 必要的用户补充信息或业务语义判断。

**主要输出**

- 满足验收目标、可保存和重新加载的 IntentAgent；
- 实际生效的配置、评价结果和优化日志；
- 构建过程中的阶段结果；
- 未完成时的明确问题和建议。

### 4.2 Intent Ingestion Agent

**职责**

- 规范化 Intent 名称和描述；
- 根据分层原则构造 Intent 的层级关系；
- 检验意图体系中的设计期冲突；
- 通过多轮处理和必要的用户判断形成边界清晰的 Intent 体系。

**主要输入**

- 包含 Intent 名称和描述的 Excel 或 CSV 清单；
- 可选的 Layer 分层原则 Markdown；
- 可选的运行配置和任务说明；
- 运行过程中用户对冲突和建议的批量判断或补充说明。

**主要输出**

- 任务完成时的标准 Intent 清单和变更记录（Change Log）；
- 迭代过程中的冲突、影响范围和修改建议；
- 需要用户判断的问题和当前处理状态。

### 4.3 Data Factory Agent

**职责**

- 检查已有数据是否满足开发和评测要求；
- 根据场景需要补充、增强或合成数据；
- 执行数据质量检查和数据冲突检验；
- 形成可供开发和评价使用的数据结果。

**主要输入**

- 标准 Intent 清单；
- 用户样例、已有数据、FAQ 或知识内容；
- 数据数量、分布、质量和使用约束。

**主要输出**

- 经过校验的开发、验证和测试数据；
- 数据质量报告和冲突报告；
- 数据不足或需要用户补充时的明确说明。

### 4.4 IntentAgentDeveloper

**职责**

- 根据场景要求选择和应用 IntentAgent 配置；
- 拼装 IntentAgent 所需的模型、Prompt 和其他运行组件；
- 形成可供 Evaluation Agent 评价的 IntentAgent 候选。

**主要输入**

- IntentAgent 构建要求；
- 运行约束和构建配置；
- 可选的可用工具。

**主要输出**

- 可运行的 IntentAgent 候选；
- 候选使用的有效配置和构建信息；
- 构建失败时的原因和可调整项。

### 4.5 Evaluation Agent

**职责**

- 根据验收目标自动执行评测；
- 收集并分析测试集和 Bad Case 的运行结果；
- 在允许范围内优化 IntentAgent；
- 自动回测优化结果并判断是否达到目标。

**主要输入**

- 可运行的 IntentAgent 候选；
- 评测数据和 Bad Case；
- 验收目标、允许优化的范围和停止条件。

**主要输出**

- 评测结果和问题分析；
- 优化建议及已执行的优化记录；
- 自动回测结果和目标达成判断；
- 建议调整的意图、数据或构建环节。

## 5. 使用方式

### 5.1 独立使用核心 Agent

用户或外部系统可以直接调用任一核心 Agent，提供该阶段所需材料并取得对应结果。独立使用时，调用方负责决定如何使用该结果，以及是否交给其他模块继续处理。

### 5.2 使用完整 Build Loop

用户向 IntentAgent Builder 提供起始材料和开发目标后，Builder 启动 Build Loop：

1. 根据当前状态选择需要调用的核心 Agent；
2. 检查并渐进收集该阶段所需材料；
3. 保存阶段结果并自动进入下一项必要工作；
4. 根据评价反馈调整相关阶段并再次评价；
5. 达到验收目标后交付 IntentAgent。

正常流程不要求用户控制阶段切换。只有必要材料无法获得、业务语义需要判断、达到停止条件或用户主动暂停时，Builder 才停止自动推进并给出明确反馈。

## 6. L1 架构

- [IntentAgent Builder](./builder/L1-architecture.md)
- [Intent Ingestion](./intent-ingestion/L1-architecture.md)
- [Data Factory](./data-factory/L1-architecture.md)
- [IntentAgentDeveloper](./intent-agent-developer/L1-architecture.md)
- [Evaluation](./evaluation/L1-architecture.md)
