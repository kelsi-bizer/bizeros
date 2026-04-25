import { acknowledgeWelcomeMutation } from '@/api-client/@tanstack/react-query.gen';
import { Button } from '@/components/ui/Button';
import { Switch } from '@/components/ui/Switch';
import { getLogo } from '@/lib/theme/theme';
import { IconBrandDiscord, IconBrandGithub } from '@tabler/icons-react';
import { useMutation } from '@tanstack/react-query';
import { useState } from 'react';

type Props = {
  allowErrorMonitoring: boolean;
};

export const Welcome = ({ allowErrorMonitoring }: Props) => {
  const [errorMonitoring, setErrorMonitoring] = useState(allowErrorMonitoring);

  const openLink = (url: string) => {
    window.open(url, '_blank', 'noopener noreferrer');
  };

  const acknowledge = useMutation({
    ...acknowledgeWelcomeMutation(),
  });

  return (
    <div className="page page-center">
      <div className="container container-tight py-4">
        <div className="text-center mb-4">
          <img alt="BizerOS logo" src={getLogo(true)} height={50} width={50} style={{ maxWidth: '100%', height: 'auto' }} />
        </div>
        <div className="card card-md">
          <div className="card-body">
            <h2 className="h2 text-center mb-4">Welcome to BizerOS</h2>
            <p className="text-center mb-4">
              BizerOS is a one-click, self-hosted business platform for running your stack on your own hardware. We&apos;re standing on the shoulders
              of{' '}
              <a target="_blank" rel="noreferrer" href="https://github.com/runtipi/runtipi">
                Runtipi
              </a>
              , the open-source homeserver this project is built on. If BizerOS helps your business, consider{' '}
              <a target="_blank" rel="noreferrer" href="https://github.com/kelsi-bizer/bizeros-dashboard">
                contributing to the codebase
              </a>{' '}
              or{' '}
              <a target="_blank" href="https://github.com/runtipi/runtipi?sponsor=1" rel="noreferrer">
                supporting Runtipi upstream
              </a>
              .
              <br />
              <br />
              You can also help us by enabling the opt-in anonymous error reporting feature below. It helps us identify and fix bugs faster.
            </p>
            <div className="d-flex flex-column align-items-center">
              <Switch checked={errorMonitoring} onCheckedChange={setErrorMonitoring} label="Enable error reporting" />
              <Button
                intent="primary"
                className="mt-3"
                onClick={() => acknowledge.mutate({ body: { allowErrorMonitoring: errorMonitoring } })}
                loading={acknowledge.isPending || acknowledge.isPending}
                disabled={acknowledge.isPending || acknowledge.isPending}
              >
                Save and enter
              </Button>
            </div>
            <div className="hr-text">Join the community</div>
            <div className="row justify-content-center gap-2">
              <Button onClick={() => openLink('https://github.com/kelsi-bizer/bizeros-dashboard/discussions')}>
                <IconBrandGithub /> Github
              </Button>
              <Button onClick={() => openLink('https://discord.gg/WGW7YP7E5j')}>
                <IconBrandDiscord />
                Discord
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
