/** 后台审计保留业务参数，凭据字段在写入数据库前脱敏。 */
export function redactLogParams(value: any): any {
  if (Array.isArray(value)) return value.map(redactLogParams);
  if (value === null || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    /(password|token|secret|apikey|authorization)$/i.test(key.replace(/[_-]/g, ''))
      ? '[REDACTED]'
      : redactLogParams(item),
  ]));
}
