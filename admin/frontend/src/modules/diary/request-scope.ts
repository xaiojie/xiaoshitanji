/** 保留当前交互的请求，旧请求完成后由调用方跳过状态写入。 */
export function createRequestScope() {
	let version = 0;
	return {
		begin() {
			const current = ++version;
			return () => current === version;
		},
		cancel() {
			version += 1;
		}
	};
}
