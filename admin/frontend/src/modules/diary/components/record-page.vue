<template>
	<section class="diary-page">
		<header class="page-heading">
			<div>
				<h2>{{ resource.title }}</h2>
				<p>{{ resource.description }}</p>
			</div>
			<el-tag type="warning">示例数据</el-tag>
		</header>
		<diary-metrics :cards="cards" />
		<el-alert
			v-if="kind === 'smoking'"
			title="尼古丁使用包装标注值累计，赠出单独记录。每包按 20 根估算支出，未知标注和价格单独保留。"
			type="info"
			:closable="false"
		/>
		<el-alert
			v-if="kind === 'usage'"
			title="总 tokens = 输入 + 输出，缓存命中已包含在输入中。费用为合成示例估算。"
			type="info"
			:closable="false"
		/>
		<div class="filters">
			<el-select
				v-if="kind !== 'user'"
				v-model="filters.userId"
				placeholder="全部 App 用户"
				clearable
				filterable
				:loading="usersLoading"
				@visible-change="visible => visible && refreshUsers()"
				><el-option
					v-for="option in users"
					:key="option.value"
					:label="option.label"
					:value="option.value"
			/></el-select>
			<el-date-picker
				v-if="kind !== 'user'"
				v-model="dates"
				type="daterange"
				value-format="YYYY-MM-DD"
				start-placeholder="开始日期"
				end-placeholder="结束日期"
				unlink-panels
			/>
			<el-select
				v-for="field in filterFields"
				:key="field.prop"
				v-model="filters[field.prop]"
				:placeholder="field.label"
				clearable
				><el-option
					v-for="option in field.options"
					:key="option.value"
					:label="option.label"
					:value="option.value"
			/></el-select>
			<el-input
				v-model="filters.keyWord"
				placeholder="搜索名称、描述或标识"
				clearable
				@keyup.enter="search"
			/>
			<el-button type="primary" @click="search">查询</el-button
			><el-button @click="reset">重置</el-button>
		</div>
		<cl-crud ref="Crud">
			<cl-row
				><cl-refresh-btn /><cl-add-btn v-if="!resource.readonly" /><cl-multi-delete-btn
					v-if="resource.deletable"
				/><cl-flex1 /><span class="table-note">{{
					kind === 'user' ? 'App 业务示例账号' : '统计跟随当前筛选条件'
				}}</span></cl-row
			>
			<cl-row
				><cl-table ref="Table"
					><template #slot-detail="{ scope }"
						><el-button
							v-permission="api.permission.info"
							link
							type="primary"
							@click="openDetail(scope.row)"
							>详情</el-button
						></template
					></cl-table
				></cl-row
			>
			<cl-row><cl-flex1 /><cl-pagination /></cl-row>
			<cl-upsert v-if="!resource.readonly" ref="Upsert" />
		</cl-crud>
		<el-drawer
			v-model="detailVisible"
			:title="`${resource.title}详情`"
			size="min(640px, 100vw)"
		>
			<el-tag type="warning">合成示例记录</el-tag>
			<el-descriptions v-loading="detailLoading" :column="1" border class="detail-fields">
				<el-descriptions-item label="记录 ID">{{ detail.id }}</el-descriptions-item>
				<el-descriptions-item v-if="kind !== 'user'" label="App 用户">{{
					detail.userName || userLabel(detail.userId)
				}}</el-descriptions-item>
				<el-descriptions-item
					v-for="field in resource.fields.filter(field => field.prop !== 'userId')"
					:key="field.prop"
					:label="field.label"
					><span class="detail-value">{{
						displayField(kind, field.prop, detail)
					}}</span></el-descriptions-item
				>
				<el-descriptions-item v-if="kind === 'user'" label="BMI">{{
					bmi
				}}</el-descriptions-item>
				<el-descriptions-item label="创建时间">{{
					detail.createTime
				}}</el-descriptions-item>
				<el-descriptions-item label="更新时间">{{
					detail.updateTime
				}}</el-descriptions-item>
			</el-descriptions>
			<template v-if="kind === 'user'">
				<h3>关联记录 · 全部时间</h3>
				<diary-metrics :cards="userCards" />
				<div class="record-links">
					<el-button
						v-for="item in linkedResources"
						:key="item.kind"
						v-permission="service.diary[item.kind].permission.page"
						:disabled="detailLoading"
						@click="goToRecords(item.kind)"
						>{{ item.label }}</el-button
					>
				</div>
			</template>
		</el-drawer>
	</section>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch, onActivated, onDeactivated } from 'vue';
