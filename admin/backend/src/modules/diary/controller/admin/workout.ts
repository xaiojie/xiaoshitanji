import { Body, Inject, Post } from '@midwayjs/core';
import { BaseController, CoolController } from '@cool-midway/core';
import { DiaryWorkoutEntity } from '../../entity/workout';
import { DiaryManagementService } from '../../service/management';
import { diaryQuery } from '../query';

@CoolController({
  api: ['page', 'info', 'delete'],
  entity: DiaryWorkoutEntity,
  pageQueryOp: diaryQuery('workout'),
  listQueryOp: diaryQuery('workout'),
})
export class DiaryWorkoutController extends BaseController {
  @Inject()
  diaryManagementService: DiaryManagementService;

  @Post('/add', { summary: '新增示例记录' })
  async createRecord(@Body() input) {
    return this.ok(
      await this.diaryManagementService.save('workout', input, false)
    );
  }

  @Post('/update', { summary: '更新示例记录' })
  async updateRecord(@Body() input) {
    return this.ok(
      await this.diaryManagementService.save('workout', input, true)
    );
  }

  @Post('/summary', { summary: '当前筛选汇总' })
  async summary(@Body() input) {
    return this.ok(await this.diaryManagementService.summary(input, 'workout'));
  }
}
