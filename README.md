# FRC: Find Run Clubs (iOS draft)

An iPhone app that pulls **club events from Strava**, puts them on a **map**, and
organizes them by **day of the week**. Each pin on the map is just the start time;
tap it to highlight the club, tap again (or tap its card) for the club page: route,
host, club admins, who's going, and weekly turnout.

> Status: draft for QA, built to the FRC design handoff (Volt palette, Stride logo,
> Archivo / Geist). It runs without any setup on **sample data** (the handoff's
> fictional Nashville clubs). Connect Strava to see your own clubs' events.

| Map | Filters | Club page | Club page, continued |
| --- | --- | --- | --- |
| <img src="docs/screenshots/01-map-tuesday.jpg" width="200"> | <img src="docs/screenshots/04-filters.jpg" width="200"> | <img src="docs/screenshots/05-club-five-points.jpg" width="200"> | <img src="docs/screenshots/06-club-five-points-bottom.jpg" width="200"> |

*Sample data, captured in the iOS Simulator by CI. To refresh: Actions → iOS → Run workflow →
"update_readme_screenshots".*

## What's in the draft

| Screen | What it does |
| --- | --- |
| **Map** | FRC mark (opens Account), "Neighborhood or club" search, Filters button with a dot when filters are on. **Mon–Sun chips** (today is dotted) and an **Any / Early / Midday / Evening** segment. Pins show start times; the selected one turns lime and shows the club name. A bottom sheet lists the matching clubs (time, neighborhood, distance, avg runners); drag or tap its header to expand. |
| **Filters** | Pick one or more days, time of day, a start-time window, distance (under 3 / 3–6 / 6+ mi), runs only, and which clubs to show. The button counts matches live ("Show 4 clubs"); ✕ discards changes. |
| **Club page** | Route map (ink casing, lime line, Start marker) with a **route switch** when a club offers two distances, schedule tag ("Weekly · Tuesdays"), meeting point, distance / elevation / avg runners, **8-week turnout** bars, **host, club admins, who's going this week**, pace and terrain, **Get directions** (Google Maps or Apple Maps), **View on Strava**, save and share. |
| **Account** | Connect or disconnect Strava; switch back to sample data for testing. |

Behind the scenes: Strava sign-in (OAuth, tokens in the Keychain, auto-refresh), one
request per club on launch, and details (admins, attendees, full route) fetched only
when a club page opens.

### How the build maps to the design handoff

- **Pins show times.** The wireframe draws dots; the original brief asked for the time
  in a button, so pins are ink time pills and the selected one gets the lime accent and
  a name label, as in the wireframe.
- **Time-of-day ranges are contiguous:** Early is before 10 AM, Midday 10 AM–4 PM,
  Evening 4 PM and later. The wireframe's 5–9 AM / 11 AM–2 PM / 5–8 PM left gaps where
  a 10 AM or 8:30 PM run would only show under "Any".
- **Route switch:** Strava events carry one route each, so when a club posts separate
  events at the same time and place (a 5 mi and a 3 mi), the app merges them into one
  listing with a route switch.
- **Base map is Apple Maps (MapKit):** free, no API key or billing account. Directions
  offer Google Maps or Apple Maps. Moving the base map to Google Maps (for custom
  neutral styling that matches the wireframe exactly) needs a Google Maps API key tied
  to a billing account; only `EventsMapView` and the club page's `RouteMap` would change.
- **Added beyond the wireframes:** host, admins and who's going (from the original
  brief), save and share, runs-only and per-club filters, sample-data badge.
- **Not built yet:** the Marketer ("Pro") dashboard. It's a separate desktop web
  product; the shared turnout metrics it needs (average, growth, peak) are in FRCKit.

## Run it (5 minutes)

Requirements: a Mac with **Xcode 16 or newer**. The app targets iOS 17+.

1. Clone the repo and open `FindRunClub.xcodeproj`.
2. Pick an iPhone simulator and press **Run** (⌘R).

With no Strava keys, the app shows the sample Nashville clubs. Set the simulator's
location to Nashville (Features → Location → Custom Location, `36.158, -86.776`) to see
yourself on the map.

## Connect real Strava data

1. Go to **https://www.strava.com/settings/api** and create an API application.
   - **Authorization Callback Domain:** `localhost`
   - Website / name / icon: anything for now.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and fill in
   the **Client ID** and **Client Secret**. This file is git-ignored, so the secret
   never lands in this public repo.
3. Run the app, tap the **FRC mark** (top-left), then **Connect with Strava**.

The app asks only for Strava's `read` scope, and shows events from clubs **the
signed-in athlete belongs to**.

### Run on a physical iPhone

Set your Apple Developer team in `Config/Secrets.xcconfig` (`DEVELOPMENT_TEAM`, and
a unique `PRODUCT_BUNDLE_IDENTIFIER`), or pick the team under
*Signing & Capabilities* in Xcode. TestFlight distribution needs a paid Apple
Developer Program membership.

## QA checklist (sample data)

- [ ] Launch: today's chip is selected and dotted; the sheet shows "Sample data".
- [ ] **Tue**: the wireframe's four clubs (Shelby Bottoms 6:00 AM, Music Row 5:30 PM,
      Five Points 6:00 PM, Gulch 6:30 PM). On the current day, a run drops off an hour
      after it starts, since the strip shows the next seven days. **Evening** shows three.
