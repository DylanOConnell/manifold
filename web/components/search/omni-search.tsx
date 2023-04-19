import { Combobox } from '@headlessui/react'
import { SparklesIcon, UsersIcon } from '@heroicons/react/solid'
import clsx from 'clsx'
import { Contract } from 'common/contract'
import { useRouter } from 'next/router'
import { ReactNode, useEffect, useRef, useState } from 'react'
import { useMemberGroupIds } from 'web/hooks/use-group'
import { useUser } from 'web/hooks/use-user'
import { useYourRecentContracts } from 'web/hooks/use-your-daily-changed-contracts'
import { searchContract } from 'web/lib/supabase/contracts'
import { db } from 'web/lib/supabase/db'
import { SearchGroupInfo, searchGroups } from 'web/lib/supabase/groups'
import { UserSearchResult, searchUsers } from 'web/lib/supabase/users'
import { ContractStatusLabel } from '../contract/contracts-list-entry'
import { JoinOrLeaveGroupButton } from '../groups/groups-button'
import { Avatar } from '../widgets/avatar'
import { LoadingIndicator } from '../widgets/loading-indicator'
import { PageData, defaultPages, searchPages } from './query-pages'
import { useSearchContext } from './search-context'
import { uniqBy } from 'lodash'
import { ExternalLinkIcon } from '@heroicons/react/outline'
import { SiteLink } from 'web/components/widgets/site-link'

export interface Option {
  id: string
  slug: string
}

export const OmniSearch = (props: {
  className?: string
  inputClassName?: string
  query: string
  setQuery: (query: string) => void
  onSelect?: () => void
}) => {
  const { className, inputClassName, query, setQuery, onSelect } = props

  const { setOpen } = useSearchContext() ?? {}
  const router = useRouter()

  return (
    <Combobox
      as="div"
      onChange={({ slug }: Option) => {
        router.push(slug)
        setOpen?.(false)
        onSelect?.()
      }}
      className={clsx('bg-canvas-0 relative flex flex-col', className)}
    >
      {({ activeOption }) => (
        <>
          <Combobox.Input
            autoFocus
            value={query}
            onKeyDown={(e: any) => {
              if (e.key === 'Escape') setOpen?.(false)
              if (e.key === 'Enter' && !activeOption) {
                router.push(marketSearchSlug(query))
                setOpen?.(false)
                onSelect?.()
              }
            }}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search markets, users, & groups"
            enterKeyHint="search"
            className={clsx(
              'border-ink-100 focus:border-ink-100 placeholder:text-ink-400 bg-canvas-0 text-ink-1000 border-0 border-b py-4 px-6 text-xl ring-0 ring-transparent focus:ring-transparent',
              inputClassName
            )}
          />
          <Combobox.Options
            static
            className="text-ink-700 flex flex-col overflow-y-auto px-2"
          >
            {query ? <Results query={query} /> : <DefaultResults />}
          </Combobox.Options>
        </>
      )}
    </Combobox>
  )
}

const DefaultResults = () => {
  const user = useUser()
  const markets = useYourRecentContracts(db, user?.id) ?? []

  return (
    <>
      <PageResults pages={defaultPages} />
      <MarketResults markets={markets} />
      <div className="mx-2 my-2 text-xs">
        <SparklesIcon className="text-primary-500 mr-1 inline h-4 w-4 align-text-bottom" />
        Start with <Key>%</Key> for markets, <Key>@</Key> for users, or{' '}
        <Key>#</Key> for groups
      </div>
    </>
  )
}

const Key = (props: { children: ReactNode }) => (
  <code className="bg-ink-300 mx-0.5 rounded p-0.5">{props.children}</code>
)

