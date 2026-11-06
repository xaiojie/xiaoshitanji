import { Body, Get, Inject, Post } from '@midwayjs/core';
import { BaseController, CoolController } from '@cool-midway/core';
import { DiaryAppUserEntity } from '../../entity/user';
import { DiaryManagementService } from '../../service/management';
import { diaryQuery } from '../query';

@CoolController({
  api: ['page', 'info', 'list'],
  entity: DiaryAppUserEntity,
  pageQueryOp: diaryQuery('user'),
  listQueryOp: diaryQuery('user'),
})
export class DiaryUserController extends BaseController {
  @Inject()
  diaryManagementService: DiaryManagementService;

  @Post('/add', { summary: '新增示例记录' })
  async createRecord(@Body() input) {
    return this.ok(
      await this.diaryManagementService.save('user', input, false)
    );
  }

  @Post('/update', { summary: '更新示例记录' })
  async updateRecord(@Body() input) {
    return this.ok(await this.diaryManagementService.save('user', input, true));
  }

  @Get('/options', { summary: 'App 用户选项' })
  async options() {
    return this.ok(
      await this.diaryManagementService.users.find({
        select: ['id', 'nickName', 'appUserId', 'status'],
        order: { id: 'DESC' },
      })
    );
  }

  @Post('/summary', { summary: '当前筛选汇总' })
  async summary(@Body() input) {
    return this.ok(await this.diaryManagementService.summary(input, 'user'));
  }
}
