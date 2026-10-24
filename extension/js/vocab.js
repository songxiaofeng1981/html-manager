// Controlled vocabulary and categories. The helper (helper/ManagerHost.swift) has its own copy:
// change both together. / 受控标签和分类。本机助手 ManagerHost.swift 里另有一份，修改时两处要一起改。

export const HTML_CONTROLLED = [{"group":"对象","tag":"Remotion","scope":"视频制作框架或组件明确基于 Remotion 的页面和工作流。"},{"group":"对象","tag":"AVGO","scope":"涉及 Broadcom（AVGO）公司、持仓或投资判断的笔记。"},{"group":"对象","tag":"MU","scope":"涉及 Micron（MU）公司、持仓或投资判断的笔记。"},{"group":"对象","tag":"NVDA","scope":"涉及 NVIDIA（NVDA）公司、持仓或投资判断的笔记。"},{"group":"对象","tag":"INTC","scope":"涉及 Intel（INTC）或其期权示例的笔记。"},{"group":"对象","tag":"PySceneDetect","scope":"讨论或使用 PySceneDetect 镜头切分工具的笔记。"},{"group":"对象","tag":"WhisperX","scope":"讨论或使用 WhisperX 转写、对齐能力的笔记。"},{"group":"主题","tag":"公司研究","scope":"分析具体上市公司业务、竞争位置、催化因素或投资逻辑。"},{"group":"主题","tag":"组合管理","scope":"涉及持仓配置、组合复盘、买入决策或仓位管理。"},{"group":"主题","tag":"风险控制","scope":"讨论回撤、杠杆、期权风险、止损或风险检查方法。"},{"group":"主题","tag":"AI算力","scope":"讨论 AI 计算需求、数据中心、芯片、供电或相关产业链。"},{"group":"主题","tag":"视觉动效","scope":"展示或设计标题、卡片、叠层、通知等视频画面组件。"},{"group":"主题","tag":"字幕包装","scope":"设计字幕、姓名条或逐词高亮等文字信息包装。"},{"group":"主题","tag":"视频转场","scope":"讨论或展示镜头、素材之间的转场方式。"},{"group":"主题","tag":"健康知识","scope":"整理疾病、检测、治疗或健康管理相关信息。"},{"group":"主题","tag":"工作流","scope":"说明一项创作、管理或内容生产任务的步骤与协作流程。"},{"group":"主题","tag":"沟通表达","scope":"围绕口播、反馈、表达方式或沟通内容的设计与整理。"},{"group":"类型","tag":"示例","scope":"可直接预览的视觉组件、动效或页面样例。"},{"group":"类型","tag":"研究","scope":"以资料梳理、论据比较或判断形成为主的分析笔记。"},{"group":"类型","tag":"复盘","scope":"回顾一段投资、工作或内容生产过程并总结结果。"},{"group":"类型","tag":"教程","scope":"提供概念解释、操作步骤或可照做的方法。"},{"group":"类型","tag":"模板","scope":"可复用的表单、结构或管理框架。"},{"group":"类型","tag":"知识卡","scope":"以问答、图鉴或便于快速查阅的摘要方式呈现资料。"}];

export const MD_CONTROLLED = [{"group":"对象","tag":"AI 工具","scope":"Markdown 中讨论的 AI 助手、提示词和创作辅助工具。"},{"group":"对象","tag":"视频素材","scope":"Markdown 中讨论的 B-roll、录制素材和可复用视频片段。"},{"group":"对象","tag":"Remotion","scope":"Markdown 中直接讨论的 Remotion 项目、组件或规范。"},{"group":"对象","tag":"半导体与算力","scope":"Markdown 中讨论的芯片、内存、GPU 和算力产业。"},{"group":"主题","tag":"投资研究","scope":"Markdown 中的投资逻辑、产业研究和决策依据。"},{"group":"主题","tag":"市场走势","scope":"Markdown 中的行情变化和市场环境跟踪。"},{"group":"主题","tag":"组合管理","scope":"Markdown 中的组合配置、仓位和持仓管理。"},{"group":"主题","tag":"风险管理","scope":"Markdown 中的风险识别、验证条件和回撤应对。"},{"group":"主题","tag":"视频制作","scope":"Markdown 中的视频录制、剪辑和制作流程。"},{"group":"主题","tag":"口播表达","scope":"Markdown 中的口播文案、表达结构和节奏。"},{"group":"主题","tag":"视觉设计","scope":"Markdown 中的视频画面、组件样式和动效。"},{"group":"主题","tag":"知识管理","scope":"Markdown 中的知识整理、提示词和协作规范。"},{"group":"类型","tag":"演示示例","scope":"Markdown 中可用于预览或测试的样例。"},{"group":"类型","tag":"研究拆解","scope":"Markdown 中的研究分析与思路推导。"},{"group":"类型","tag":"复盘记录","scope":"Markdown 中回顾投资、业务或项目结果的记录。"},{"group":"类型","tag":"制作规范","scope":"Markdown 中可反复遵循的视频制作或协作规范。"},{"group":"类型","tag":"操作教程","scope":"Markdown 中解释操作步骤或入门方式的内容。"},{"group":"类型","tag":"流程工作流","scope":"Markdown 中按步骤组织、可重复执行的流程。"}];

// Tag groups as written in the vocabulary. / 词表里的标签分组。
export const TAG_GROUPS = ['对象', '主题', '类型'];

// Categories accepted on import, with their color (Apple system colors). / 收录时可选的分类及颜色（Apple 系统色）。
export const CATEGORIES = ['投资与市场', '视频制作与流程', '视觉设计与组件', '健康与生活资料', '工作与管理'];

const TOPICS = {
  invest: '#ff9500',
  video: '#007aff',
  tech: '#af52de',
  life: '#34c759',
  work: '#30b0c7',
  misc: '#8e8e93',
};

/** Topic key and color for a category name, including older free-form names. / 分类名对应的主题和颜色（兼容旧的自由分类名）。 */
export function categoryTopic(category = '') {
  const key =
    category === '投资与市场' ? 'invest'
    : category === '视频制作与流程' ? 'video'
    : category === '视觉设计与组件' ? 'tech'
    : category === '健康与生活资料' ? 'life'
    : category === '工作与管理' ? 'work'
    : /投资|期权|个股|市场|行业|半导体/.test(category) ? 'invest'
    : /视频|口播|Remotion/.test(category) ? 'video'
    : /AI|知识|开发规范/.test(category) ? 'tech'
    : /健康|园艺/.test(category) ? 'life'
    : /管理|团队|业务|沟通/.test(category) ? 'work'
    : 'misc';
  return { key, color: TOPICS[key] };
}

export const isControlledTag = tag => HTML_CONTROLLED.some(x => x.tag === tag);