const Results = (props: { query: string }) => {
  const { query } = props

  const prefix = query.match(/^(%|#|@)/) ? query.charAt(0) : ''
  const search = prefix ? query.slice(1) : query

  const userHitLimit = !prefix ? 2 : prefix === '@' ? 25 : 0
  const groupHitLimit = !prefix ? 2 : prefix === '#' ? 25 : 0
  const marketHitLimit = !prefix ? 20 : prefix === '%' ? 25 : 0

  const [{ pageHits, userHits, groupHits, marketHits }, setSearchResults] =
    useState({
      pageHits: [] as PageData[],
      userHits: [] as UserSearchResult[],
      groupHits: [] as SearchGroupInfo[],
      marketHits: [] as Contract[],
    })
  const [loading, setLoading] = useState(false)

  // Use nonce to make sure only latest result gets used.
  const nonce = useRef(0)

  useEffect(() => {
    nonce.current++
    const thisNonce = nonce.current
    setLoading(true)

    Promise.all([
      searchUsers(search, userHitLimit),
      searchGroups(search, groupHitLimit),
      searchContract({
        query: search,
        filter: 'all',
        sort: 'most-popular',
        limit: marketHitLimit,
      }),
    ]).then(([userHits, groupHits, { data: marketHits }]) => {
      if (thisNonce === nonce.current) {
        const pageHits = prefix ? [] : searchPages(search, 2)
        const uniqueMarketHits = uniqBy<Contract>(marketHits, 'id')
        setSearchResults({
          pageHits,
          userHits,
          groupHits,
          marketHits: uniqueMarketHits,
        })
        setLoading(false)
      }
    })
  }, [search, groupHitLimit, marketHitLimit, userHitLimit, prefix])

  if (loading) {
    return (
      <LoadingIndicator
        className="absolute right-6 bottom-1/2 translate-y-1/2"
        spinnerClassName="!border-ink-300 !border-r-transparent"
      />
    )
  }

  if (
    !pageHits.length &&
    !userHits.length &&
    !groupHits.length &&
    !marketHits.length
  ) {
    return <div className="my-6 text-center">no results x.x</div>
  }

  return (
    <>
      <PageResults pages={pageHits} />
      <UserResults users={userHits} search={search} />

      <GroupResults groups={groupHits} search={search} />
      <MarketResults markets={marketHits} search={search} />
    </>
  )
}

const SectionTitle = (props: { children: ReactNode; link?: string }) => {
  const { children, link } = props
  return (
    <h2 className="text-ink-500 mt-2 mb-1 px-1">
      <SiteLink href={link}>
        {children}
        {link && (
          <ExternalLinkIcon className="ml-1 inline h-4 w-4 align-middle" />
        )}
      </SiteLink>
    </h2>
  )
}

const ResultOption = (props: { value: Option; children: ReactNode }) => {
  const { value, children } = props

  return (
    <Combobox.Option value={value}>
      {({ active }) => (
        <div
          // modify click event before it bubbles higher to trick Combobox into thinking this is a normal click event
          onClick={(e) => {
            e.defaultPrevented = false
          }}
        >
          <a
            className={clsx(
              'mb-1 block cursor-pointer select-none rounded-md px-3 py-2',
              active && 'bg-primary-100 text-primary-800'
            )}
            onClick={(e) => {
              if (e.ctrlKey || e.shiftKey || e.metaKey || e.button === 1) {
                // if openned in new tab/window don't switch this page
                e.stopPropagation()
              } else {
                // if click normally, don't hard refresh. Let Combobox onChange handle routing instead of this <a>
                e.preventDefault()
              }
              return true
            }}
            href={value.slug}
          >
            {children}
          </a>
        </div>
      )}
    </Combobox.Option>
  )
}

const MarketResults = (props: { markets: Contract[]; search?: string }) => {
  const markets = props.markets
  if (!markets.length) return null

  return (
    <>
      <SectionTitle link={marketSearchSlug(props.search ?? '')}>
        Markets
      </SectionTitle>
      {props.markets.map((market) => (
        <ResultOption
          value={{
            id: market.id,
            slug: `/${market.creatorUsername}/${market.slug}`,
          }}
        >
          <div className="flex gap-2">
            <span className="grow">{market.question}</span>
            <span className="font-bold">
              <ContractStatusLabel contract={market} />
            </span>
            <Avatar
              size="xs"
              username={market.creatorUsername}
              avatarUrl={market.creatorAvatarUrl}
            />
          </div>
        </ResultOption>
      ))}
    </>
  )
}

const UserResults = (props: { users: UserSearchResult[]; search?: string }) => {
  if (!props.users.length) return null
  return (
    <>
      <SectionTitle
        link={`/users?search=${encodeURIComponent(props.search ?? '')}`}
      >
        Users
      </SectionTitle>
      {props.users.map(({ id, name, username, avatarUrl }) => (
        <ResultOption value={{ id, slug: `/${username}` }}>
          <div className="flex items-center gap-2">
            <Avatar
              username={username}
              avatarUrl={avatarUrl}
              size="xs"
              noLink
            />
            {name}
            {username !== name && (
              <span className="text-ink-400">@{username}</span>
            )}
          </div>
        </ResultOption>
      ))}
    </>
  )
}

const GroupResults = (props: {
  groups: SearchGroupInfo[]
  search?: string
}) => {
  const me = useUser()
  const myGroups = useMemberGroupIds(me) || []
  const { search } = props
  if (!props.groups.length) return null
  return (
    <>
      <SectionTitle link={`/groups?search=${encodeURIComponent(search ?? '')}`}>
        Groups
      </SectionTitle>
      {props.groups.map((group) => (
        <ResultOption value={{ id: group.id, slug: `/group/${group.slug}` }}>
          <div className="flex items-center gap-3">
            <span className="grow">{group.name}</span>
            <span className="flex items-center">
              <UsersIcon className="mr-1 h-4 w-4" />
              {group.totalMembers}
            </span>
            <div onClick={(e) => e.stopPropagation()}>
              <JoinOrLeaveGroupButton
                group={group}
                user={me}
                isMember={myGroups.includes(group.id)}
                className="w-[80px] !px-0 !py-1"
              />
            </div>
          </div>
        </ResultOption>
      ))}
    </>
  )
}

const PageResults = (props: { pages: PageData[] }) => {
  if (!props.pages.length) return null
  return (
    <>
      <SectionTitle>Pages</SectionTitle>
      {props.pages.map(({ label, slug }) => (
        <ResultOption value={{ id: label, slug }}>{label}</ResultOption>
      ))}
    </>
  )
}

const marketSearchSlug = (query: string) =>
  `/markets?s=relevance&f=all&q=${encodeURIComponent(query)}`
