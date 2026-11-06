export type DiaryKind = 'user' | 'meal' | 'smoking' | 'workout' | 'usage';

type Rule = {
  label: string;
  type: 'text' | 'number' | 'enum' | 'date';
  required?: boolean;
  max?: number;
  min?: number;
  integer?: boolean;
  values?: string[];
  default?: unknown;
};

const text = (label: string, max = 2000, required = false): Rule => ({
  label,
  type: 'text',
  max,
  required,
});
const number = (
  label: string,
  min: number,
  max: number,
  required = false,
  integer = false
): Rule => ({ label, type: 'number', min, max, required, integer });
const choice = (label: string, values: string[], value?: string): Rule => ({
  label,
  type: 'enum',
  values,
  default: value,
  required: true,
});
const common = {
  userId: number('关联用户', 1, Number.MAX_SAFE_INTEGER, true, true),
  recordedAt: { label: '记录时间', type: 'date', required: true } as Rule,
  notes: text('备注'),
};

const rules: Record<DiaryKind, Record<string, Rule>> = {
  user: {
    appUserId: text('App 用户标识', 64, true),
    nickName: text('昵称', 40, true),
    gender: choice('性别', ['unknown', 'male', 'female', 'private'], 'unknown'),
    age: number('年龄', 0, 120, false, true),
    heightCm: number('身高', 50, 250),
    weightKg: number('体重', 15, 400),
    targetWeightKg: number('目标体重', 15, 400),
    goal: choice(
      '目标',
      ['health', 'lose_weight', 'gain_muscle', 'fitness', 'maintain'],
      'health'
    ),
    smokingStatus: choice(
      '抽烟情况',
      ['unknown', 'smoker', 'non_smoker', 'quitting'],
      'unknown'
    ),
    status: choice('账号状态', ['active', 'disabled'], 'active'),
    notes: text('备注'),
  },
  meal: {
    ...common,
    mealType: choice('餐次', ['breakfast', 'lunch', 'dinner', 'snack']),
    description: text('食物描述', 2000, true),
    source: choice('记录来源', ['text', 'photo', 'label', 'manual'], 'text'),
    calories: number('热量', 0, 100000, true),
    protein: number('蛋白质', 0, 10000, true),
    carbs: number('碳水化合物', 0, 10000, true),
    fat: number('脂肪', 0, 10000, true),
    analysisSummary: text('分析摘要'),
  },
  smoking: {
    ...common,
    action: choice('记录类型', ['smoked', 'gifted']),
    count: number('香烟数量', 1, 100, true, true),
    packName: text('香烟名称', 100, true),
    packPrice: number('每包价格', 0, 10000),
    nicotinePerCigarette: number('每根尼古丁标注', 0, 10),
  },
  workout: {
    ...common,
    activityType: choice('运动类型', [
      'running',
      'walking',
      'cycling',
      'strength',
      'other',
    ]),
    title: text('运动名称', 100, true),
    durationSeconds: number('运动时长', 1, 604800, true, true),
    distanceMeters: number('运动距离', 0, 1000000),
    calories: number('运动消耗', 0, 100000),
    averageHeartRate: number('平均心率', 30, 250, false, true),
    maxHeartRate: number('最高心率', 30, 250, false, true),
  },
  usage: {
    ...common,
    requestId: text('请求标识', 100, true),
    feature: choice('AI 功能', [
      'meal_text',
      'meal_photo',
      'nutrition_label',
      'smoking_pack',
      'wellness_report',
      'running_report',
    ]),
    model: text('模型', 80, true),
    status: choice('请求状态', ['success', 'failed']),
    promptTokens: number('输入 tokens', 0, 100000000, true, true),
    completionTokens: number('输出 tokens', 0, 100000000, true, true),
    cachedTokens: number('缓存命中 tokens', 0, 100000000, true, true),
    latencyMs: number('响应时延', 0, 3600000, true, true),
    estimatedCostYuan: number('预估费用', 0, 999999, true),
    errorMessage: text('失败原因'),
  },
};

function validDate(value: string, withTime: boolean) {
  const pattern = withTime
    ? /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/
    : /^\d{4}-\d{2}-\d{2}$/;
  if (!pattern.test(value)) return false;
  const normalized = withTime ? value.replace(' ', 'T') : `${value}T00:00:00`;
  const date = new Date(`${normalized}Z`);
  return (
    Number.isFinite(date.getTime()) &&
    date.toISOString().slice(0, withTime ? 19 : 10) ===
      normalized.slice(0, withTime ? 19 : 10)
  );
}

