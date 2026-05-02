import { type } from 'arktype';
import { createArkDto } from 'nestjs-arktype';

const firstBootAppStatusSchema = type({
  name: 'string',
  // 'pending' = no DB row yet (not installed at all)
  // 'installing' / 'running' / 'stopped' / 'missing' / 'error' = mapped from app.status
  status: '"pending" | "installing" | "running" | "stopped" | "missing" | "error"',
});

const firstBootStatusSchema = type({
  complete: 'boolean',
  apps: firstBootAppStatusSchema.array(),
});

export class FirstBootStatusDto extends createArkDto(firstBootStatusSchema, { name: 'FirstBootStatusDto' }) {}
