// Security-rules tests for ../firestore.rules, run against the real
// Firestore emulator (not a mock) via @firebase/rules-unit-testing - this
// is what actually enforces rule logic, unlike the mocked-Firestore
// service-layer tests in test/services/, which bypass rules entirely.
//
// Run with: firebase emulators:exec --only firestore "npm test" (from
// firestore-tests/), or see the root README for the full command.
import { before, beforeEach, after, describe, test } from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'convoy-rules-test',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function asUser(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function asAnon() {
  return testEnv.unauthenticatedContext().firestore();
}

// Seeds data bypassing rules entirely - for setting up preconditions, not
// for the behavior under test itself.
async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => fn(context.firestore()));
}

describe('users/{userId}', () => {
  test('any signed-in user can read another user\'s doc', async () => {
    await seed((db) => db.doc('users/u1').set({ displayName: 'Alex' }));
    await assertSucceeds(asUser('u2').doc('users/u1').get());
  });

  test('an unauthenticated request cannot read', async () => {
    await seed((db) => db.doc('users/u1').set({ displayName: 'Alex' }));
    await assertFails(asAnon().doc('users/u1').get());
  });

  test('a user can write their own doc', async () => {
    await assertSucceeds(asUser('u1').doc('users/u1').set({ displayName: 'Alex' }));
  });

  test('a user cannot write another user\'s doc', async () => {
    await assertFails(asUser('u1').doc('users/u2').set({ displayName: 'Eve' }));
  });
});

describe('groups/{groupId}', () => {
  test('any signed-in user can read a group doc', async () => {
    await seed((db) => db.doc('groups/g1').set({ createdBy: 'owner1', status: 'active' }));
    await assertSucceeds(asUser('someone-else').doc('groups/g1').get());
  });

  test('an unauthenticated request cannot read', async () => {
    await seed((db) => db.doc('groups/g1').set({ createdBy: 'owner1', status: 'active' }));
    await assertFails(asAnon().doc('groups/g1').get());
  });

  test('a user can create a group naming themselves as createdBy', async () => {
    await assertSucceeds(
      asUser('u1').doc('groups/g1').set({ createdBy: 'u1', status: 'active', ownerId: 'u1' }),
    );
  });

  test('a user cannot create a group naming someone else as createdBy', async () => {
    await assertFails(
      asUser('u1').doc('groups/g1').set({ createdBy: 'u2', status: 'active', ownerId: 'u2' }),
    );
  });

  test('the owner can delete their group', async () => {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' });
      await db.doc('groups/g1/members/owner1').set({ role: 'owner' });
    });
    await assertSucceeds(asUser('owner1').doc('groups/g1').delete());
  });

  test('a non-owner cannot delete the group', async () => {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' });
      await db.doc('groups/g1/members/owner1').set({ role: 'owner' });
      await db.doc('groups/g1/members/member2').set({ role: 'member' });
    });
    await assertFails(asUser('member2').doc('groups/g1').delete());
  });

  test('the owner can update arbitrary fields', async () => {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' });
      await db.doc('groups/g1/members/owner1').set({ role: 'owner' });
    });
    await assertSucceeds(asUser('owner1').doc('groups/g1').update({ name: 'Renamed' }));
  });

  test('a non-owner cannot update fields (not the narrow ownerless-claim shape)', async () => {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' });
      await db.doc('groups/g1/members/owner1').set({ role: 'owner' });
    });
    await assertFails(asUser('member2').doc('groups/g1').update({ name: 'Hijacked' }));
  });

  test('anyone can claim ownership of an ownerless group via the narrow exception', async () => {
    await seed((db) =>
      db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: null, status: 'active' }),
    );
    await assertSucceeds(asUser('rejoiner').doc('groups/g1').update({ ownerId: 'rejoiner' }));
  });

  test('the ownerless-claim exception is rejected if the group already has an owner', async () => {
    await seed((db) =>
      db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' }),
    );
    await assertFails(asUser('thief').doc('groups/g1').update({ ownerId: 'thief' }));
  });

  test('the ownerless-claim exception is rejected when claiming ownership for someone else', async () => {
    await seed((db) =>
      db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: null, status: 'active' }),
    );
    await assertFails(asUser('rejoiner').doc('groups/g1').update({ ownerId: 'someone-else' }));
  });

  test('the ownerless-claim exception is rejected if it also touches other fields', async () => {
    await seed((db) =>
      db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: null, status: 'active', name: 'Trip' }),
    );
    await assertFails(
      asUser('rejoiner').doc('groups/g1').update({ ownerId: 'rejoiner', name: 'Hijacked' }),
    );
  });
});