export function normalizeRecord(kind: DiaryKind, input: Record<string, any>) {
  const result: Record<string, any> = { isDemo: true };
  for (const [field, rule] of Object.entries(rules[kind])) {
    let value = input[field];
    if (value === undefined || value === null || value === '') {
      value = rule.default;
      if (value === undefined) {
        if (rule.required) throw new Error(`请填写${rule.label}`);
        result[field] = rule.type === 'text' ? '' : null;
        continue;
      }
    }
    if (rule.type === 'number') {
      if (
        !['number', 'string'].includes(typeof value) ||
        String(value).trim() === ''
      )
        throw new Error(`${rule.label}需要为有效数字`);
      value = Number(value);
      if (
        !Number.isFinite(value) ||
        value < rule.min ||
        value > rule.max ||
        (rule.integer && !Number.isSafeInteger(value))
      )
        throw new Error(`${rule.label}超出有效范围`);
    } else {
      if (typeof value !== 'string') throw new Error(`${rule.label}格式错误`);
      value = value.trim();
      if ((rule.required && !value) || (rule.max && value.length > rule.max))
        throw new Error(`${rule.label}长度不正确`);
      if (rule.type === 'enum' && !rule.values.includes(value))
        throw new Error(`${rule.label}选项错误`);
      if (rule.type === 'date' && !validDate(value, true))
        throw new Error(`${rule.label}格式错误`);
    }
    result[field] = value;
  }
  if (kind === 'usage' && result.cachedTokens > result.promptTokens)
    throw new Error('缓存命中 tokens 不能大于输入 tokens');
  if (
    kind === 'workout' &&
    result.averageHeartRate !== null &&
    result.maxHeartRate !== null &&
    result.maxHeartRate < result.averageHeartRate
  )
    throw new Error('最高心率不能低于平均心率');
  return result;
}

export function dateFilters(input: Record<string, any>) {
  const { startDate, endDate, userId } = input;
  if (startDate && !validDate(startDate, false))
    throw new Error('开始日期格式错误');
  if (endDate && !validDate(endDate, false))
    throw new Error('结束日期格式错误');
  if (startDate && endDate && startDate > endDate)
    throw new Error('开始日期不能晚于结束日期');
  const conditions: any[][] = [];
  if (startDate)
    conditions.push([
      'a.recordedAt >= :startTime',
      { startTime: `${startDate} 00:00:00` },
    ]);
  if (endDate)
    conditions.push([
      'a.recordedAt <= :endTime',
      { endTime: `${endDate} 23:59:59` },
    ]);
  if (userId !== undefined && userId !== null && userId !== '') {
    if (
      !/^\d+$/.test(String(userId)) ||
      !Number.isSafeInteger(Number(userId)) ||
      Number(userId) < 1
    )
      throw new Error('关联用户格式错误');
    conditions.push([
      'a.userId = :diaryUserId',
      { diaryUserId: Number(userId) },
    ]);
  }
  return conditions;
}

export function tokenTotal(row: Record<string, any>) {
  return Number(row.promptTokens) + Number(row.completionTokens);
}

export function resourceFilters(kind: DiaryKind, input: Record<string, any>) {
  const conditions = kind === 'user' ? [] : dateFilters(input);
  if (kind === 'user' && input.userId !== undefined && input.userId !== '') {
    for (const [sql, params] of dateFilters({ userId: input.userId }))
      conditions.push([sql.replace('a.userId', 'a.id'), params]);
  }
  const fields = {
    user: ['status', 'gender', 'goal', 'smokingStatus'],
    meal: ['mealType', 'source'],
    smoking: ['action'],
    workout: ['activityType'],
    usage: ['feature', 'status'],
  }[kind];
  for (const field of fields) {
    const value = input[field];
    if (value === undefined || value === '') continue;
    if (!rules[kind][field].values.includes(value))
      throw new Error(`${rules[kind][field].label}筛选错误`);
    conditions.push([
      `a.${field} = :filter_${field}`,
      { [`filter_${field}`]: value },
    ]);
  }
  if (input.keyWord) {
    if (typeof input.keyWord !== 'string' || input.keyWord.length > 100)
      throw new Error('搜索词长度不正确');
    const columns = {
      user: ['a.nickName', 'a.appUserId'],
      meal: ['a.description', 'u.nickName'],
      smoking: ['a.packName', 'u.nickName'],
      workout: ['a.title', 'u.nickName'],
      usage: ['a.requestId', 'a.model', 'u.nickName'],
    }[kind];
    conditions.push([
      `(${columns.map(field => `${field} LIKE :diaryKeyword`).join(' OR ')})`,
      { diaryKeyword: `%${input.keyWord}%` },
    ]);
  }
  return conditions;
}
