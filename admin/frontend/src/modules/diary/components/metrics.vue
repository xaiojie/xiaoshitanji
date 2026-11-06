<template>
	<div class="diary-metrics">
		<div v-for="card in cards" :key="card.label" class="metric">
			<span>{{ card.label }}</span
			><strong>{{ card.value }}</strong
			><small v-if="card.note">{{ card.note }}</small>
		</div>
	</div>
</template>
<script setup lang="ts">
defineProps<{ cards: { label: string; value: string | number; note?: string }[] }>();
</script>
<style scoped>
.diary-metrics {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
	gap: 12px;
}
.metric {
	padding: 16px 20px;
	border: 1px solid var(--el-border-color-light);
	border-radius: 12px;
	background: var(--el-bg-color);
	display: flex;
	flex-direction: column;
	gap: 8px;
}
.metric span,
.metric small {
	color: var(--el-text-color-secondary);
}
.metric strong {
	font-size: 24px;
	font-variant-numeric: tabular-nums;
}
</style>
