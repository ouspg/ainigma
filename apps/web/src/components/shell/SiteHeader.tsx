import type { ReactNode } from "react";
import { HStack } from "@astryxdesign/core/Stack";
import { BookOpenCheck } from "lucide-react";
import type { Locale } from "../../lib/i18n";
import { localizedPath, routes } from "../../lib/routes";

interface Props {
  locale: Locale;
  children: ReactNode;
}

export default function SiteHeader({ locale, children }: Props) {
  return (
    <header className="site-header">
      <HStack className="site-header-row" gap={3} vAlign="center">
        <a className="login-wordmark" href={localizedPath(locale, routes.home.path())}>
          <HStack gap={2} vAlign="center">
            <BookOpenCheck size={19} aria-hidden="true" />
            <span>Ainigma</span>
          </HStack>
        </a>
        <span className="login-spacer" />
        {children}
      </HStack>
    </header>
  );
}
