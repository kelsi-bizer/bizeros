import { ConfigurationService } from '@/core/config/configuration.service';
import { FilesystemService } from '@/core/filesystem/filesystem.service';
import { LoggerService } from '@/core/logger/logger.service';
import { Injectable } from '@nestjs/common';
import si from 'systeminformation';

@Injectable()
export class SystemService {
  constructor(
    private readonly logger: LoggerService,
    private readonly config: ConfigurationService,
    private readonly filesystem: FilesystemService,
  ) {}

  public async getSystemLoad() {
    const { currentLoad } = await si.currentLoad();

    const memResult = { total: 0, used: 0, available: 0 };

    try {
      const memInfo = await this.filesystem.readTextFile('/host/proc/meminfo');

      memResult.total = Number(memInfo?.toString().match(/MemTotal:\s+(\d+)/)?.[1] ?? 0) * 1024;
      memResult.available = Number(memInfo?.toString().match(/MemAvailable:\s+(\d+)/)?.[1] ?? 0) * 1024;
      memResult.used = memResult.total - memResult.available;
    } catch (e) {
      this.logger.error(`Unable to read /host/proc/meminfo: ${e}`);
    }

    const [disk0] = await si.fsSize();

    const disk = disk0 ?? { available: 0, size: 0 };
    const diskFree = Math.round(disk.available / 1024 / 1024 / 1024);
    const diskSize = Math.round(disk.size / 1024 / 1024 / 1024);
    const diskUsed = diskSize - diskFree;
    const percentUsed = Math.round((diskUsed / diskSize) * 100);

    const memoryTotal = Math.round(Number(memResult.total) / 1024 / 1024 / 1024);
    const memoryFree = Math.round(Number(memResult.available) / 1024 / 1024 / 1024);
    const percentUsedMemory = Math.round(((memoryTotal - memoryFree) / memoryTotal) * 100);

    return {
      diskUsed: diskUsed || 0,
      diskSize: diskSize || 0,
      percentUsed: percentUsed || 0,
      cpuLoad: currentLoad || 0,
      memoryTotal: memoryTotal || 0,
      percentUsedMemory: percentUsedMemory || 0,
    };
  }

  public async getLocalCertificate() {
    const { dataDir } = this.config.get('directories');
    const filePath = `${dataDir}/traefik/tls/cert.pem`;

    if (await this.filesystem.pathExists(filePath)) {
      const file = await this.filesystem.readTextFile(filePath);
      return file;
    }
  }

  /**
   * Read the tail of error.log and return the entries from the last `sinceMs`
   * milliseconds, capped at `maxEntries`. Used by the dashboard's "Recent
   * errors" card so the operator doesn't have to SSH in to see backend errors.
   */
  public async getRecentErrors(params: { sinceMs: number; maxEntries: number }) {
    const { sinceMs, maxEntries } = params;
    const { dataDir } = this.config.get('directories');
    const filePath = `${dataDir}/logs/error.log`;
    const cutoff = Date.now() - sinceMs;

    if (!(await this.filesystem.pathExists(filePath))) {
      return { entries: [], total: 0 };
    }

    const content = (await this.filesystem.readTextFile(filePath)) ?? '';
    const lines = content.split('\n').filter(Boolean);

    // Winston file format from logger.service.ts: `${timestamp} - ${level} > ${message}`
    // Timestamps are ISO 8601 (winston default), e.g. 2026-05-04T02:48:21.123Z.
    const lineRegex = /^(?<timestamp>\S+)\s+-\s+(?<level>\w+)\s+>\s+(?<message>.*)$/;

    const parsed: Array<{ timestamp: string; level: string; message: string; ts: number }> = [];
    for (const line of lines) {
      const match = lineRegex.exec(line);
      const groups = match?.groups;
      if (!groups || !groups.timestamp || !groups.level || !groups.message) continue;
      const ts = Date.parse(groups.timestamp);
      if (Number.isNaN(ts) || ts < cutoff) continue;
      parsed.push({
        timestamp: groups.timestamp,
        level: groups.level,
        message: groups.message,
        ts,
      });
    }

    // Newest first, cap to maxEntries.
    parsed.sort((a, b) => b.ts - a.ts);
    const entries = parsed.slice(0, maxEntries).map(({ ts: _ts, ...rest }) => rest);
    return { entries, total: parsed.length };
  }
}
