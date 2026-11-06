<template>
	<el-scrollbar>
		<section class="business-overview" v-loading="loading">
			<header>
				<div class="brand">
					<img :src="logoUrl" alt="小食痰记" />
					<div>
						<h1>小食痰记 · 业务总览</h1>
						<p>饮食、生活、运动与 AI 服务的管理视图</p>
					</div>
				</div>
				<el-tag type="warning">示例环境</el-tag>
			</header>
			<el-alert
				title="当前展示合成示例数据，可用于检查管理流程和统计口径。"
				type="warning"
				:closable="false"
				show-icon
			/>
			<div class="toolbar">
				<el-select
					v-model="userId"
					placeholder="全部 App 用户"
					clearable
					filterable
					@change="load"
					><el-option
						v-for="user in users"
						:key="user.id"
						:label="`${user.nickName} · ${user.appUserId}`"
						:value="user.id"
				/></el-select>
				<el-radio-group v-model="range" @change="changeRange"
					><el-radio-button :value="7">近 7 天</el-radio-button
					><el-radio-button :value="30">近 30 天</el-radio-button
					><el-radio-button :value="0">全部</el-radio-button></el-radio-group
				>
				<el-date-picker
					v-model="dates"
					type="daterange"
					value-format="YYYY-MM-DD"
					start-placeholder="开始日期"
					end-placeholder="结束日期"
					@change="customRange"
				/>
				<el-button @click="load">刷新</el-button>
			</div>
			<el-alert v-if="error" :title="error" type="error" :closable="false" />
			<template v-if="summary">
				<div class="overview-cards">
					<button
						v-for="card in cards"
						:key="card.kind"
						class="overview-card"
						@click="open(card.kind)"
					>
						<span>{{ card.label }}</span
						><strong>{{ card.value }}</strong
						><small>{{ card.note }}</small
						><span class="card-link">进入管理 →</span>
					</button>
				</div>
				<div class="panels">
					<el-card shadow="never"
						><template #header><h3>饮食与运动</h3></template
						><diary-metrics :cards="balanceCards" />
						<p class="hint">
							摄入与运动消耗分别展示，所有统计均来自所选区间的示例记录。
						</p></el-card
					>
					<el-card shadow="never"
						><template #header><h3>AI 请求情况</h3></template
						><diary-metrics :cards="aiCards" />
						<p class="hint">
							缓存命中属于输入 tokens，预估费用由示例记录提供。
						</p></el-card
					>
				</div>
				<el-card shadow="never"
					><template #header
						><div class="trend-heading">
							<h3>按日趋势</h3>
							<small>最近有记录的 14 天</small>
						</div></template
					>
					<el-table :data="recentTrend" stripe empty-text="所选区间暂无记录">
						<el-table-column prop="date" label="日期" min-width="130" />
						<el-table-column label="饮食摄入 kcal" min-width="220"
							><template #default="{ row }"
								><div class="trend-cell">
									<span>{{ number(row.calories) }}</span
									><el-progress
										:percentage="trendPercent(row.calories)"
										:show-text="false"
										:stroke-width="8"
									/></div></template
						></el-table-column>
						<el-table-column label="自吸 根" min-width="100"
							><template #default="{ row }">{{
								number(row.smoked)
							}}</template></el-table-column
						>
						<el-table-column label="运动 分钟" min-width="120"
							><template #default="{ row }">{{
								number(row.minutes)
							}}</template></el-table-column
						>
						<el-table-column label="AI tokens" min-width="130"
							><template #default="{ row }">{{
								number(row.tokens)
							}}</template></el-table-column
						>
					</el-table>
				</el-card>
			</template>
		</section>
	</el-scrollbar>
</template>

<script setup lang="ts">
defineOptions({ name: 'diary-overview' });
import { computed, onMounted, ref } from 'vue';
import dayjs from 'dayjs';
import { useCool } from '/@/cool';
import DiaryMetrics from '../components/metrics.vue';
import type { ResourceKind } from '../resources';

const { service, router } = useCool();
const users = ref<{ id: number; nickName: string; appUserId: string }[]>([]);
const userId = ref<number>();
const range = ref(30);
const dates = ref<string[] | undefined>([
	dayjs().subtract(29, 'day').format('YYYY-MM-DD'),
	dayjs().format('YYYY-MM-DD')
]);
const loading = ref(false);
const error = ref('');
const summary = ref<Record<string, any> | null>(null);
const trend = ref<
	{ date: string; calories: number; smoked: number; minutes: number; tokens: number }[]
>([]);
let version = 0;
const number = (value: number, digits = 0) =>
	Number(value || 0).toLocaleString('zh-CN', { maximumFractionDigits: digits });
