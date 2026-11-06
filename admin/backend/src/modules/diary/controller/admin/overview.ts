import { Body, Inject, Post } from '@midwayjs/core';
import { BaseController, CoolController } from '@cool-midway/core';
import { DiaryManagementService } from '../../service/management';

@CoolController()
export class DiaryOverviewController extends BaseController {
  @Inject()
  diaryManagementService: DiaryManagementService;

  @Post('/summary', { summary: '业务汇总' })
  async summary(@Body() input) {
    return this.ok(await this.diaryManagementService.summary(input));
  }

  @Post('/trend', { summary: '业务每日趋势' })
  async trend(@Body() input) {
    return this.ok(await this.diaryManagementService.trend(input));
  }
}
