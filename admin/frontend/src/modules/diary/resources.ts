export type ResourceKind = 'user' | 'meal' | 'smoking' | 'workout' | 'usage';
export type Choice = { label: string; value: string | number; type?: string };
export type Field = {
	prop: string;
	label: string;
	type?: 'select' | 'number' | 'datetime' | 'textarea' | 'user';
	options?: Choice[];
	required?: boolean;
	min?: number;
	max?: number;
	precision?: number;
	value?: string | number;
};
export type Resource = {
	title: string;
	description: string;
	fields: Field[];
	columns: string[];
	filters: string[];
	readonly?: boolean;
	deletable?: boolean;
};

function choices(items: string[][]): Choice[] {
	return items.map(([value, label, type]) => ({ value, label, type }));
}

export const dictionaries = {
	gender: choices([
		['unknown', '未填写'],
		['male', '男'],
		['female', '女'],
		['private', '不愿透露']
	]),
	goal: choices([
		['health', '健康生活'],
		['lose_weight', '减脂'],
		['gain_muscle', '增肌'],
		['fitness', '提升体能'],
		['maintain', '保持状态']
	]),
	smokingStatus: choices([
		['unknown', '未填写'],
		['smoker', '抽烟'],
		['non_smoker', '不抽烟'],
		['quitting', '正在戒烟']
	]),
	userStatus: choices([
		['active', '正常', 'success'],
		['disabled', '停用', 'danger']
	]),
	mealType: choices([
		['breakfast', '早餐'],
		['lunch', '午餐'],
		['dinner', '晚餐'],
		['snack', '加餐']
	]),
	source: choices([
		['text', '文字分析'],
		['photo', '餐食照片'],
		['label', '营养成分表'],
		['manual', '后台录入']
	]),
	action: choices([
		['smoked', '自己抽', 'warning'],
		['gifted', '赠给他人', 'success']
	]),
	activityType: choices([
		['running', '跑步'],
		['walking', '步行'],
		['cycling', '骑行'],
		['strength', '力量训练'],
		['other', '其他']
	]),
	feature: choices([
		['meal_text', '文字记餐'],
		['meal_photo', '拍照记餐'],
		['nutrition_label', '营养表识别'],
		['smoking_pack', '烟盒识别'],
		['wellness_report', '汇总分析'],
		['running_report', '跑步分析']
	]),
	usageStatus: choices([
		['success', '成功', 'success'],
		['failed', '失败', 'danger']
	])
};

const user: Field = { prop: 'userId', label: '关联 App 用户', type: 'user', required: true };
const time: Field = { prop: 'recordedAt', label: '记录时间', type: 'datetime', required: true };
const notes: Field = { prop: 'notes', label: '备注', type: 'textarea' };
const select = (prop: string, label: string, options: Choice[], value?: string): Field => ({
	prop,
	label,
	type: 'select',
	options,
	required: true,
	value
});
const numeric = (
	prop: string,
	label: string,
	min = 0,
	max = 100000,
	required = false,
	precision = 2
): Field => ({ prop, label, type: 'number', min, max, required, precision });

