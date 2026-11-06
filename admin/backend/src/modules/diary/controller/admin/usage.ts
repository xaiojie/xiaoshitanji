import { Body, Inject, Post } from '@midwayjs/core';
import { BaseController, CoolController } from '@cool-midway/core';
import { DiaryAIUsageEntity } from '../../entity/usage';
import { DiaryManagementService } from '../../service/management';
import { diaryQuery } from '../query';

@CoolController({
  api: ['page', 'info'],
  entity: DiaryAIUsageEntity,
  pageQueryOp: diaryQuery('usage'),
  listQueryOp: diaryQuery('usage'),
})
export class DiaryUsageController extends BaseController {
  @Inject()
  diaryManagementService: DiaryManagementService;

  @Post('/summary', { summary: '当前筛选汇总' })
  async summary(@Body() input) {
    return this.ok(await this.diaryManagementService.summary(input, 'usage'));
  }
}