import { useCrud, useTable, useUpsert } from '@cool-vue/crud';
import { ElMessage } from 'element-plus';
import dayjs from 'dayjs';
import { useCool } from '/@/cool';
import { useRoute } from 'vue-router';
import DiaryMetrics from './metrics.vue';
import { createRequestScope } from '../request-scope';
import {
	resources,
	displayField,
	fieldLabel,
	metricCards,
	type ResourceKind,
	type Choice,
	type Field
} from '../resources';

const props = defineProps<{ kind: ResourceKind }>();
const kind = props.kind;
const resource = resources[kind];
const { service, router } = useCool();
const route = useRoute();
// 五类资源共享 Cool Admin 的 CRUD 契约，具体能力由资源配置和接口权限约束。
const api = service.diary[kind] as any;
const users = reactive<Choice[]>([]);
const filters = reactive<Record<string, any>>({
	userId: route.query.userId ? Number(route.query.userId) : undefined,
	keyWord: ''
});
const dates = ref<string[] | undefined>([
	dayjs().subtract(29, 'day').format('YYYY-MM-DD'),
	dayjs().format('YYYY-MM-DD')
]);
const summary = ref<Record<string, any> | null>(null);
const cards = computed(() => (summary.value ? metricCards(kind, summary.value) : []));
const filterFields = resource.fields.filter(field => resource.filters.includes(field.prop));
const summaryRequests = createRequestScope();
const detailRequests = createRequestScope();
const optionRequests = createRequestScope();
const usersLoading = ref(false);

async function refreshUsers() {
	if (kind === 'user') return;
	const current = optionRequests.begin();
	usersLoading.value = true;
	try {
		const data = await service.diary.user.options();
		if (current())
			users.splice(
				0,
				users.length,
				...data.map(item => ({
					value: item.id,
					label: `${item.nickName} · ${item.appUserId}`
				}))
			);
	} catch (error) {
		if (current())
			ElMessage.error(
				(error as Error).message || '加载用户选项失败，请重新展开用户选择器重试'
			);
	} finally {
		if (current()) usersLoading.value = false;
	}
}

function query() {
	return {
		...filters,
		...(kind !== 'user' ? { startDate: dates.value?.[0], endDate: dates.value?.[1] } : {})
	};
}

function search() {
	Crud.value?.refresh({ page: 1 });
}
function reset() {
	for (const key of Object.keys(filters)) filters[key] = undefined;
	dates.value = [dayjs().subtract(29, 'day').format('YYYY-MM-DD'), dayjs().format('YYYY-MM-DD')];
	search();
}

const Crud = useCrud(
	{
		service: api,
		async onRefresh(params, { next }) {
			const input = { ...params, ...query() };
			const current = summaryRequests.begin();
			try {
				await next(input);
				const result = await api.summary(input);
				if (current()) summary.value = result;
			} catch (error) {
				if (current()) {
					summary.value = null;
					ElMessage.error((error as Error).message || '加载记录失败');
				}
			}
		}
	},
	app => {
		app.refresh();
		void refreshUsers();
	}
);

const Table = useTable({
	columns: [
		...(resource.deletable ? [{ type: 'selection' as const, width: 48 }] : []),
		...resource.columns.map(prop => {
			const field = resource.fields.find(field => field.prop === prop);
			return {
				prop,
				label: fieldLabel(kind, prop),
				minWidth:
					prop === 'description' || prop === 'requestId'
						? 210
						: prop.includes('Time') || prop === 'recordedAt'
							? 175
							: 120,
				showOverflowTooltip: true,
				...(field?.options
					? { dict: field.options }
					: { formatter: row => displayField(kind, prop, row) })
			};
		}),
		{
			type: 'op',
			width: resource.deletable ? 200 : 150,
			buttons: [
				'slot-detail',
				...(!resource.readonly ? ['edit'] : []),
				...(resource.deletable ? ['delete'] : [])
			]
		}
	]
});

function editor(field: Field) {
	if (field.type === 'user')
		return { name: 'el-select', props: { filterable: true }, options: users };
	if (field.type === 'select') return { name: 'el-select', options: field.options };
	if (field.type === 'number')
		return {
			name: 'el-input-number',
			props: {
				min: field.min,
				max: field.max,
				precision: field.precision,
				controlsPosition: 'right',
				style: { width: '100%' }
			}
		};
	if (field.type === 'datetime')
		return {
			name: 'el-date-picker',
			props: {
				type: 'datetime',
				valueFormat: 'YYYY-MM-DD HH:mm:ss',
				style: { width: '100%' }
			}
		};
	return {
		name: 'el-input',
		props: {
			type: field.type === 'textarea' ? 'textarea' : 'text',
			rows: 3,
			maxlength:
				field.type === 'textarea'
					? 2000
					: field.prop === 'nickName'
						? 40
						: field.prop === 'appUserId'
							? 64
							: 100,
			showWordLimit: true
		}
	};
}

