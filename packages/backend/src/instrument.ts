import * as Sentry from '@sentry/nestjs';
import { cleanseErrorData } from './common/helpers/error-helpers';

const { NODE_ENV, TIPI_VERSION, SENTRY_DSN } = process.env;

Sentry.init({
  release: TIPI_VERSION,
  enabled: Boolean(SENTRY_DSN),
  tracesSampleRate: 1.0,
  dsn: SENTRY_DSN,
  environment: NODE_ENV,
  beforeSend: cleanseErrorData,
  includeLocalVariables: true,
  integrations: [Sentry.extraErrorDataIntegration(), Sentry.nestIntegration()],
  initialScope: {
    tags: { version: TIPI_VERSION },
  },
});
