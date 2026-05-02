import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiResponse } from '@nestjs/swagger';
import { AuthGuard } from '../auth/auth.guard';
import { FirstBootStatusDto } from './dto/bootstrap.dto';
import { FirstBootService } from './first-boot.service';

@Controller('bootstrap')
export class BootstrapController {
  constructor(private readonly firstBootService: FirstBootService) {}

  @UseGuards(AuthGuard)
  @Get('first-boot-status')
  @ApiResponse({ type: FirstBootStatusDto })
  async firstBootStatus() {
    const status = await this.firstBootService.getStatus();
    return FirstBootStatusDto.parse(status, { reportOnly: true });
  }
}