export const resources: Record<ResourceKind, Resource> = {
	user: {
		title: 'App 用户',
		description: '维护用户资料、目标与账号状态，查看关联的生活记录。',
		columns: [
			'appUserId',
			'nickName',
			'gender',
			'age',
			'goal',
			'smokingStatus',
			'status',
			'createTime'
		],
		filters: ['status', 'gender', 'goal', 'smokingStatus'],
		fields: [
			{ prop: 'appUserId', label: 'App 用户标识', required: true },
			{ prop: 'nickName', label: '昵称', required: true },
			select('gender', '性别', dictionaries.gender, 'unknown'),
			numeric('age', '年龄', 0, 120, false, 0),
			numeric('heightCm', '身高 cm', 50, 250),
			numeric('weightKg', '体重 kg', 15, 400),
			numeric('targetWeightKg', '目标体重 kg', 15, 400),
			select('goal', '目标', dictionaries.goal, 'health'),
			select('smokingStatus', '抽烟情况', dictionaries.smokingStatus, 'unknown'),
			select('status', '账号状态', dictionaries.userStatus, 'active'),
			notes
		]
	},
	meal: {
		title: '饮食记录',
		description: '按用户、餐次与分析来源查看摄入，维护热量和营养素。',
		deletable: true,
		columns: [
			'userName',
			'mealType',
			'description',
			'source',
			'calories',
			'protein',
			'carbs',
			'fat',
			'recordedAt'
		],
		filters: ['mealType', 'source'],
		fields: [
			user,
			time,
			select('mealType', '餐次', dictionaries.mealType, 'lunch'),
			{ prop: 'description', label: '食物描述', type: 'textarea', required: true },
			select('source', '记录来源', dictionaries.source, 'manual'),
			numeric('calories', '热量 kcal', 0, 100000, true),
			numeric('protein', '蛋白质 g', 0, 10000, true),
			numeric('carbs', '碳水化合物 g', 0, 10000, true),
			numeric('fat', '脂肪 g', 0, 10000, true),
			{ prop: 'analysisSummary', label: '分析摘要', type: 'textarea' },
			notes
		]
	},
	smoking: {
		title: '抽烟记录',
		description: '区分自己抽和赠给他人，汇总自吸数量、包装标注与估算支出。',
		deletable: true,
		columns: [
			'userName',
			'action',
			'count',
			'packName',
			'packPrice',
			'nicotinePerCigarette',
			'_nicotine',
			'recordedAt'
		],
		filters: ['action'],
		fields: [
			user,
			time,
			select('action', '记录类型', dictionaries.action, 'smoked'),
			numeric('count', '数量 根', 1, 100, true, 0),
			{ prop: 'packName', label: '香烟名称', required: true },
			numeric('packPrice', '元 / 包（20根）', 0, 10000),
			numeric('nicotinePerCigarette', '标注 mg / 根', 0, 10, false, 3),
			notes
		]
	},
	workout: {
		title: '运动记录',
		description: '查看运动时长、距离、消耗和已记录的心率信息。',
		deletable: true,
		columns: [
			'userName',
			'activityType',
			'title',
			'distanceMeters',
			'durationSeconds',
			'_pace',
			'calories',
			'averageHeartRate',
			'recordedAt'
		],
		filters: ['activityType'],
		fields: [
			user,
			time,
			select('activityType', '运动类型', dictionaries.activityType, 'running'),
			{ prop: 'title', label: '运动名称', required: true },
			numeric('durationSeconds', '时长 秒', 1, 604800, true, 0),
			numeric('distanceMeters', '距离 米', 0, 1000000),
			numeric('calories', '消耗 kcal'),
			numeric('averageHeartRate', '平均心率 bpm', 30, 250, false, 0),
			numeric('maxHeartRate', '最高心率 bpm', 30, 250, false, 0),
			notes
		]
	},
	usage: {
		title: 'AI 用量',
		description: '查看各功能的请求、tokens、响应时延与预估费用。',
		readonly: true,
		columns: [
			'requestId',
			'userName',
			'feature',
			'model',
			'status',
			'_tokens',
			'cachedTokens',
			'latencyMs',
			'estimatedCostYuan',
			'recordedAt'
		],
		filters: ['feature', 'status'],
		fields: [
			user,
			time,
			{ prop: 'requestId', label: '请求标识' },
			select('feature', 'AI 功能', dictionaries.feature),
			{ prop: 'model', label: '模型' },
			select('status', '请求状态', dictionaries.usageStatus),
			numeric('promptTokens', '输入 tokens'),
			numeric('completionTokens', '输出 tokens'),
			numeric('cachedTokens', '输入缓存命中'),
			numeric('latencyMs', '响应时延 ms'),
			numeric('estimatedCostYuan', '预估费用 元', 0, 999999, false, 6),
			{ prop: 'errorMessage', label: '失败原因', type: 'textarea' },
			notes
		]
	}
};

