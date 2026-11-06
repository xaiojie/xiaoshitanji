import { Body, Inject, Post } from '@midwayjs/core';
import { BaseController, CoolController } from '@cool-midway/core';
import { DiaryMealEntity } from '../../entity/meal';
import { DiaryManagementService } from '../../service/management';
import { diaryQuery } from '../query';

@CoolController({
  api: ['page', 'info', 'delete'],
  entity: DiaryMealEntity,
  pageQueryOp: diaryQuery('meal'),
  listQueryOp: diaryQuery('meal'),
})
export class DiaryMealController extends BaseController {
  @Inject()
  diaryManagementService: DiaryManagementService;

  @Post('/add', { summary: '新增示例记录' })
  async createRecord(@Body() input) {
    return this.ok(
      await this.diaryManagementService.save('meal', input, false)
    );
  }

  @Post('/update', { summary: '更新示例记录' })
  async updateRecord(@Body() input) {
    return this.ok(await this.diaryManagementService.save('meal', input, true));
  }

  @Post('/summary', { summary: '当前筛选汇总' })
  async summary(@Body() input) {
    return this.ok(await this.diaryManagementService.summary(input, 'meal'));
  }
}
