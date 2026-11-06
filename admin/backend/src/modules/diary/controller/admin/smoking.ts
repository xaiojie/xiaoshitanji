import { Body, Inject, Post } from '@midwayjs/core';
import { BaseController, CoolController } from '@cool-midway/core';
import { DiarySmokingEntity } from '../../entity/smoking';
import { DiaryManagementService } from '../../service/management';
import { diaryQuery } from '../query';

@CoolController({
  api: ['page', 'info', 'delete'],
  entity: DiarySmokingEntity,
  pageQueryOp: diaryQuery('smoking'),
  listQueryOp: diaryQuery('smoking'),
})
export class DiarySmokingController extends BaseController {
  @Inject()
  diaryManagementService: DiaryManagementService;

  @Post('/add', { summary: '新增示例记录' })
  async createRecord(@Body() input) {
    return this.ok(
      await this.diaryManagementService.save('smoking', input, false)
    );
  }

  @Post('/update', { summary: '更新示例记录' })
  async updateRecord(@Body() input) {
    return this.ok(
      await this.diaryManagementService.save('smoking', input, true)
    );
  }

  @Post('/summary', { summary: '当前筛选汇总' })
  async summary(@Body() input) {
    return this.ok(await this.diaryManagementService.summary(input, 'smoking'));
  }
}
