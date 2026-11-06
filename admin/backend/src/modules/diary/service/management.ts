import { Provide } from '@midwayjs/core';
import { CoolCommException } from '@cool-midway/core';
import { InjectEntityModel } from '@midwayjs/typeorm';
import { Repository } from 'typeorm';
import * as moment from 'moment';
import { DiaryAppUserEntity } from '../entity/user';
import { DiaryMealEntity } from '../entity/meal';
import { DiarySmokingEntity } from '../entity/smoking';
import { DiaryWorkoutEntity } from '../entity/workout';
import { DiaryAIUsageEntity } from '../entity/usage';
import {
  DiaryKind,
  normalizeRecord,
  resourceFilters,
  tokenTotal,
} from '../dto/record';

@Provide()
export class DiaryManagementService {
  @InjectEntityModel(DiaryAppUserEntity)
  users: Repository<DiaryAppUserEntity>;
  @InjectEntityModel(DiaryMealEntity)
  meals: Repository<DiaryMealEntity>;
  @InjectEntityModel(DiarySmokingEntity)
  smoking: Repository<DiarySmokingEntity>;
  @InjectEntityModel(DiaryWorkoutEntity)
  workouts: Repository<DiaryWorkoutEntity>;
  @InjectEntityModel(DiaryAIUsageEntity)
  usage: Repository<DiaryAIUsageEntity>;

  repository(kind: DiaryKind): Repository<any> {
    return {
      user: this.users,
      meal: this.meals,
      smoking: this.smoking,
      workout: this.workouts,
      usage: this.usage,
    }[kind];
  }

  async save(kind: DiaryKind, input: Record<string, any>, update: boolean) {
    const repository = this.repository(kind);
    let existing;
    if (update) {
      if (!Number.isSafeInteger(Number(input.id)) || Number(input.id) < 1)
        throw new CoolCommException('记录 ID 无效');
      existing = await repository.findOneBy({ id: Number(input.id) });
      if (!existing) throw new CoolCommException('记录已不存在，请刷新列表');
    }
    let data;
    try {
      data = normalizeRecord(kind, { ...existing, ...input });
    } catch (error) {
      throw new CoolCommException(error.message);
    }
    if (kind !== 'user' && !(await this.users.existsBy({ id: data.userId })))
      throw new CoolCommException('关联 App 用户不存在');
    const now = moment().format('YYYY-MM-DD HH:mm:ss');
    try {
      return await repository.save({
        ...existing,
        ...data,
        updateTime: now,
        ...(!update ? { createTime: now } : {}),
      });
    } catch (error) {
      if (error.code === 'ER_DUP_ENTRY')
        throw new CoolCommException('App 用户标识或请求标识已经存在');
      throw error;
    }
  }

  query(kind: DiaryKind, input: Record<string, any>) {
    const query = this.repository(kind).createQueryBuilder('a');
    if (kind !== 'user')
      query.leftJoin(DiaryAppUserEntity, 'u', 'u.id = a.userId');
    try {
      for (const [sql, params] of resourceFilters(kind, input))
        query.andWhere(sql, params);
    } catch (error) {
      throw new CoolCommException(error.message);
    }
    return query;
  }

