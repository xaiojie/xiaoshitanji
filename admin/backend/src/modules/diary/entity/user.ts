import { Column, Entity } from 'typeorm';
import { DiaryEntity, numeric } from './base';

@Entity('diary_app_user')
export class DiaryAppUserEntity extends DiaryEntity {
  @Column({ comment: 'App 用户标识', length: 64, unique: true })
  appUserId: string;

  @Column({ comment: '昵称', length: 40 })
  nickName: string;

  @Column({ comment: '性别', length: 16, default: 'unknown' })
  gender: string;

  @Column({ comment: '年龄', nullable: true })
  age: number;

  @Column({
    comment: '身高 cm',
    type: 'decimal',
    precision: 6,
    scale: 2,
    nullable: true,
    transformer: numeric,
  })
  heightCm: number;

  @Column({
    comment: '体重 kg',
    type: 'decimal',
    precision: 6,
    scale: 2,
    nullable: true,
    transformer: numeric,
  })
  weightKg: number;

  @Column({
    comment: '目标体重 kg',
    type: 'decimal',
    precision: 6,
    scale: 2,
    nullable: true,
    transformer: numeric,
  })
  targetWeightKg: number;

  @Column({ comment: '目标', length: 24, default: 'health' })
  goal: string;

  @Column({ comment: '抽烟情况', length: 20, default: 'unknown' })
  smokingStatus: string;

  @Column({ comment: '账号状态', length: 16, default: 'active' })
  status: string;
}
