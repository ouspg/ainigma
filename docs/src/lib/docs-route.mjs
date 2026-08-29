/** Generate the stable content collection ID for a documentation source path. */
export function docsEntryId(entry) {
  return entry
    .replace(/\.mdx?$/i, "")
    .split(/[\\/]/)
    .map((segment) => segment.replace(/_/g, "-").toLowerCase())
    .join("/");
}

/** Generate the public route ID, where an index source maps to its directory. */
export function docsRouteId(entry) {
  return docsEntryId(entry).replace(/(?:^|\/)index$/, "");
}