const Upsert = useUpsert({
	dialog: { width: '720px' },
	items: resource.fields.map(field => ({
		prop: field.prop,
		label: field.label,
		required: field.required,
		value: field.value,
		component: editor(field)
	})),
	onOpened(data) {
		if (Upsert.value?.mode === 'add' && kind !== 'user') {
			data.recordedAt = dayjs().format('YYYY-MM-DD HH:mm:ss');
			data.userId = filters.userId || users[0]?.value;
		}
	}
});

const detailVisible = ref(false);
const detailLoading = ref(false);
const detail = ref<Record<string, any>>({});
const userSummary = ref<Record<string, any> | null>(null);
const linkedResources: { kind: 'meal' | 'smoking' | 'workout' | 'usage'; label: string }[] = [
	{ kind: 'meal', label: '查看饮食' },
	{ kind: 'smoking', label: '查看抽烟' },
	{ kind: 'workout', label: '查看运动' },
	{ kind: 'usage', label: '查看 AI 用量' }
];
const userCards = computed(() =>
	userSummary.value
		? linkedResources.map(item => ({
				label: resources[item.kind].title,
				value:
					item.kind === 'smoking'
						? `${userSummary.value!.smoking.smoked} 根自吸`
						: userSummary.value![item.kind].count
			}))
		: []
);
const bmi = computed(() =>
	detail.value.heightCm && detail.value.weightKg
		? (Number(detail.value.weightKg) / (Number(detail.value.heightCm) / 100) ** 2).toFixed(1)
		: '资料待完善'
);
function userLabel(id: number) {
	return users.find(user => user.value === id)?.label || `用户 #${id}`;
}
async function openDetail(row: Record<string, any>) {
	const current = detailRequests.begin();
	detail.value = { ...row };
	userSummary.value = null;
	detailVisible.value = true;
	detailLoading.value = true;
	try {
		const info = await api.info({ id: row.id });
		if (!current()) return;
		detail.value = { ...row, ...info };
		if (kind === 'user') {
			const result = await service.diary.overview.summary({ userId: row.id });
			if (current()) userSummary.value = result;
		}
	} catch (error) {
		if (current()) ElMessage.error((error as Error).message || '加载详情失败');
	} finally {
		if (current()) detailLoading.value = false;
	}
}
function goToRecords(target: ResourceKind) {
	detailVisible.value = false;
	router.push({ path: `/diary/${target}`, query: { userId: detail.value.id } });
}
function applyRouteUser() {
	if (route.path === `/diary/${kind}` && kind !== 'user') {
		filters.userId = route.query.userId ? Number(route.query.userId) : undefined;
		search();
	}
}
watch(() => route.query.userId, applyRouteUser);
onActivated(() => {
	applyRouteUser();
	void refreshUsers();
});
watch(
	detailVisible,
	visible => {
		if (!visible) detailRequests.cancel();
	},
	{ flush: 'sync' }
);
watch(
	() => route.fullPath,
	() => {
		detailVisible.value = false;
		detailRequests.cancel();
	}
);
onDeactivated(() => {
	detailVisible.value = false;
	detailRequests.cancel();
	summaryRequests.cancel();
	optionRequests.cancel();
	usersLoading.value = false;
});
</script>

<style scoped>
.diary-page {
	display: flex;
	flex-direction: column;
	gap: 12px;
	height: 100%;
	min-height: 0;
}
.page-heading {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: 12px;
}
h2 {
	font-size: 22px;
	margin: 0 0 8px;
}
p,
.table-note {
	color: var(--el-text-color-secondary);
	font-size: 13px;
}
.filters {
	display: flex;
	flex-wrap: wrap;
	gap: 10px;
	padding: 14px;
	border-radius: 10px;
	background: var(--el-bg-color);
}
.filters :deep(.el-select),
.filters :deep(.el-input) {
	width: 180px;
}
.filters :deep(.el-date-editor) {
	width: 280px;
	flex-grow: 0;
}
.cl-crud {
	min-height: 280px;
	flex: 1;
}
.detail-fields {
	margin: 18px 0;
}
.detail-value {
	white-space: pre-wrap;
	overflow-wrap: anywhere;
}
.record-links {
	display: flex;
	flex-wrap: wrap;
	gap: 10px;
	margin-top: 20px;
}
.record-links :deep(.el-button) {
	margin-left: 0;
}
@media (max-width: 900px) {
	.diary-page {
		height: auto;
		overflow: auto;
	}
	.page-heading {
		align-items: flex-start;
	}
	.filters :deep(.el-date-editor) {
		width: 100%;
	}
	.filters :deep(.el-select),
	.filters :deep(.el-input) {
		flex: 1 1 160px;
	}
	.table-note {
		display: none;
	}
}
</style>
