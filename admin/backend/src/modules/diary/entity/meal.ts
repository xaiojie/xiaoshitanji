import { Column, Entity } from 'typeorm';
import { DiaryRecordEntity, numeric } from './base';

@Entity('diary_meal')
export class DiaryMealEntity extends DiaryRecordEntity {
  @Column({ comment: '餐次', length: 16 })
  mealType: string;

  @Column({ comment: '食物描述', type: 'text' })
  description: string;

  @Column({ comment: '记录来源', length: 16 })
  source: string;

  @Column({
    comment: '热量 kcal',
    type: 'decimal',
    precision: 10,
    scale: 2,
    transformer: numeric,
  })
  calories: number;

  @Column({
    comment: '蛋白质 g',
    type: 'decimal',
    precision: 10,
    scale: 2,
    transformer: numeric,
  })
  protein: number;

  @Column({
    comment: '碳水 g',
    type: 'decimal',
    precision: 10,
    scale: 2,
    transformer: numeric,
  })
  carbs: number;

  @Column({
    comment: '脂肪 g',
    type: 'decimal',
    precision: 10,
    scale: 2,
    transformer: numeric,
  })
  fat: number;

  @Column({ comment: '分析摘要', type: 'text', nullable: true })
  analysisSummary: string;
}
