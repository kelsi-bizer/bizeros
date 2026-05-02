import { Module } from '@nestjs/common';
import { AppLifecycleModule } from '@/modules/app-lifecycle/app-lifecycle.module';
import { AppStoreModule } from '@/modules/app-stores/app-store.module';
import { AppsModule } from '@/modules/apps/apps.module';
import { MarketplaceModule } from '@/modules/marketplace/marketplace.module';
import { BootstrapController } from './bootstrap.controller';
import { FirstBootService } from './first-boot.service';

@Module({
  imports: [AppLifecycleModule, AppStoreModule, MarketplaceModule, AppsModule],
  controllers: [BootstrapController],
  providers: [FirstBootService],
  exports: [FirstBootService],
})
export class BootstrapModule {}
