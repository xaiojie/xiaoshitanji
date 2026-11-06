<template>
	<el-scrollbar>
		<main class="admin-welcome">
			<section class="intro">
				<img src="/logo.png" alt="小食痰记奶蛙" />
				<div>
					<el-tag type="success" effect="light">本地开发环境</el-tag>
					<h1>小食痰记管理后台</h1>
					<p>把饮食、生活与运动，慢慢整理成更好的日常。</p>
				</div>
			</section>

			<el-alert title="后台基础框架已接入，App 业务数据接入待开发" type="info" :closable="false" show-icon>
				本页展示后台搭建进度。用户管理、数据字典等菜单当前管理此框架的独立开发库。
			</el-alert>

			<section class="cards">
				<el-card shadow="never">
					<template #header><h2>基础管理</h2></template>
					<p>管理员、角色、菜单与权限</p>
					<p>操作日志、参数配置与数据字典</p>
					<el-tag type="success">已可使用</el-tag>
				</el-card>
				<el-card shadow="never">
					<template #header><h2>独立开发数据库</h2></template>
					<p>服务器 MySQL 8.4，通过 SSH 隧道连接</p>
					<p>与 App 现有服务及数据库独立</p>
					<el-tag>本地管理</el-tag>
				</el-card>
				<el-card shadow="never">
					<template #header><h2>下一步接入</h2></template>
					<p>App 用户、饮食与抽烟记录</p>
					<p>运动记录、AI 用量与分析管理</p>
					<el-tag type="warning">待开发</el-tag>
				</el-card>
			</section>
		</main>
	</el-scrollbar>
</template>

<script lang="ts" setup>
defineOptions({ name: 'home' });
</script>

<style scoped lang="scss">
.admin-welcome {
	padding: 24px;
	max-width: 1280px;
	margin: 0 auto;

	.intro {
		display: flex;
		align-items: center;
		gap: 24px;
		padding: 28px;
		margin-bottom: 24px;
		border-radius: 16px;
		background: var(--el-bg-color);

		img { width: 100px; height: 100px; border-radius: 24px; }
		h1 { margin: 14px 0 10px; font-size: 28px; }
		p { color: var(--el-text-color-secondary); line-height: 1.7; }
	}

	.cards {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 20px;
		margin-top: 24px;
		h2 { font-size: 17px; margin: 0; }
		p { color: var(--el-text-color-secondary); margin-bottom: 16px; line-height: 1.7; }
	}
}

@media (max-width: 900px) {
	.admin-welcome {
		padding: 12px;
		.cards { grid-template-columns: 1fr; }
		.intro { padding: 20px; gap: 16px; }
		.intro img { width: 64px; height: 64px; border-radius: 16px; }
		.intro h1 { font-size: 22px; }
	}
}
</style>