describe('groups/{groupId}/members/{memberId}', () => {
  async function seedActiveGroupWithOwner() {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' });
      await db.doc('groups/g1/members/owner1').set({ role: 'owner' });
    });
  }

  test('an existing member can read the member list', async () => {
    await seedActiveGroupWithOwner();
    await assertSucceeds(asUser('owner1').doc('groups/g1/members/owner1').get());
  });

  test('a non-member cannot read another member\'s doc', async () => {
    await seedActiveGroupWithOwner();
    await assertFails(asUser('stranger').doc('groups/g1/members/owner1').get());
  });

  test(
    'a non-member CAN read their own (not-yet-existing) member doc ' +
      '(regression: this is what makes joinGroupByInviteCode\'s "am I already ' +
      'a member?" check possible without a chicken-and-egg permission-denied)',
    async () => {
      await seedActiveGroupWithOwner();
      await assertSucceeds(asUser('newcomer').doc('groups/g1/members/newcomer').get());
    },
  );

  test('an unauthenticated request cannot read even their own potential doc', async () => {
    await seedActiveGroupWithOwner();
    await assertFails(asAnon().doc('groups/g1/members/newcomer').get());
  });

  test('a user can create their own member doc with role "member"', async () => {
    await seedActiveGroupWithOwner();
    await assertSucceeds(
      asUser('newcomer').doc('groups/g1/members/newcomer').set({ role: 'member' }),
    );
  });

  test('a user cannot create a member doc for someone else\'s uid', async () => {
    await seedActiveGroupWithOwner();
    await assertFails(
      asUser('newcomer').doc('groups/g1/members/someone-else').set({ role: 'member' }),
    );
  });

  test('the group creator can add themselves as owner (createGroup\'s second write)', async () => {
    await seed((db) => db.doc('groups/g1').set({ createdBy: 'owner1', status: 'active' }));
    await assertSucceeds(asUser('owner1').doc('groups/g1/members/owner1').set({ role: 'owner' }));
  });

  test('a non-creator can claim owner role when the group is ownerless', async () => {
    await seed((db) =>
      db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: null, status: 'active' }),
    );
    await assertSucceeds(
      asUser('rejoiner').doc('groups/g1/members/rejoiner').set({ role: 'owner' }),
    );
  });

  test('a non-creator cannot claim owner role when the group already has an owner', async () => {
    await seedActiveGroupWithOwner();
    await assertFails(
      asUser('opportunist').doc('groups/g1/members/opportunist').set({ role: 'owner' }),
    );
  });

  test('only the owner can update another member\'s role', async () => {
    await seedActiveGroupWithOwner();
    await seed((db) => db.doc('groups/g1/members/member2').set({ role: 'member' }));

    await assertSucceeds(
      asUser('owner1').doc('groups/g1/members/member2').update({ role: 'owner' }),
    );
  });

  test('a non-owner cannot update another member\'s role', async () => {
    await seedActiveGroupWithOwner();
    await seed((db) => db.doc('groups/g1/members/member2').set({ role: 'member' }));

    await assertFails(
      asUser('member2').doc('groups/g1/members/member2').update({ role: 'owner' }),
    );
  });

  test('the owner can delete any member', async () => {
    await seedActiveGroupWithOwner();
    await seed((db) => db.doc('groups/g1/members/member2').set({ role: 'member' }));

    await assertSucceeds(asUser('owner1').doc('groups/g1/members/member2').delete());
  });

  test('a member can delete themselves (leave)', async () => {
    await seedActiveGroupWithOwner();
    await seed((db) => db.doc('groups/g1/members/member2').set({ role: 'member' }));

    await assertSucceeds(asUser('member2').doc('groups/g1/members/member2').delete());
  });

  test('a non-owner member cannot delete a different member', async () => {
    await seedActiveGroupWithOwner();
    await seed(async (db) => {
      await db.doc('groups/g1/members/member2').set({ role: 'member' });
      await db.doc('groups/g1/members/member3').set({ role: 'member' });
    });

    await assertFails(asUser('member2').doc('groups/g1/members/member3').delete());
  });
});

describe('groups/{groupId}/locations/{userId}', () => {
  async function seedActiveGroupWithMembers() {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'active' });
      await db.doc('groups/g1/members/owner1').set({ role: 'owner' });
      await db.doc('groups/g1/members/member2').set({ role: 'member' });
    });
  }

  test('a member can read the locations feed', async () => {
    await seedActiveGroupWithMembers();
    await assertSucceeds(asUser('member2').doc('groups/g1/locations/owner1').get());
  });

  test('a non-member cannot read the locations feed', async () => {
    await seedActiveGroupWithMembers();
    await assertFails(asUser('stranger').doc('groups/g1/locations/owner1').get());
  });

  test('a member can write their own location while the group is active', async () => {
    await seedActiveGroupWithMembers();
    await assertSucceeds(
      asUser('member2').doc('groups/g1/locations/member2').set({ lat: 1, lng: 2 }),
    );
  });

  test('a member cannot write someone else\'s location', async () => {
    await seedActiveGroupWithMembers();
    await assertFails(
      asUser('member2').doc('groups/g1/locations/owner1').set({ lat: 1, lng: 2 }),
    );
  });

  test('a non-member cannot write a location even for themselves', async () => {
    await seedActiveGroupWithMembers();
    await assertFails(
      asUser('stranger').doc('groups/g1/locations/stranger').set({ lat: 1, lng: 2 }),
    );
  });

  test('a member cannot write their location once the group has ended', async () => {
    await seed(async (db) => {
      await db.doc('groups/g1').set({ createdBy: 'owner1', ownerId: 'owner1', status: 'ended' });
      await db.doc('groups/g1/members/member2').set({ role: 'member' });
    });
    await assertFails(
      asUser('member2').doc('groups/g1/locations/member2').set({ lat: 1, lng: 2 }),
    );
  });

  test('the owner can delete a member\'s location doc', async () => {
    await seedActiveGroupWithMembers();
    await seed((db) => db.doc('groups/g1/locations/member2').set({ lat: 1, lng: 2 }));

    await assertSucceeds(asUser('owner1').doc('groups/g1/locations/member2').delete());
  });

  test('a non-owner member cannot delete another member\'s location doc', async () => {
    await seedActiveGroupWithMembers();
    await seed((db) => db.doc('groups/g1/locations/owner1').set({ lat: 1, lng: 2 }));

    await assertFails(asUser('member2').doc('groups/g1/locations/owner1').delete());
  });
});
