/// 预设商城商品（按市场价值 1 积分 = 1 元配置），供情侣空间内一键添加。
class PresetMallGood {
  const PresetMallGood({
    required this.name,
    this.description,
    required this.pointsRequired,
    required this.category,
  });

  final String name;
  final String? description;
  final int pointsRequired;
  final String category;
}

/// 品类常量，与 UI 展示一致
class MallCategory {
  static const knowledge = '知识付费';
  static const tech = '科技赋能';
  static const assistant = '秘书助理';
  static const virtual = '虚拟类';
  static const charity = '公益类';
  static const companion = '陪伴类';
  static const books = '书籍类';
  static const gift = '礼物';

  static List<String> get all => [
        knowledge,
        tech,
        assistant,
        virtual,
        charity,
        companion,
        books,
        gift,
      ];
}

List<PresetMallGood> get presetMallGoods => [
      // —— 知识付费类 ——
      const PresetMallGood(
        name: '一起上的线上课程（你选）',
        description: '为我们共同报名一门线上课程，一起上完并交流收获',
        pointsRequired: 200,
        category: MallCategory.knowledge,
      ),
      const PresetMallGood(
        name: '为 TA 购买一个想学领域的课程/会员月卡',
        description: '尊重 TA 的选择，用积分支持 TA 的长期成长',
        pointsRequired: 300,
        category: MallCategory.knowledge,
      ),
      const PresetMallGood(
        name: '7 天共同学习打卡计划',
        description: '连续 7 天约定好一起学习/打卡，每天不少于 30 分钟',
        pointsRequired: 100,
        category: MallCategory.knowledge,
      ),
      const PresetMallGood(
        name: '一起参加一门系统课程',
        description: '为我们报名一门对关系或个人成长有帮助的系统课程',
        pointsRequired: 500,
        category: MallCategory.knowledge,
      ),

      // —— 科技赋能类 ——
      const PresetMallGood(
        name: '科技小配件升级包',
        description: '如数据线、手机支架、鼠标垫等，由 TA 选一件',
        pointsRequired: 100,
        category: MallCategory.tech,
      ),
      const PresetMallGood(
        name: '数码小外设礼物',
        description: '如耳机、小音箱、智能灯等，由 TA 选一件',
        pointsRequired: 300,
        category: MallCategory.tech,
      ),
      const PresetMallGood(
        name: '效率工具/AI 服务 1 个月',
        description: '为 TA 订阅一个实用的效率 App 或 AI 服务一个月',
        pointsRequired: 200,
        category: MallCategory.tech,
      ),
      const PresetMallGood(
        name: '升级一件科技产品',
        description: '为 TA 升级一件重要设备（如耳机、平板等），总价上限约 3000 元',
        pointsRequired: 3000,
        category: MallCategory.tech,
      ),

      // —— 秘书助理类 ——
      const PresetMallGood(
        name: '一次行程/出行管家服务',
        description: '帮 TA 规划并预订一次完整出行（路线、时间、吃住玩）',
        pointsRequired: 200,
        category: MallCategory.assistant,
      ),
      const PresetMallGood(
        name: '简历/作品集/文案优化服务',
        description: '认真帮 TA 改一次简历、作品集或重要文案',
        pointsRequired: 150,
        category: MallCategory.assistant,
      ),
      const PresetMallGood(
        name: '整理收纳/衣橱搭配一次',
        description: '帮 TA 整理房间或衣橱，并一起搭几套穿搭',
        pointsRequired: 200,
        category: MallCategory.assistant,
      ),
      const PresetMallGood(
        name: '解决一个一直拖延的事项',
        description: '帮 TA 处理一个一直拖着没做完的具体任务',
        pointsRequired: 150,
        category: MallCategory.assistant,
      ),

      // —— 虚拟类 ——
      const PresetMallGood(
        name: '反思示弱卡',
        description: '在争执后主动承认自己的问题，真诚反思并用温柔方式示弱',
        pointsRequired: 10,
        category: MallCategory.virtual,
      ),
      const PresetMallGood(
        name: '允许独处卡',
        description: '无条件允许 TA 独处一段时间（不超过 1 天），不追问不打扰',
        pointsRequired: 20,
        category: MallCategory.virtual,
      ),
      const PresetMallGood(
        name: '真诚理解卡',
        description: '复述 TA 的观点并表达理解，直到 TA 觉得被理解为止',
        pointsRequired: 15,
        category: MallCategory.virtual,
      ),
      const PresetMallGood(
        name: '认真聆听卡',
        description: '全程不打断地听 TA 倾诉至少 30 分钟',
        pointsRequired: 15,
        category: MallCategory.virtual,
      ),
      const PresetMallGood(
        name: '情绪抱抱卡',
        description: '当 TA 需要时，主动给一个长时间的拥抱和安慰',
        pointsRequired: 10,
        category: MallCategory.virtual,
      ),

      // —— 公益类 ——
      const PresetMallGood(
        name: '以 TA 名义捐款一次',
        description: '商量后以 TA 名义向一个公益项目捐款',
        pointsRequired: 100,
        category: MallCategory.charity,
      ),
      const PresetMallGood(
        name: '共同去做义工',
        description: '一起参加一场线下公益/义工活动',
        pointsRequired: 80,
        category: MallCategory.charity,
      ),
      const PresetMallGood(
        name: '一起完成一项环保行动',
        description: '例如徒步捡垃圾、无塑出行一天等',
        pointsRequired: 50,
        category: MallCategory.charity,
      ),

      // —— 陪伴类 ——
      const PresetMallGood(
        name: '一整晚不看手机的约会',
        description: '约定一晚只专注彼此，不刷手机不工作',
        pointsRequired: 100,
        category: MallCategory.companion,
      ),
      const PresetMallGood(
        name: '一起做饭 + 家常晚餐',
        description: '一起买菜做饭并慢慢吃完这顿饭',
        pointsRequired: 120,
        category: MallCategory.companion,
      ),
      const PresetMallGood(
        name: '一起看电影并好好聊聊',
        description: '看完一部电影后至少聊天 30 分钟，分享各自感受',
        pointsRequired: 80,
        category: MallCategory.companion,
      ),
      const PresetMallGood(
        name: '陪 TA 做一次 TA 的兴趣',
        description: '全程参与 TA 的兴趣活动一次，如运动、游戏或手作',
        pointsRequired: 100,
        category: MallCategory.companion,
      ),
      const PresetMallGood(
        name: '2–3 小时深度共处（学习/工作/读书）',
        description: '关掉干扰，一起专注 2–3 小时做同一件事',
        pointsRequired: 100,
        category: MallCategory.companion,
      ),

      // —— 书籍类 ——
      const PresetMallGood(
        name: '送 TA 一本一直想读的书',
        description: '由 TA 自己选书，你负责买单和包邮',
        pointsRequired: 60,
        category: MallCategory.books,
      ),
      const PresetMallGood(
        name: '互相推荐一本书',
        description: '各自选一本书送给对方，并在读完后互相分享',
        pointsRequired: 80,
        category: MallCategory.books,
      ),
      const PresetMallGood(
        name: '为 TA 准备一个小书单',
        description: '根据 TA 兴趣挑选 2–3 本书，总价上限约 150 元',
        pointsRequired: 150,
        category: MallCategory.books,
      ),

      // —— 礼物类 ——
      const PresetMallGood(
        name: '花束/小花礼物',
        description: '为 TA 送一束花或一份小型花礼',
        pointsRequired: 100,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '小首饰（项链/手链/耳饰）',
        description: '由 TA 选择一件小首饰，你负责买单',
        pointsRequired: 200,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '香薰/香水小礼物',
        description: '如香薰蜡烛、香水小样套装等，由 TA 选择',
        pointsRequired: 200,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '桌面小摆件/玩偶',
        description: '为 TA 选一个可爱的桌面摆件或玩偶',
        pointsRequired: 80,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '通勤包/运动包',
        description: '由 TA 选择一只适合日常使用的包',
        pointsRequired: 300,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '护肤/彩妆小礼物（TA 选）',
        description: '由 TA 自己挑选一件护肤或彩妆单品',
        pointsRequired: 150,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '纪念日惊喜礼盒',
        description: '为纪念日准备一份总价不超过约 500 元的小礼盒',
        pointsRequired: 500,
        category: MallCategory.gift,
      ),
      const PresetMallGood(
        name: '无条件和我道歉哄我不回避一次',
        description: '当你做错时，主动承认错误并认真哄我一次',
        pointsRequired: 20,
        category: MallCategory.gift,
      ),
    ];