export function fieldLabel(kind: ResourceKind, prop: string) {
	return (
		resources[kind].fields.find(field => field.prop === prop)?.label ||
		(
			{
				userName: 'App 用户',
				createTime: '创建时间',
				_nicotine: '自吸标注累计 mg',
				_tokens: '总 tokens',
				_pace: '配速 / km'
			} as Record<string, string>
		)[prop] ||
		prop
	);
}

export function displayField(kind: ResourceKind, prop: string, row: Record<string, any>) {
	const value = row[prop];
	if (prop === '_tokens') return Number(row.promptTokens) + Number(row.completionTokens);
	if (prop === '_nicotine')
		return row.action === 'gifted'
			? '赠出'
			: row.nicotinePerCigarette === null
				? '未知'
				: (Number(row.nicotinePerCigarette) * row.count).toFixed(3);
	if (prop === '_pace') {
		if (row.activityType !== 'running' || !Number(row.distanceMeters)) return '—';
		const seconds = Math.round(
			(Number(row.durationSeconds) / Number(row.distanceMeters)) * 1000
		);
		return `${Math.floor(seconds / 60)}′${String(seconds % 60).padStart(2, '0')}″`;
	}
	if (value === null || value === undefined || value === '') return '—';
	const field = resources[kind].fields.find(field => field.prop === prop);
	if (field?.options) return field.options.find(option => option.value === value)?.label || value;
	if (field?.type === 'number')
		return Number(value).toLocaleString('zh-CN', {
			maximumFractionDigits: field.precision ?? 2
		});
	return value;
}

export function metricCards(kind: ResourceKind, data: Record<string, any>) {
	if (!data) return [];
	const item = data[kind];
	const number = (value: number, digits = 0) =>
		Number(value || 0).toLocaleString('zh-CN', { maximumFractionDigits: digits });
	switch (kind) {
		case 'user':
			return [
				{ label: '用户数', value: number(item.total) },
				{ label: '正常账号', value: number(item.active) },
				{ label: '停用账号', value: number(item.total - item.active) }
			];
		case 'meal':
			return [
				{ label: '饮食记录', value: `${number(item.count)} 餐` },
				{ label: '摄入合计', value: `${number(item.calories)} kcal` },
				{ label: '蛋白质', value: `${number(item.protein, 1)} g` },
				{ label: '碳水 / 脂肪', value: `${number(item.carbs)} / ${number(item.fat)} g` }
			];
		case 'smoking':
			return [
				{ label: '自己抽', value: `${number(item.smoked)} 根` },
				{ label: '赠给他人', value: `${number(item.gifted)} 根` },
				{
					label: '自吸包装标注累计',
					value: `${number(item.nicotineMG, 3)} mg`,
					note: `${item.unknownNicotineCount} 根标注未知`
				},
				{
					label: '自吸估算支出',
					value: `¥ ${number(item.costYuan, 2)}`,
					note: `${item.unpricedCount} 根价格未知`
				}
			];
		case 'workout':
			return [
				{ label: '运动次数', value: number(item.count) },
				{ label: '运动时长', value: `${number(item.durationSeconds / 60)} 分钟` },
				{ label: '距离合计', value: `${number(item.distanceMeters / 1000, 2)} km` },
				{
					label: '运动消耗',
					value: `${number(item.calories)} kcal`,
					note: item.heartRateCount
						? `已记录平均心率 ${number(item.averageHeartRate)} bpm`
						: '心率未记录'
				}
			];
		case 'usage':
			return [
				{ label: 'AI 请求', value: number(item.count) },
				{ label: '成功 / 失败', value: `${number(item.success)} / ${number(item.failed)}` },
				{
					label: '总 tokens',
					value: number(item.totalTokens),
					note: `输入缓存命中 ${number(item.cachedTokens)}`
				},
				{
					label: '预估费用',
					value: `¥ ${number(item.estimatedCostYuan, 6)}`,
					note: '示例估算金额'
				}
			];
	}
}
