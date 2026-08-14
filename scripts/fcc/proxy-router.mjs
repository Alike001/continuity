import http from 'node:http'

const port = Number(process.env.FCC_ROUTER_PORT ?? 7676)
const primaryPort = Number(process.env.PRIMARY_PROXY_PORT ?? 6674)
const recoveryPort = Number(process.env.RECOVERY_PROXY_PORT ?? 6684)

function route(pathname) {
  if (pathname === '/primary' || pathname.startsWith('/primary/')) return { prefix: '/primary', port: primaryPort }
  if (pathname === '/recovery' || pathname.startsWith('/recovery/')) return { prefix: '/recovery', port: recoveryPort }
  return null
}

const hopByHopHeaders = new Set(['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade'])
function endToEndHeaders(headers) {
  return Object.fromEntries(Object.entries(headers).filter(([name]) => !hopByHopHeaders.has(name.toLowerCase())))
}

const server = http.createServer((request, response) => {
  const incoming = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`)
  const target = route(incoming.pathname)
  if (!target) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
    response.end('Use /primary or /recovery.\n')
    return
  }

  const rewrittenPath = incoming.pathname.slice(target.prefix.length) || '/'
  const proxyRequest = http.request({
    hostname: '127.0.0.1',
    port: target.port,
    method: request.method,
    path: `${rewrittenPath}${incoming.search}`,
    headers: { ...endToEndHeaders(request.headers), host: `127.0.0.1:${target.port}` },
  }, (upstream) => {
    response.writeHead(upstream.statusCode ?? 502, endToEndHeaders(upstream.headers))
    upstream.pipe(response)
  })

  proxyRequest.on('error', (error) => {
    if (!response.headersSent) response.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
    response.end(`FCC proxy unavailable: ${error.code ?? error.message}\n`)
  })
  request.pipe(proxyRequest)
})

server.listen(port, '127.0.0.1', () => {
  console.log(`FCC proxy router listening on http://127.0.0.1:${port}`)
  console.log(`primary /primary -> 127.0.0.1:${primaryPort}`)
  console.log(`recovery /recovery -> 127.0.0.1:${recoveryPort}`)
})

process.on('SIGINT', () => server.close(() => process.exit(0)))
