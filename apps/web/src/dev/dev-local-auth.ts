import {
  localAuthPersonas,
  type LocalAuthPersona,
  type LocalAuthPersonaOption,
} from "./dev-local-auth.generated";

export { localAuthPersonas, type LocalAuthPersona, type LocalAuthPersonaOption };

export function isLocalAuthEnabled(): boolean {
  return import.meta.env.DEV && import.meta.env.PUBLIC_AUTH_MODE === "local";
}

export function isLocalAuthPersona(value: string | null): value is LocalAuthPersona {
  return localAuthPersonas.some((persona) => persona.key === value);
}
