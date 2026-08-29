// Nimbus's Icon.astro is API-compatible with astro-icon's named Icon export.
// Keep this adapter local so registry components can remain unchanged without
// adding a second icon runtime to the docs bundle.
import Icon from "@cloudflare/nimbus-docs/components/Icon.astro";

export { Icon };
