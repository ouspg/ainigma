import { Button } from "@astryxdesign/core/Button";
import { HStack } from "@astryxdesign/core/Stack";
import { BookOpenCheck, Palette } from "lucide-react";
import { appearanceThemes, colorModes } from "../../lib/appearance";
import { getMessages, localizedPath, type Locale } from "../../lib/i18n";
import LocaleSwitcher from "../islands/LocaleSwitcher";
import AppearanceThemeIcon from "../theme/AppearanceThemeIcon";
import ColorModeIcon from "../theme/ColorModeIcon";

interface Props {
  currentPath: string;
  locale: Locale;
  showSignIn?: boolean;
}

export default function PublicHeader({ currentPath, locale, showSignIn = false }: Props) {
  const messages = getMessages(locale);

  return (
    <header className="public-header">
      <HStack className="public-header-row" gap={3} vAlign="center">
        <a className="login-wordmark" href={localizedPath(locale, "/")}>
          <HStack gap={2} vAlign="center">
            <BookOpenCheck size={19} aria-hidden="true" />
            <span>Ainigma</span>
          </HStack>
        </a>
        <span className="login-spacer" />
        {showSignIn ? (
          <Button
            href={localizedPath(locale, "/login/")}
            label={messages.publicHome.signIn}
            size="sm"
            variant="primary"
          />
        ) : null}
        <LocaleSwitcher locale={locale} path={currentPath} />
        <details className="public-theme-menu">
          <summary
            aria-label={messages.appearance.label}
            className="public-theme-menu-trigger"
            title={messages.appearance.label}
          >
            <Palette size={17} aria-hidden="true" />
            <span className="visually-hidden">{messages.appearance.label}</span>
          </summary>
          <ul className="public-theme-menu-list">
            <li className="public-theme-menu-heading">{messages.appearance.theme}</li>
            {appearanceThemes.map((theme) => (
              <li key={theme}>
                <button
                  aria-pressed={theme === "academic"}
                  className="public-theme-menu-option"
                  data-appearance-theme-choice={theme}
                  type="button"
                >
                  <AppearanceThemeIcon theme={theme} />
                  <span>{messages.appearance.themeNames[theme]}</span>
                </button>
              </li>
            ))}
            <li className="public-theme-menu-divider" aria-hidden="true" />
            <li className="public-theme-menu-heading">{messages.appearance.colorMode}</li>
            {colorModes.map((mode) => (
              <li key={mode}>
                <button
                  aria-pressed={mode === "system"}
                  className="public-theme-menu-option"
                  data-color-mode-choice={mode}
                  type="button"
                >
                  <ColorModeIcon mode={mode} />
                  <span>{messages.appearance[mode]}</span>
                </button>
              </li>
            ))}
          </ul>
        </details>
      </HStack>
    </header>
  );
}
