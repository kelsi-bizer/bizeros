import { useQuery } from '@tanstack/react-query';
import { IconAlertTriangle, IconCheck } from '@tabler/icons-react';
import type React from 'react';
import { useTranslation } from 'react-i18next';

interface RecentErrorsResponse {
  total: number;
  entries: Array<{ timestamp: string; level: string; message: string }>;
}

const fetchRecentErrors = async (): Promise<RecentErrorsResponse> => {
  const res = await fetch('/api/system/recent-errors', { credentials: 'include' });
  if (!res.ok) throw new Error(`recent-errors ${res.status}`);
  return res.json();
};

const formatTimestamp = (iso: string) => {
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
};

export const RecentErrors: React.FC = () => {
  const { t } = useTranslation();
  const { data } = useQuery<RecentErrorsResponse>({
    queryKey: ['system', 'recent-errors'],
    queryFn: fetchRecentErrors,
    refetchInterval: 60_000,
  });

  if (!data) return null;

  const { total, entries } = data;
  const isClean = total === 0;

  return (
    <div className="col-12 px-1">
      <div className="card mb-2">
        <div className="card-body">
          <div className="d-flex align-items-center gap-2 mb-1">
            {isClean ? <IconCheck size={20} className="text-success" /> : <IconAlertTriangle size={20} className="text-danger" />}
            <h3 className="card-title mb-0">{t('DASHBOARD_RECENT_ERRORS_TITLE')}</h3>
          </div>
          <p className="text-muted mb-3">
            {isClean ? t('DASHBOARD_RECENT_ERRORS_SUBTITLE_NONE') : t('DASHBOARD_RECENT_ERRORS_SUBTITLE_SOME', { count: total })}
          </p>
          {!isClean && (
            <>
              <div className="list-group list-group-flush">
                {entries.map((e) => (
                  <div key={`${e.timestamp}-${e.message}`} className="list-group-item px-0 py-2">
                    <div className="d-flex justify-content-between gap-3">
                      <code className="small text-danger flex-grow-1" style={{ wordBreak: 'break-word' }}>
                        {e.message}
                      </code>
                      <span className="text-muted small flex-shrink-0">{formatTimestamp(e.timestamp)}</span>
                    </div>
                  </div>
                ))}
              </div>
              {total > entries.length && (
                <p className="text-muted small mt-2 mb-0">{t('DASHBOARD_RECENT_ERRORS_TRUNCATED', { shown: entries.length, total })}</p>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};
