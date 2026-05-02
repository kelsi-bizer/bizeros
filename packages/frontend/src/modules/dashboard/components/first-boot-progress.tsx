import { useQuery } from '@tanstack/react-query';
import clsx from 'clsx';
import type React from 'react';
import { useTranslation } from 'react-i18next';

type AppStatus = 'pending' | 'installing' | 'running' | 'stopped' | 'missing' | 'error';

interface FirstBootStatus {
  complete: boolean;
  apps: Array<{ name: string; status: AppStatus }>;
}

const fetchFirstBootStatus = async (): Promise<FirstBootStatus> => {
  const res = await fetch('/api/bootstrap/first-boot-status', { credentials: 'include' });
  if (!res.ok) throw new Error(`first-boot-status ${res.status}`);
  return res.json();
};

const STATUS_LABEL_KEY: Record<AppStatus, string> = {
  pending: 'DASHBOARD_FIRSTBOOT_STATUS_PENDING',
  installing: 'DASHBOARD_FIRSTBOOT_STATUS_INSTALLING',
  running: 'DASHBOARD_FIRSTBOOT_STATUS_RUNNING',
  stopped: 'DASHBOARD_FIRSTBOOT_STATUS_STOPPED',
  missing: 'DASHBOARD_FIRSTBOOT_STATUS_MISSING',
  error: 'DASHBOARD_FIRSTBOOT_STATUS_ERROR',
};

const STATUS_BADGE_CLASS: Record<AppStatus, string> = {
  pending: 'bg-secondary',
  installing: 'bg-blue text-white',
  running: 'bg-success',
  stopped: 'bg-secondary',
  missing: 'bg-warning',
  error: 'bg-danger text-white',
};

export const FirstBootProgress: React.FC = () => {
  const { t } = useTranslation();
  const { data } = useQuery<FirstBootStatus>({
    queryKey: ['bootstrap', 'first-boot-status'],
    queryFn: fetchFirstBootStatus,
    // Poll while incomplete; stop polling once first-boot is done.
    refetchInterval: (query) => (query.state.data?.complete ? false : 5000),
  });

  if (!data || data.complete) return null;

  const total = data.apps.length;
  const installed = data.apps.filter((a) => a.status === 'running').length;

  return (
    <div className="col-12 px-1">
      <div className="card mb-2">
        <div className="card-body">
          <div className="d-flex justify-content-between align-items-baseline mb-2">
            <h3 className="card-title mb-0">{t('DASHBOARD_FIRSTBOOT_TITLE')}</h3>
            <span className="text-muted">
              {installed} / {total}
            </span>
          </div>
          <p className="text-muted mb-3">{t('DASHBOARD_FIRSTBOOT_SUBTITLE')}</p>
          <div className="progress mb-3" style={{ height: '4px' }}>
            <div
              className="progress-bar bg-primary"
              role="progressbar"
              style={{ width: `${total > 0 ? (installed / total) * 100 : 0}%` }}
              aria-valuenow={installed}
              aria-valuemin={0}
              aria-valuemax={total}
            />
          </div>
          <div className="d-flex flex-wrap gap-2">
            {data.apps.map((app) => (
              <span key={app.name} className={clsx('badge', STATUS_BADGE_CLASS[app.status])}>
                {app.name} · {t(STATUS_LABEL_KEY[app.status])}
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
