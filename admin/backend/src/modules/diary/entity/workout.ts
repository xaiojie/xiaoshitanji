import { Column, Entity } from 'typeorm';
import { DiaryRecordEntity, numeric } from './base';

@Entity('diary_workout')
export class DiaryWorkoutEntity extends DiaryRecordEntity {
  @Column({ comment: '运动类型', length: 20 })
  activityType: string;

  @Column({ comment: '运动名称', length: 100 })
  title: string;

  @Column({ comment: '运动时长秒' })
  durationSeconds: number;

  @Column({
    comment: '运动距离米',
    type: 'decimal',
    precision: 12,
    scale: 2,
    nullable: true,
    transformer: numeric,
  })
  distanceMeters: number;

  @Column({
    comment: '运动消耗 kcal',
    type: 'decimal',
    precision: 10,
    scale: 2,
    nullable: true,
    transformer: numeric,
  })
  calories: number;

  @Column({ comment: '平均心率 bpm', nullable: true })
  averageHeartRate: number;

  @Column({ comment: '最高心率 bpm', nullable: true })
  maxHeartRate: number;
}