- [ ] Tap a pin: it turns lime with the club name, and its card is outlined and scrolled
      into view. Tap it again to open the club page.
- [ ] **Five Points Run Club**: the route switch flips between the 5 mi and 3 mi loops;
      distance and elevation update (5.0 mi / +142 ft, 3.0 mi / +64 ft).
- [ ] Turnout bars: 8 weeks, this week in lime; avg runners 75.
- [ ] **12South Social Run** (Thu) shows "You're going" and a check on its pin and card.
- [ ] **Fri** has one club; every day has at least one.
- [ ] **Sat**: two runs; turn off *Runs only* in Filters and East Bank Riders appears
      (grey pin).
- [ ] Filters: pick Tue + Thu, Evening, 3–6 mi; the button count matches the sheet after
      tapping it. ✕ discards changes; Reset clears them.
- [ ] Search "gulch" on Tuesday (or "Germantown" on Wednesday) narrows the list to that club.
- [ ] Get directions offers Google Maps and Apple Maps; share and save work.
- [ ] With keys: Connect with Strava, approve, and your clubs' events load.
- [ ] Disconnect Strava: the app returns to sample data.

## How it works

```
FindRunClub/                 SwiftUI app (iOS 17+)
  App/                       App entry, AppModel (picks Strava vs sample data), AppConfig
  Auth/                      Strava sign-in (ASWebAuthenticationSession), Keychain storage
  Events/                    Map screen, time pins, bottom sheet, EventsStore, saved clubs
  Filters/                   Filters screen
  ClubDetail/                Club page + lazy loading of admins/attendees/route
  Account/                   Connect/disconnect Strava, sample-data toggle
  Shared/Theme.swift         Volt tokens, fonts, Stride logo, buttons, chips, cards
  Resources/Fonts/           Archivo, Geist, Geist Mono (SIL Open Font License)
Packages/FRCKit/             Swift package with no UI code, unit-tested
  Models/                    Strava club, event, athlete, route (lenient decoding)
  Strava/                    API client, OAuth, token session (refresh + Keychain hook)
  Schedule/                  7-day schedule, ClubRun grouping, RunFilter, turnout metrics
  DataSources/               Live Strava source + sample Nashville source behind one protocol
Config/                      Build settings, Info.plist, Secrets.example.xcconfig
scripts/                     capture-screenshots.sh (used by CI)
```

**Strava endpoints used**

| Call | When | Cost |
| --- | --- | --- |
| `GET /athlete/clubs` | launch / refresh | 1 request |
| `GET /clubs/{id}/group_events?upcoming=true` | launch / refresh | 1 per club |
| `GET /clubs/{id}/admins` | opening a club page (cached per club) | 1 |
| `GET /group_events/{id}/athletes` | opening a club page | 1+ per route option |
| `GET /routes/{id}` | opening a club page with a route (cached) | 1 per route option |

Strava's default limits are 200 requests / 15 min and 2,000 / day (reads: 100 / 15 min,
1,000 / day), so details load only when a club page opens. List distances come from
measuring the route line each event already includes, so filtering by distance costs no
extra requests.

**Tests:** `swift test --package-path Packages/FRCKit` (or ⌘U in Xcode). The decoding
tests use a real `group_events` response captured in March 2026. GitHub Actions
(`.github/workflows/ios.yml`) runs the tests, builds the app, launches it in an iPhone
simulator, and uploads screenshots of each screen as the run's `screenshots` artifact
(`scripts/capture-screenshots.sh` does the same on a Mac).

## Known limitations and open questions

- **Turnout history isn't available from Strava.** The API shows who's going to the next
  run, not past attendance. The sample data has 8-week histories; with live data the
  chart explains this and "avg runners" shows "–". Filling it in means recording each
  run's "going" count weekly, which is a job for an FRC backend.
- **Club events aren't in Strava's published API reference.** `GET /clubs/{id}/group_events`
  still works (other apps use it in 2026), but Strava could change it without notice.
  Decoding is deliberately forgiving so one odd field doesn't break the list.
- **Only the signed-in athlete's clubs.** Strava exposes events for clubs you've joined.
  A "discover every run club in my city" map, and the Marketer product, need another
  source: clubs connecting their own Strava accounts to an FRC backend, clubs submitting
  events directly, or a Strava partnership.
- **Neighborhood names** come from the event's free-text address, so they're only as
  good as what organizers typed.
- **Recurring events:** Strava's list often includes only the *next* date of a recurring
  event. That covers a 7-day view, which is why the app looks one week ahead.
- **Client secret in the app:** fine for a draft; for the App Store, move the token
  exchange to a small backend so the secret isn't shipped in the binary.
- **Strava app review:** new Strava API apps allow only a small number of connected
  athletes (initially just the owner) until Strava approves a capacity increase.
  Other testers can use sample data in the meantime.
- **Strava brand and API terms:** before release, use Strava's official "Connect with
  Strava" button and "Powered by Strava" logo (Strava's own marks, so they're exempt
  from the no-orange rule), and review the API Agreement's rules on showing other
  athletes' data and on commercial use, which matters most for the Marketer product.
- **Fonts:** the logo uses live Archivo text, as the handoff notes; outline it for final
  production artwork.
