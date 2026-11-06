import { Column, Index } from 'typeorm';
import { BaseEntity } from '../../base/entity/base';

export const numeric = {
  to: value => value,
  from: value => (value === null ? null : Number(value)),
};

export abstract class DiaryEntity extends BaseEntity {
  @Column({ comment: '示例数据', default: true })
  isDemo: boolean;

  @Column({ comment: '备注', type: 'text', nullable: true })
  notes: string;
}

export abstract class DiaryRecordEntity extends DiaryEntity {
  @Index()
  @Column({ comment: '关联 App 用户 ID' })
  userId: number;

  @Index()
  @Column({ comment: '北京时间', length: 19 })
  recordedAt: string;
}
