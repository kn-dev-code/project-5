// TODO: replace with a real live-scores feed. These are made-up teams for
// testing only.

/// Made-up teams per league. Fake games pair two teams from the same league.
const fakeTeams = {
  'Pro Football': [
    'Riverside Raptors',
    'Northgate Knights',
    'Harbor City Mariners',
    'Eastfield Stallions',
    'Oakridge Outlaws',
    'Lakeshore Lightning',
    'Southport Sharks',
    'Greenwood Rams',
  ],
  'College Football': [
    'Kingsbridge Bears',
    'Millbrook Hawks',
    'Westvale Wolves',
    'Stonehill Titans',
    'Brookfield Bison',
    'Highcliff Falcons',
  ],
};

/// A new fake game kicks off this often.
const fakeKickoffInterval = Duration(minutes: 4);

/// How long a fake game lasts from kickoff until it expires and is settled.
/// Short so win/lose can be tested without waiting for a real game.
const fakeGameLength = Duration(minutes: 12);

/// How far ahead upcoming fake games are listed.
const fakeUpcomingWindow = Duration(minutes: 8);

/// How long finished fake games stay listed.
const fakeFinishedWindow = Duration(minutes: 12);
