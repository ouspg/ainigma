import { Monitor, Moon, Sun } from "lucide-react";
import type { ColorMode } from "../../lib/appearance";

interface Props {
  mode: ColorMode;
  size?: number;
}

export default function ColorModeIcon({ mode, size = 16 }: Props) {
  const Icon = mode === "system" ? Monitor : mode === "light" ? Sun : Moon;
  return <Icon size={size} aria-hidden="true" />;
}
