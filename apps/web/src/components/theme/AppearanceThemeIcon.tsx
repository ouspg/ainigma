import { BookOpen, SquareTerminal } from "lucide-react";
import type { AppearanceTheme } from "../../lib/appearance";

interface Props {
  theme: AppearanceTheme;
  size?: number;
}

export default function AppearanceThemeIcon({ theme, size = 16 }: Props) {
  const Icon = theme === "academic" ? BookOpen : SquareTerminal;
  return <Icon size={size} aria-hidden="true" />;
}
