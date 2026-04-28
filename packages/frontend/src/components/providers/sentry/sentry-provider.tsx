import { useUserContext } from '@/context/user-context';
import * as Sentry from '@sentry/react';
import { type PropsWithChildren, useEffect } from 'react';

const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN;

export const SentryProvider = ({ children }: PropsWithChildren) => {
  const { allowErrorMonitoring, version } = useUserContext();

  useEffect(() => {
    if (allowErrorMonitoring && SENTRY_DSN) {
      console.info('Error monitoring enabled, version:', version.current);
      Sentry.init({
        release: version.current,
        environment: 'production',
        tracesSampleRate: 1.0,
        dsn: SENTRY_DSN,
        integrations: [Sentry.browserTracingIntegration()],
        initialScope: {
          tags: { version: version.current },
        },
      });
    }
  }, [allowErrorMonitoring, version.current]);

  return children;
};
