import Foundation

/// Response bodies used by the tests. `realGroupEvent` is a real
/// `GET /clubs/{id}/group_events` element captured in March 2026 (from the
/// open-source feedbee/strava-club-events project), with IDs restored to the
/// numeric form Strava sends on the wire.
enum Fixtures {
    static let realGroupEvent = #"""
{
  "id": 3468204764614160646,
  "resource_state": 2,
  "title": "Club Recurring Event with Route",
  "description": "Event description",
  "club_id": 1752189,
  "club": {
    "id": 1752189,
    "resource_state": 1,
    "name": "Club Events Testing Club"
  },
  "organizing_athlete": {
    "id": 9545474,
    "username": null,
    "resource_state": 2,
    "firstname": "Valera",
    "lastname": "Leontyev",
    "bio": null,
    "city": "Warszawa",
    "state": "Masovian Voivodeship",
    "country": "Poland",
    "sex": "M",
    "premium": true,
    "summit": true,
    "created_at": "2015-06-03T06:19:57Z",
    "updated_at": "2025-09-23T08:09:39Z",
    "badge_type_id": 1,
    "weight": 78,
    "profile_medium": "https://dgalywyr863hv.cloudfront.net/pictures/athletes/9545474/27017331/2/medium.jpg",
    "profile": "https://dgalywyr863hv.cloudfront.net/pictures/athletes/9545474/27017331/2/large.jpg",
    "friend": null,
    "follower": null,
    "blocked": false,
    "can_follow": true
  },
  "activity_type": "Ride",
  "created_at": "",
  "route_id": 3465434395661532938,
  "route": {
    "id": 3465434395661532938,
    "id_str": "3465434395661532938",
    "resource_state": 1,
    "name": "South Road Ride 108 Public",
    "map": {
      "id": "r3465434395661532938",
      "summary_polyline": "qfi}H_hv_C|LmB?qDkDSMuDfD_t@OoXwF_f@jLcKjIaX`XgFjI}GxDa@`VuRrCcNtb@uXaAwHvIq^|EqFfI_@tIaKlUou@m@aUtBsb@`KmX_E}c@f@gb@zHcYdDeFfd@}W|IyI~g@}gAf\\g^nCy@jKnFbQcC`UqVz`AcH{Fna@f@fBrHyKd@nAU|~BtUoKdCmJjeA~_@nThR~@~J|EuDbIiAbs@nMiIos@~Bwq@bgAqaAlZqt@zd@wm@xg@{N|PBbhApVxv@pU`D{G|[iRnOnEbN}Ir_@yF?yBdA[|ATEbVhWt@~m@xKhJS|B`Db@yEdl@mrAhFgUKoSeH{MgA{JtQw^pN{}@haAsc@pa@oB`D`@jCnE`a@daAP|w@nRhCzClChOk@jN`Vt@zXyMx\\mAtRD|jAmDf`BeBf@uMuGaAlKlSpVxlA`z@p~@|`@dBbR|yBx~AaTht@~NbQjQpy@vg@zr@le@dcAvAzUqBx[}En\\OdkAnsAco@jt@ua@`Fdb@`QdVyuA~kEyb@rVoe@hNsf@B_Abc@sM`h@_WbIcHpGcMnTyA|m@rAzIXz`AmVrEie@}LKhH_Ce@uBbMwB`Cuy@pBwVyWo~@oG}Aqa@iU}^gb@}^mIgDcZsZ{]fc@ad@eJwQwWuHy@{]ttAaZnh@kWhK}IbJ_`Bz~@eNnRoq@CigAmLuCrBcLvVa|@k_@gbAzf@y`AtVqI_a@~KkkAuDsd@uSk_@uG~Bk_@cs@mCsUej@_r@RaJ_I}M}OeLsn@{KsLkVwh@cIwCyx@}KkAqB_E_ISyKuEIiC_P_Tc|@gb@aGuS{PqM}G}JwHi^DiYiEa`@Ac^~Bih@}DaKaDge@aKq[z@}XcAaHok@cQqGs`@q]k`AqA}@]zIcU|s@uI`KgI^}EpFwIp^`AvHub@tXsCbNaVtRyD`@kI|GaXfFkI`XkLbKbFb_@b@j_@{Cdz@eHtAMnEiEhBlFkB",
      "resource_state": 2
    },
    "map_urls": {
      "url": "https://d3o5xota0a1fcr.cloudfront.net/v6/maps/5F4T22GDJKXZZXMKXHUQYHD6OKYTQWDKSAQL7Q3MUXWKH2IUFEDXBF3UENTMBB7OOOZDM6WHOVIBXRDVTJP3KPC6DFGKDQM6K57WXAI=",
      "retina_url": "https://d3o5xota0a1fcr.cloudfront.net/v6/maps/JDQWIAENQUP4VGWW2AVNGSZRZFGPQ62TVJCGVJ5Q4ZBYI2CYAIHW7THZ5J66HATVXY5T72HU2LEIELFYRLRGSPNV5AROMKZMFOUFGRA=",
      "light_url": "https://d3o5xota0a1fcr.cloudfront.net/v6/maps/JDQWIAENQUP4VGWW2AVNGSZRZFGPQ62TVJCGVJ5Q4ZBYI2CYAIHW7THZ5J66HATVXY5T72HU2LEIELFYRLRGSPNV5AROMKZMFOUFGRA=",
      "dark_url": "https://d3o5xota0a1fcr.cloudfront.net/v6/maps/2FIYF35UGSX6EJ3UQB5M4DOYEZ4NNGR7EFL4EYV47F6SEGS7N4S4WZFETDENIITJWNVQ33WCOD5DX7BDFNGE7AOJV54ABUL3OYLDB3A="
    }
  },
  "women_only": false,
  "private": true,
  "skill_levels": null,
  "terrain": null,
  "upcoming_occurrences": [
    "2026-03-24T08:00:00Z"
  ],
  "zone": "Europe/Warsaw",
  "address": "Warsaw, MZ, Poland",
  "joined": true,
  "start_latlng": [
    52.237695,
    21.005427
  ]
}
"""#

    static let clubEventsList = #"""
[
  {
    "id": 101,
    "title": "Tuesday Track",
    "club_id": 55,
    "activity_type": "Run",
    "upcoming_occurrences": ["2026-09-29T23:00:00Z", "2026-10-06T23:00:00.000Z"],
    "zone": "America/New_York",
    "start_latlng": [40.72, -73.95],
    "joined": false
  },
  { "title": "Broken event without an id" },
  null,
  {
    "id": "102",
    "title": "   ",
    "club": { "id": 55, "resource_state": 1, "name": "Test Club" },
    "activity_type": 7,
    "upcoming_occurrences": ["not a date", "2026-10-01T10:30:00Z"],
    "start_latlng": [],
    "skill_levels": null,
    "terrain": 2,
    "women_only": true,
    "address": ""
  }
]
"""#

    static let clubAdmins = #"""
[
  { "resource_state": 2, "firstname": "Peter", "lastname": "S." },
  { "id": 42, "firstname": "Ana", "lastname": "Lopez", "profile_medium": "avatar/athlete/medium.png" },
  { "id": 43, "firstname": "Kofi", "lastname": "", "profile_medium": "https://example.com/kofi.jpg" }
]
"""#

    static let athleteClubs = #"""
[
  {
    "id": 1752189,
    "resource_state": 2,
    "name": "Club Events Testing Club",
    "profile_medium": "https://dgalywyr863hv.cloudfront.net/pictures/clubs/1752189/40566062/1/medium.jpg",
    "sport_type": "running",
    "city": "Warszawa",
    "state": "Masovian Voivodeship",
    "country": "Poland",
    "private": true,
    "member_count": 1,
    "url": "club-events"
  }
]
"""#

    static let tokenExchange = #"""
{
  "token_type": "Bearer",
  "expires_at": 1790000000,
  "expires_in": 21600,
  "refresh_token": "refresh-1",
  "access_token": "access-1",
  "athlete": { "id": 9545474, "firstname": "Valera", "lastname": "Leontyev", "profile_medium": "https://example.com/v.jpg" }
}
"""#

    static let tokenRefresh = #"""
{
  "token_type": "Bearer",
  "access_token": "access-2",
  "expires_at": 1790021600,
  "expires_in": 21600,
  "refresh_token": "refresh-2"
}
"""#

    static let route = #"""
{
  "id": 3465434395661532938,
  "id_str": "3465434395661532938",
  "resource_state": 3,
  "name": "South Road Ride 108 Public",
  "distance": 108123.4,
  "elevation_gain": 612.0,
  "estimated_moving_time": 14400,
  "map": { "id": "r3465434395661532938", "summary_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@", "polyline": "_p~iF~ps|U_ulLnnqC" }
}
"""#
}
