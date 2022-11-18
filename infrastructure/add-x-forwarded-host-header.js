function handler(event) {
  var request = event.request;
  var host = request.headers.host;

  if (!host) {
    return request;
  }

  request.headers["x-forwarded-host"] = { value: request.headers.host.value };

  return request;
}
