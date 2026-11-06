import { type ModuleConfig } from '/@/cool';

export default (): ModuleConfig => ({
	components: Object.values(import.meta.glob('./components/**/*.vue'))
});
