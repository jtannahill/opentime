// www.lulls.app served a full duplicate of the site. Send it to the apex with a
// permanent redirect, keeping the path and query.
export async function onRequest(context) {
  const url = new URL(context.request.url);
  if (url.hostname === "www.lulls.app") {
    url.hostname = "lulls.app";
    return Response.redirect(url.toString(), 301);
  }
  return context.next();
}