  async summary(input: Record<string, any>, kind?: DiaryKind) {
    const queries: Record<DiaryKind, () => Promise<any>> = {
      user: () =>
        this.query('user', input)
          .select('COUNT(*)', 'total')
          .addSelect("SUM(a.status='active')", 'active')
          .getRawOne(),
      meal: () =>
        this.query('meal', input)
          .select('COUNT(*)', 'count')
          .addSelect('SUM(a.calories)', 'calories')
          .addSelect('SUM(a.protein)', 'protein')
          .addSelect('SUM(a.carbs)', 'carbs')
          .addSelect('SUM(a.fat)', 'fat')
          .getRawOne(),
      smoking: () =>
        this.query('smoking', input)
          .select("SUM(IF(a.action='smoked',a.count,0))", 'smoked')
          .addSelect("SUM(IF(a.action='gifted',a.count,0))", 'gifted')
          .addSelect(
            "SUM(IF(a.action='smoked',a.count*a.nicotinePerCigarette,0))",
            'nicotineMG'
          )
          .addSelect(
            "SUM(IF(a.action='smoked' AND a.nicotinePerCigarette IS NULL,a.count,0))",
            'unknownNicotineCount'
          )
          .addSelect(
            "SUM(IF(a.action='smoked',a.count*a.packPrice/20,0))",
            'costYuan'
          )
          .addSelect(
            "SUM(IF(a.action='smoked' AND a.packPrice IS NULL,a.count,0))",
            'unpricedCount'
          )
          .getRawOne(),
      workout: () =>
        this.query('workout', input)
          .select('COUNT(*)', 'count')
          .addSelect('SUM(a.durationSeconds)', 'durationSeconds')
          .addSelect('SUM(a.distanceMeters)', 'distanceMeters')
          .addSelect('SUM(a.calories)', 'calories')
          .addSelect('AVG(a.averageHeartRate)', 'averageHeartRate')
          .addSelect('COUNT(a.averageHeartRate)', 'heartRateCount')
          .getRawOne(),
      usage: () =>
        this.query('usage', input)
          .select('COUNT(*)', 'count')
          .addSelect("SUM(a.status='success')", 'success')
          .addSelect("SUM(a.status='failed')", 'failed')
          .addSelect('SUM(a.promptTokens)', 'promptTokens')
          .addSelect('SUM(a.completionTokens)', 'completionTokens')
          .addSelect('SUM(a.cachedTokens)', 'cachedTokens')
          .addSelect('SUM(a.estimatedCostYuan)', 'estimatedCostYuan')
          .addSelect('AVG(a.latencyMs)', 'latencyMs')
          .getRawOne(),
    };
    // 单资源接口仅执行该资源的查询，业务总览使用独立权限读取完整聚合。
    const selected: DiaryKind[] = kind
      ? [kind]
      : ['user', 'meal', 'smoking', 'workout', 'usage'];
    const rows = await Promise.all(
      selected.map(async resource => {
        const row = await queries[resource]();
        const numeric = Object.fromEntries(
          Object.entries(row).map(([key, value]) => [
            key,
            value === null && key === 'averageHeartRate'
              ? null
              : Number(value || 0),
          ])
        );
        return [resource, numeric];
      })
    );
    const result: Record<string, any> = Object.fromEntries(rows);
    if (result.usage) result.usage.totalTokens = tokenTotal(result.usage);
    return result;
  }

  async trend(input: Record<string, any>) {
    const [meals, smoking, workouts, usage] = await Promise.all([
      this.query('meal', input)
        .select('LEFT(a.recordedAt,10)', 'date')
        .addSelect('SUM(a.calories)', 'calories')
        .groupBy('date')
        .getRawMany(),
      this.query('smoking', input)
        .select('LEFT(a.recordedAt,10)', 'date')
        .addSelect("SUM(IF(a.action='smoked',a.count,0))", 'smoked')
        .groupBy('date')
        .getRawMany(),
      this.query('workout', input)
        .select('LEFT(a.recordedAt,10)', 'date')
        .addSelect('SUM(a.durationSeconds)/60', 'minutes')
        .groupBy('date')
        .getRawMany(),
      this.query('usage', input)
        .select('LEFT(a.recordedAt,10)', 'date')
        .addSelect('SUM(a.promptTokens+a.completionTokens)', 'tokens')
        .groupBy('date')
        .getRawMany(),
    ]);
    const days = new Map<string, any>();
    for (const rows of [meals, smoking, workouts, usage]) {
      for (const row of rows) {
        const day = days.get(row.date) || {
          date: row.date,
          calories: 0,
          smoked: 0,
          minutes: 0,
          tokens: 0,
        };
        for (const [key, value] of Object.entries(row))
          if (key !== 'date') day[key] = Number(value);
        days.set(row.date, day);
      }
    }
    return [...days.values()].sort((a, b) => a.date.localeCompare(b.date));
  }
}
