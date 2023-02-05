import dayjs from 'dayjs'
import { BETTOR, User } from 'common/user'
import { useUser, useUserById } from 'web/hooks/use-user'
import { Row } from 'web/components/layout/row'
import { Avatar, EmptyAvatar } from 'web/components/widgets/avatar'
import { formatMoney } from 'common/util/format'
import { RelativeTimestamp } from 'web/components/relative-timestamp'
import React from 'react'
import { LiquidityProvision } from 'common/liquidity-provision'
import { UserLink } from 'web/components/widgets/user-link'

export function FeedLiquidity(props: {
  className?: string
  liquidity: LiquidityProvision
}) {
  const { liquidity } = props
  const { userId, createdTime } = liquidity

  const isBeforeJune2022 = dayjs(createdTime).isBefore('2022-06-01')
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const bettor = isBeforeJune2022 ? undefined : useUserById(userId) ?? undefined

  const user = useUser()
  const isSelf = user?.id === userId

  return (
    <div className="-ml-2 rounded-full bg-gradient-to-r from-pink-300 via-purple-300 to-indigo-300 p-2">
      <Row className="items-stretch gap-2 rounded-full bg-white/50">
        {isSelf ? (
          <Avatar avatarUrl={user.avatarUrl} username={user.username} />
        ) : bettor ? (
          <Avatar avatarUrl={bettor.avatarUrl} username={bettor.username} />
        ) : (
          <div className="relative px-1">
            <EmptyAvatar />
          </div>
        )}
        <LiquidityStatusText
          liquidity={liquidity}
          isSelf={isSelf}
          bettor={bettor}
        />
      </Row>
    </div>
  )
}

function LiquidityStatusText(props: {
  liquidity: LiquidityProvision
  isSelf: boolean
  bettor?: User
}) {
  const { liquidity, bettor, isSelf } = props
  const { amount, createdTime } = liquidity

  // TODO: Withdrawn liquidity will never be shown, since liquidity amounts currently are zeroed out upon withdrawal.
  const bought = amount >= 0 ? 'added' : 'withdrew'
  const money = formatMoney(Math.abs(amount))

  return (
    <div className="flex items-center gap-1 pr-4 text-sm text-gray-500">
      {bettor ? (
        <UserLink name={bettor.name} username={bettor.username} />
      ) : (
        <span>{isSelf ? 'You' : `A ${BETTOR}`}</span>
      )}
      {bought} a subsidy of <span className="text-violet-800">{money}</span>
      <RelativeTimestamp time={createdTime} className="text-white" />
    </div>
  )
}
