import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { Injectable } from '@nestjs/common';
import type { AppUrn } from '@runtipi/common/types';
import { createAppUrn } from '@/common/helpers/app-helpers';
import { ConfigurationService } from '@/core/config/configuration.service';
import { LoggerService } from '@/core/logger/logger.service';
import { AppLifecycleService } from '@/modules/app-lifecycle/app-lifecycle.service';
import { AppStoreService } from '@/modules/app-stores/app-store.service';
import { MarketplaceService } from '@/modules/marketplace/marketplace.service';

const CURATED_APPS = ['authentik', 'bizeros-dash', 'bizeros-chat', 'miles', 'nextcloud', 'invoice-ninja', 'infisical'];

const FLAG_FILENAME = 'bizeros-firstboot-complete';
const READY_TIMEOUT_MS = 5 * 60 * 1000;
const READY_POLL_INTERVAL_MS = 5 * 1000;

@Injectable()
export class FirstBootService {
  constructor(
    private readonly logger: LoggerService,
    private readonly configuration: ConfigurationService,
    private readonly appStoreService: AppStoreService,
    private readonly marketplaceService: MarketplaceService,
    private readonly appLifecycleService: AppLifecycleService,
  ) {}

  private get flagPath() {
    const { directories } = this.configuration.getConfig();
    return path.join(directories.dataDir, 'state', FLAG_FILENAME);
  }

  public async runIfNeeded(): Promise<void> {
    if (this.alreadyRan()) {
      this.logger.debug('[FirstBoot] flag present, skipping curated install');
      return;
    }

    this.logger.info('[FirstBoot] starting curated app install');

    void (async () => {
      try {
        const storeSlug = await this.resolveDefaultStoreSlug();
        if (!storeSlug) {
          this.logger.warn('[FirstBoot] no enabled app store found, aborting');
          return;
        }

        const ready = await this.waitForCuratedAppsReady(storeSlug);
        if (!ready) {
          this.logger.warn('[FirstBoot] timed out waiting for curated apps in marketplace, aborting (will retry next boot)');
          return;
        }

        for (const appName of CURATED_APPS) {
          await this.installApp(appName, storeSlug);
        }

        this.markComplete();
        this.logger.info('[FirstBoot] curated install complete');
      } catch (err) {
        this.logger.error('[FirstBoot] unexpected failure', err);
      }
    })();
  }

  private alreadyRan(): boolean {
    return fs.existsSync(this.flagPath);
  }

  private markComplete(): void {
    fs.mkdirSync(path.dirname(this.flagPath), { recursive: true });
    fs.writeFileSync(this.flagPath, new Date().toISOString());
  }

  private async resolveDefaultStoreSlug(): Promise<string | null> {
    const stores = await this.appStoreService.getEnabledAppStores();
    return stores[0]?.slug ?? null;
  }

  private async waitForCuratedAppsReady(storeSlug: string): Promise<boolean> {
    const deadline = Date.now() + READY_TIMEOUT_MS;
    const expectedUrns = new Set(CURATED_APPS.map((name) => createAppUrn(name, storeSlug)));

    while (Date.now() < deadline) {
      const available = new Set(await this.marketplaceService.getAvailableAppUrns());
      const missing = [...expectedUrns].filter((urn) => !available.has(urn));
      if (missing.length === 0) {
        return true;
      }
      this.logger.debug(`[FirstBoot] waiting for ${missing.length} curated apps in marketplace`);
      await new Promise((resolve) => setTimeout(resolve, READY_POLL_INTERVAL_MS));
    }
    return false;
  }

  private async installApp(appName: string, storeSlug: string): Promise<void> {
    const appUrn = createAppUrn(appName, storeSlug);
    try {
      this.logger.info(`[FirstBoot] installing curated app: ${appUrn}`);
      const form = await this.buildPlaceholderForm(appUrn);
      const { requestId } = await this.appLifecycleService.installApp({ appUrn, form });
      this.logger.info(`[FirstBoot] install dispatched for ${appUrn} (requestId=${requestId})`);
    } catch (err) {
      this.logger.error(`[FirstBoot] error installing ${appUrn}`, err);
    }
  }

  /**
   * Generate placeholder values for any required form field that has no default
   * and isn't a 'random' type (which the install pipeline auto-generates).
   * Lets first-boot install apps that would otherwise fail validation. Customers
   * reconfigure via each app's settings dialog after first login.
   */
  private async buildPlaceholderForm(appUrn: AppUrn): Promise<Record<string, string | number | boolean>> {
    const form: Record<string, string | number | boolean> = {};

    let appInfo: Awaited<ReturnType<MarketplaceService['getAppInfoFromAppStore']>>;
    try {
      appInfo = await this.marketplaceService.getAppInfoFromAppStore(appUrn);
    } catch (err) {
      this.logger.warn(`[FirstBoot] could not load app info for ${appUrn}, installing with empty form: ${(err as Error).message}`);
      return form;
    }

    const fields = appInfo?.form_fields ?? [];
    if (fields.length === 0) return form;

    const { domain, internalIp } = this.configuration.getConfig().userSettings;
    const safeDomain = domain || 'bizeros.local';
    const fallbackEmail = `admin@${safeDomain}`;

    for (const field of fields) {
      if (field.type === 'random') continue;
      if (field.default !== undefined) continue;
      if (!field.required) continue;

      switch (field.type) {
        case 'email':
          form[field.env_variable] = fallbackEmail;
          break;
        case 'password':
          form[field.env_variable] = randomBytes(16).toString('hex');
          break;
        case 'url':
          form[field.env_variable] = `https://${safeDomain}`;
          break;
        case 'fqdn':
        case 'fqdnip':
          form[field.env_variable] = safeDomain;
          break;
        case 'ip':
          form[field.env_variable] = internalIp || '127.0.0.1';
          break;
        case 'number':
          form[field.env_variable] = field.min ?? 1;
          break;
        case 'boolean':
          form[field.env_variable] = false;
          break;
        default:
          form[field.env_variable] = 'bizeros';
          break;
      }
    }

    return form;
  }
}
