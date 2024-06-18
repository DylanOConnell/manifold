import {
  createSupabaseDirectClient,
  SupabaseDirectClient,
} from 'shared/supabase/init'
import { APIError } from 'common//api/utils'
import { getPrivateUser } from 'shared/utils'
import { isAdminId, isModId } from 'common/envs/constants'
import { convertTopic, TOPIC_IDS_YOU_CANT_FOLLOW } from 'common/supabase/groups'
import { updatePrivateUser } from './users'
import { FieldVal } from './utils'

export const getMemberGroupSlugs = async (
  userId: string,
  pg: SupabaseDirectClient
): Promise<string[]> => {
  return await pg.map(
    `select slug from groups where id in (
        select group_id from group_members where member_id = $1
    )`,
    [userId],
    (r) => r.slug as string
  )
}
export const getMemberTopics = async (
  userId: string,
  pg: SupabaseDirectClient
) => {
  return await pg.map(
    `select id,slug,name,importance_score,privacy_status,total_members from groups where id in (
        select group_id from group_members where member_id = $1
    ) order by importance_score desc`,
    [userId],
    convertTopic
  )
}
export const getGroupIdFromSlug = async (
  slug: string,
  pg: SupabaseDirectClient
): Promise<string> => {
  return await pg.one(
    `select id from groups where slug = $1`,
    [slug],
    (r) => r.id as string
  )
}

export async function addUserToTopic(
  groupId: string,
  userId: string,
  myId: string
) {
  if (TOPIC_IDS_YOU_CANT_FOLLOW.includes(groupId)) {
    throw new APIError(403, 'You can not follow this topic.')
  }
  const pg = createSupabaseDirectClient()

  // the old firebase code did this as a transaction to prevent race conditions
  // and idk if that's still necessary but I did it here too
  return pg.tx(async (tx) => {
    const requester = await tx.oneOrNone(
      `select gm.role, u.data
      from group_members gm join users u
      on gm.member_id = u.id
      where u.id = $1
      and gm.group_id = $2`,
      [myId, groupId]
    )

    const newMemberExists = await tx.oneOrNone(
      'select 1 from group_members where member_id = $1 and group_id = $2',
      [userId, groupId]
    )

    const group = await tx.oneOrNone('select * from groups where id = $1', [
      groupId,
    ])

    if (!group) throw new APIError(404, 'Group cannot be found')
    if (newMemberExists)
      throw new APIError(403, 'User already exists in group!')

    const privateUser = await getPrivateUser(userId)
    if (privateUser && privateUser.blockedGroupSlugs.includes(group.slug)) {
      await updatePrivateUser(tx, userId, {
        blockedGroupSlugs: FieldVal.arrayRemove(group.slug),
      })
    }

    const isAdminRequest = isAdminId(myId)
    const isModRequest = isModId(myId)

    if (userId === myId) {
      if (group.privacy_status === 'private') {
        throw new APIError(403, 'You can not add yourself to a private group!')
      }
    } else {
      if (!requester) {
        if (
          !isAdminRequest &&
          !(isModRequest && group.privacy_status !== 'private')
        ) {
          throw new APIError(
            403,
            'User does not have permission to add members'
          )
        }
      } else {
        if (requester.role !== 'admin')
          throw new APIError(
            403,
            'User does not have permission to add members'
          )
      }
    }

    const member = { member_id: userId, group_id: groupId }
    // insert and return row
    const ret = await tx.one(
      `insert into group_members (member_id, group_id) values ($1, $2)
      returning *`,
      [member.member_id, member.group_id]
    )

    return { status: 'success', member: ret }
  })
}
