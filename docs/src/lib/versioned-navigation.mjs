import { withDocsBase } from "../../config/versions.mjs";

/**
 * Prefix the href-bearing shape returned by Nimbus while retaining its
 * framework-owned metadata. Groups are recursive and may also have a landing.
 *
 * @template {Record<string, any>} T
 * @param {T[]} items
 * @param {string} base
 * @returns {T[]}
 */
export function prefixNavigationItems(items, base) {
  return items.map((item) => ({
    ...item,
    ...(typeof item.href === "string" ? { href: withDocsBase(item.href, base) } : {}),
    ...(typeof item.indexHref === "string"
      ? { indexHref: withDocsBase(item.indexHref, base) }
      : {}),
    ...(Array.isArray(item.children)
      ? { children: prefixNavigationItems(item.children, base) }
      : {}),
  }));
}

/** Prefix optional previous/next links returned by Nimbus. */
export function prefixPrevNext(prevNext, base) {
  return {
    prev: prevNext.prev
      ? { ...prevNext.prev, href: withDocsBase(prevNext.prev.href, base) }
      : undefined,
    next: prevNext.next
      ? { ...prevNext.next, href: withDocsBase(prevNext.next.href, base) }
      : undefined,
  };
}
