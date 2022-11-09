import { APIError, newEndpoint, validate } from 'functions/src/api'
import { z } from 'zod'
import { getPrivateUser, getUser, isProd, log } from './utils'
import { sendThankYouEmail } from 'functions/src/emails'
import { track } from 'functions/src/analytics'
import * as admin from 'firebase-admin'
import { IapTransaction, PurchaseData } from 'common/iap'
import {
  DEV_HOUSE_LIQUIDITY_PROVIDER_ID,
  HOUSE_LIQUIDITY_PROVIDER_ID,
} from 'common/antes'
import { ManaPurchaseTxn } from 'common/txn'
import { runTxn } from 'functions/src/transact'

const bodySchema = z.object({
  receipt: z.string(),
  userId: z.string(),
})

const PRODUCTS_TO_AMOUNTS: { [key: string]: number } = {
  mana_1000: 1000,
  mana_2500: 2500,
  mana_10000: 10000,
}

const IAP_TYPES_PROCESSED = 'apple'

export const validateiap = newEndpoint({}, async (req, auth) => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const iap = require('@flat/in-app-purchase')
  const { receipt, userId } = validate(bodySchema, req.body)

  if (auth.uid !== userId)
    throw new APIError(400, 'auth id and user id do not match')

  iap.config({
    /* Configurations for Apple */
    // appleExcludeOldTransactions: true, // if you want to exclude old transaction, set this to true. Default is false
    // applePassword: 'abcd.....', // this comes from iTunes Connect (You need this to valiate subscriptions)
    /* Configurations all platforms */
    test: !isProd(), // For Apple and Googl Play to force Sandbox validation only
    verbose: true, // Output debug logs to stdout stream
  })
  await iap.setup().catch((error: any) => {
    log('Error setting up iap', error)
    throw new APIError(400, 'iap setup failed')
  })

  const validatedData = await iap.validate(receipt).catch((error: any) => {
    log('error on validate data:', error)
    throw new APIError(400, 'iap receipt validation failed')
  })

  log('validated data')
  // validatedData: the actual content of the validated receipt
  // validatedData also contains the original receipt
  const options = {
    ignoreCanceled: true, // Apple ONLY (for now...): purchaseData will NOT contain cancceled items
    ignoreExpired: true, // purchaseData will NOT contain exipired subscription items
  }
  // validatedData contains sandbox: true/false for Apple and Amazon
  const purchaseData = iap.getPurchaseData(
    validatedData,
    options
  ) as PurchaseData[]
  log('purchase data:', purchaseData)

  const { transactionId, productId, purchaseDateMs, quantity } = purchaseData[0]

  const query = await firestore
    .collection('iaps')
    .where('transactionId', '==', transactionId)
    .get()

  if (!query.empty) {
    log('transactionId', transactionId, 'already processed')
    throw new APIError(400, 'iap transaction already processed')
  }

  const payout = PRODUCTS_TO_AMOUNTS[productId] * quantity
  const revenue = (payout / 100) * 0.2 + payout / 100 - 0.01

  log('payout', payout)

  const iapTransRef = await firestore.collection('iaps').doc()
  const iapTransaction: IapTransaction = {
    userId,
    manaQuantity: payout, // save as number
    createdTime: Date.now(),
    purchaseTime: purchaseDateMs,
    transactionId,
    quantity,
    receipt,
    productId,
    type: IAP_TYPES_PROCESSED,
    revenue,
    id: iapTransRef.id,
  }
  log('iap transaction:', iapTransaction)
  await firestore.collection('iaps').doc(iapTransRef.id).set(iapTransaction)

  const manaPurchaseTxn = {
    fromId: isProd()
      ? HOUSE_LIQUIDITY_PROVIDER_ID
      : DEV_HOUSE_LIQUIDITY_PROVIDER_ID,
    fromType: 'BANK',
    toId: userId,
    toType: 'USER',
    amount: payout,
    token: 'M$',
    category: 'MANA_PURCHASE',
    data: {
      iapTransactionId: iapTransRef.id,
      type: IAP_TYPES_PROCESSED,
    },
    description: `Deposit M$${payout} from BANK for mana purchase`,
  } as Omit<ManaPurchaseTxn, 'id' | 'createdTime'>

  await firestore.runTransaction(async (transaction) => {
    const result = await runTxn(transaction, manaPurchaseTxn)
    if (result.status == 'error') {
      throw new APIError(500, result.message ?? 'An unknown error occurred.')
    }
    return result
  })

  log('user', userId, 'paid M$', payout)

  const user = await getUser(userId)
  if (!user) throw new APIError(400, 'user not found')

  const privateUser = await getPrivateUser(userId)
  if (!privateUser) throw new APIError(400, 'private user not found')

  await sendThankYouEmail(user, privateUser)
  log('iap revenue', revenue)
  await track(
    userId,
    'M$ purchase',
    { amount: payout, transactionId },
    { revenue }
  )
  return { success: true }
})

const firestore = admin.firestore()
