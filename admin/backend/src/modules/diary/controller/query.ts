import { CoolCommException, QueryOp } from '@cool-midway/core';
import { DiaryAppUserEntity } from '../entity/user';
import { DiaryKind, resourceFilters } from '../dto/record';

export function diaryQuery(kind: DiaryKind): QueryOp {
  return {
    select:
      kind === 'user'
        ? ['a.*']
        : ['a.*', 'u.nickName AS userName', 'u.appUserId AS appUserId'],
    join:
      kind === 'user'
        ? []
        : [
            {
              entity: DiaryAppUserEntity,
              alias: 'u',
              condition: 'a.userId = u.id',
              type: 'leftJoin',
            },
          ],
    addOrderBy:
      kind === 'user' ? { id: 'DESC' } : { recordedAt: 'DESC', id: 'DESC' },
    where: async ctx => {
      try {
        return resourceFilters(kind, { ...ctx.query, ...ctx.request.body });
      } catch (error) {
        throw new CoolCommException(error.message);
      }
    },
  };
}
