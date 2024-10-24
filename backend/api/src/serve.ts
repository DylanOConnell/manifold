import * as admin from 'firebase-admin'
import { getLocalEnv, initAdmin } from 'shared/init-admin'
import { loadSecretsToEnv, getServiceAccountCredentials } from 'common/secrets'
import { LOCAL_DEV, log } from 'shared/utils'
import { METRIC_WRITER } from 'shared/monitoring/metric-writer'
import { initCaches } from 'shared/init-caches'
import { listen as webSocketListen } from 'shared/websockets/server'

log('Api server starting up...')

if (LOCAL_DEV) {
  initAdmin()
} else {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT
  admin.initializeApp({
    projectId,
    storageBucket: `${projectId}.appspot.com`,
  })
}

METRIC_WRITER.start()

import { app } from './app'
import { readApp } from './read-app'

const credentials = LOCAL_DEV
  ? getServiceAccountCredentials(getLocalEnv())
  : undefined

const DB_RESPONSE_TIMEOUT = 30_000

const startupProcess = async () => {
  await loadSecretsToEnv(credentials)
  log('Secrets loaded.')

  log('Starting server <> postgres timeout')
  const timeoutId = setTimeout(() => {
    log.error(
      `Server hasn't heard from postgres in ${DB_RESPONSE_TIMEOUT}ms. Exiting.`
    )
    throw new Error('Server startup timed out')
  }, DB_RESPONSE_TIMEOUT)

  await initCaches(timeoutId)
  log('Caches loaded.')

  const PORT = process.env.PORT ?? 8088
  const IS_READ_ONLY = process.env.IS_READ_ONLY === 'true'

  if (IS_READ_ONLY) {
    readApp.listen(PORT, () => {
      log.info(`Serving read-only API on port ${PORT}.`)
    })
  } else {
    const httpServer = app.listen(PORT, () => {
      log.info(`Serving main API on port ${PORT}.`)
    })

    webSocketListen(httpServer, '/ws')
  }

  log('Server started successfully')
}
startupProcess()
