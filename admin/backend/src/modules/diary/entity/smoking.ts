import { Column, Entity } from 'typeorm';
import { DiaryRecordEntity, numeric } from './base';

@Entity('diary_smoking')
export class DiarySmokingEntity extends DiaryRecordEntity {
  @Column({ comment: '自吸或赠出', length: 16 })
  action: string;

  @Column({ comment: '数量' })
  count: number;

  @Column({ comment: '香烟名称', length: 100 })
  packName: string;

  @Column({
    comment: '元每包20根',
    type: 'decimal',
    precision: 10,
    scale: 2,
    nullable: true,
    transformer: numeric,
  })
  packPrice: number;

  @Column({
    comment: '包装尼古丁标注 mg每根',
    type: 'decimal',
    precision: 6,
    scale: 3,
    nullable: true,
    transformer: numeric,
  })
  nicotinePerCigarette: number;
}
