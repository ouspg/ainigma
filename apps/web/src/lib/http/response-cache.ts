export const PRIVATE_NO_STORE_CACHE_CONTROL = "private, no-store";

/** Prevents personalized responses from being stored by browsers or shared caches. */
export function markPrivateNoStore(response: Response): Response {
  response.headers.set("Cache-Control", PRIVATE_NO_STORE_CACHE_CONTROL);
  return response;
}
