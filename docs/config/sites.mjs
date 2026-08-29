/**
 * Top-level documentation sites. Keep this registry shared by the Nimbus
 * sidebar config and the header so labels, paths, and active state cannot
 * drift apart.
 */
export const docsSites = Object.freeze([
  Object.freeze({ slug: "web", label: "Web" }),
  Object.freeze({ slug: "supabase", label: "Supabase" }),
  Object.freeze({ slug: "workers", label: "Workers" }),
  Object.freeze({ slug: "infrastructure", label: "Infrastructure" }),
]);
