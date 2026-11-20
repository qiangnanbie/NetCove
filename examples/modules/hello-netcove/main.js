// Hello NetCove — 示例模块
// 演示：声明式出网、日志、存储、TMDB 桥、返回资源列表给播放器

async function onDiscover(context) {
  netcove.log('hello: discover for library', context.libraryName)

  const cached = await netcove.storage.get('lastResult')
  if (cached) netcove.log('hello: cached', cached)

  const response = await netcove.fetch('https://api.netcove.app/api/metadata/search?q=inception', {
    method: 'GET',
    headers: { 'accept': 'application/json' }
  })

  if (response.status !== 200) {
    netcove.log('hello: backend returned', response.status)
    return []
  }

  const payload = JSON.parse(response.body)
  const items = (payload.results || []).map(function (item) {
    return {
      id: String(item.id),
      title: item.title,
      year: item.year,
      kind: item.kind || 'movie'
    }
  })

  await netcove.storage.set('lastResult', String(items.length))
  return items
}

async function onPlayback(input) {
  netcove.log('hello: resolve playback for', input.itemID)
  return { url: input.fallbackURL }
}

globalThis.onDiscover = onDiscover
globalThis.onPlayback = onPlayback