const cards = computed(() => {
	if (!summary.value) return [];
	const { user, meal, smoking, workout, usage } = summary.value;
	return [
		{
			kind: 'user' as ResourceKind,
			label: 'App 用户',
			value: number(user.total),
			note: `${user.active} 个正常账号`
		},
		{
			kind: 'meal' as ResourceKind,
			label: '饮食记录',
			value: `${number(meal.count)} 餐`,
			note: `${number(meal.calories)} kcal 摄入`
		},
		{
			kind: 'smoking' as ResourceKind,
			label: '抽烟情况',
			value: `${number(smoking.smoked)} 根`,
			note: `赠出 ${smoking.gifted} 根 · 独立统计`
		},
		{
			kind: 'workout' as ResourceKind,
			label: '运动记录',
			value: `${number(workout.count)} 次`,
			note: `${number(workout.distanceMeters / 1000, 2)} km · ${number(workout.durationSeconds / 60)} 分钟`
		},
		{
			kind: 'usage' as ResourceKind,
			label: 'AI 请求',
			value: number(usage.count),
			note: `预估 ¥ ${number(usage.estimatedCostYuan, 6)}`
		}
	];
});
const balanceCards = computed(() =>
	summary.value
		? [
				{ label: '摄入合计', value: `${number(summary.value.meal.calories)} kcal` },
				{ label: '运动消耗', value: `${number(summary.value.workout.calories)} kcal` },
				{ label: '蛋白质合计', value: `${number(summary.value.meal.protein, 1)} g` }
			]
		: []
);
const aiCards = computed(() =>
	summary.value
		? [
				{
					label: '成功率',
					value: summary.value.usage.count
						? `${number((summary.value.usage.success / summary.value.usage.count) * 100, 1)}%`
						: '—'
				},
				{ label: '失败请求', value: number(summary.value.usage.failed) },
				{ label: '平均响应', value: `${number(summary.value.usage.latencyMs / 1000, 2)} s` }
			]
		: []
);
const recentTrend = computed(() => trend.value.slice(-14).reverse());
const maxCalories = computed(() => Math.max(1, ...recentTrend.value.map(row => row.calories)));
function trendPercent(value: number) {
	return Math.min(100, Math.round((value / maxCalories.value) * 100));
}
async function load() {
	const requestVersion = ++version;
	loading.value = true;
	error.value = '';
	try {
		const input = {
			userId: userId.value,
			startDate: dates.value?.[0],
			endDate: dates.value?.[1]
		};
		const [result, daily] = await Promise.all([
			service.diary.overview.summary(input),
			service.diary.overview.trend(input)
		]);
		if (requestVersion === version) {
			summary.value = result;
			trend.value = daily;
		}
	} catch (cause) {
		if (requestVersion === version) {
			error.value = (cause as Error).message || '加载业务数据失败';
			summary.value = null;
			trend.value = [];
		}
	} finally {
		if (requestVersion === version) loading.value = false;
	}
}
function changeRange() {
	dates.value = range.value
		? [
				dayjs()
					.subtract(range.value - 1, 'day')
					.format('YYYY-MM-DD'),
				dayjs().format('YYYY-MM-DD')
			]
		: undefined;
	load();
}
function customRange() {
	range.value = -1;
	load();
}
function open(kind: ResourceKind) {
	router.push({
		path: `/diary/${kind}`,
		query: userId.value && kind !== 'user' ? { userId: userId.value } : {}
	});
}
onMounted(async () => {
	await load();
	try {
		users.value = await service.diary.user.options();
	} catch (cause) {
		error.value = (cause as Error).message || '加载用户选项失败';
	}
});
const logoUrl = `${import.meta.env.BASE_URL}logo.png`;
</script>

<style scoped>
.business-overview {
	padding: 12px;
	display: flex;
	flex-direction: column;
	gap: 20px;
}
header {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: 16px;
}
.brand {
	display: flex;
	align-items: center;
	gap: 16px;
}
.brand img {
	width: 64px;
	height: 64px;
	border-radius: 16px;
}
h1 {
	font-size: 26px;
	margin: 0 0 8px;
}
h3 {
	font-size: 16px;
	margin: 0;
}
p,
small {
	color: var(--el-text-color-secondary);
}
.toolbar {
	display: flex;
	flex-wrap: wrap;
	gap: 12px;
}
.toolbar :deep(.el-select) {
	width: 230px;
}
.toolbar :deep(.el-date-editor) {
	width: 280px;
	flex-grow: 0;
}
.overview-cards {
	display: grid;
	grid-template-columns: repeat(5, minmax(0, 1fr));
	gap: 14px;
}
.overview-card {
	text-align: left;
	font: inherit;
	cursor: pointer;
	color: var(--el-text-color-primary);
	background: var(--el-bg-color);
	border: 1px solid var(--el-border-color-light);
	border-radius: 14px;
	padding: 20px;
	display: flex;
	flex-direction: column;
	gap: 12px;
}
.overview-card:hover {
	border-color: var(--el-color-primary);
}
.overview-card strong {
	font-size: 28px;
}
.card-link {
	color: var(--el-color-primary);
	font-size: 12px;
}
.panels {
	display: grid;
	grid-template-columns: 1fr 1fr;
	gap: 16px;
}
.hint {
	font-size: 12px;
	line-height: 1.8;
	margin-top: 14px;
}
.trend-heading {
	display: flex;
	justify-content: space-between;
	gap: 12px;
}
.trend-cell {
	display: flex;
	align-items: center;
	gap: 12px;
}
.trend-cell span {
	width: 70px;
}
.trend-cell :deep(.el-progress) {
	flex: 1;
}
@media (max-width: 1300px) {
	.overview-cards {
		grid-template-columns: repeat(3, minmax(0, 1fr));
	}
	.panels {
		grid-template-columns: 1fr;
	}
}
@media (max-width: 700px) {
	.business-overview {
		padding: 0;
	}
	.overview-cards {
		grid-template-columns: repeat(2, minmax(0, 1fr));
	}
	h1 {
		font-size: 20px;
	}
	.brand img {
		width: 48px;
		height: 48px;
	}
	header {
		align-items: flex-start;
	}
	.toolbar :deep(.el-select),
	.toolbar :deep(.el-date-editor) {
		width: 100%;
	}
	.overview-card {
		padding: 16px;
	}
	.overview-card strong {
		font-size: 24px;
	}
}
</style>
