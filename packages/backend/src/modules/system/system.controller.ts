import { Controller, Get, Res, UseGuards } from '@nestjs/common';
import type { Response } from 'express';
import { AuthGuard } from '../auth/auth.guard';
import { LoadDto, RecentErrorsDto } from './dto/system.dto';
import { SystemService } from './system.service';
import { ApiResponse } from '@nestjs/swagger';

const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;
const RECENT_ERRORS_MAX_ENTRIES = 25;

@Controller('system')
export class SystemController {
  constructor(private readonly systemService: SystemService) {}

  @UseGuards(AuthGuard)
  @Get('/load')
  @ApiResponse({ type: LoadDto })
  async systemLoad() {
    const res = await this.systemService.getSystemLoad();
    return LoadDto.parse(res, { reportOnly: true });
  }

  @UseGuards(AuthGuard)
  @Get('/recent-errors')
  @ApiResponse({ type: RecentErrorsDto })
  async recentErrors() {
    const res = await this.systemService.getRecentErrors({
      sinceMs: TWENTY_FOUR_HOURS_MS,
      maxEntries: RECENT_ERRORS_MAX_ENTRIES,
    });
    return RecentErrorsDto.parse(res, { reportOnly: true });
  }

  @Get('/certificate')
  async downloadLocalCertificate(@Res() res: Response) {
    const cert = await this.systemService.getLocalCertificate();

    res.set({
      'Content-Type': 'application/x-pem-file',
      'Content-Disposition': 'attachment; filename=cert.pem',
    });

    return res.send(cert);
  }
}
