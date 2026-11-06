import { Column, Entity } from 'typeorm';
import { DiaryRecordEntity, numeric } from './base';

@Entity('diary_ai_usage')
export class DiaryAIUsageEntity extends DiaryRecordEntity {
  @Column({ comment: '请求标识', length: 100, unique: true })
  requestId: string;

  @Column({ comment: 'AI 功能', length: 30 })
  feature: string;

  @Column({ comment: '模型', length: 80 })
  model: string;

  @Column({ comment: '请求状态', length: 16 })
  status: string;

  @Column({ comment: '输入 tokens' })
  promptTokens: number;

  @Column({ comment: '输出 tokens' })
  completionTokens: number;

  @Column({ comment: '输入缓存命中 tokens' })
  cachedTokens: number;

  @Column({ comment: '响应时延毫秒' })
  latencyMs: number;

  @Column({
    comment: '预估费用元',
    type: 'decimal',
    precision: 12,
    scale: 6,
    transformer: numeric,
  })
  estimatedCostYuan: number;

  @Column({ comment: '失败原因', type: 'text', nullable: true })
  errorMessage: string;
}
