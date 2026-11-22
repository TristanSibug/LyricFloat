# Lyric Float

Lyric Float shows timed lyrics in a movable Picture in Picture window on iOS 17 and later. It can follow Spotify playback after a one-time connection.

Download the IPA from the release notes and sign it with your sideloading tool. [GitHub releases](https://github.com/TristanSibug/lyric-float/releases)

## Use Spotify sync

1. Tap **Connect Spotify** and authorize Lyric Float on Spotify's sign-in page. Lyric Float saves the refresh token in the iPhone Keychain.
2. Start a song in Spotify and open Lyric Float. It reads the current track and playback time, looks up timed lyrics through LRCLIB, and follows pauses, seeks, and track changes. Updates can lag by a few seconds.
3. Tap **Float lyrics** to keep the lines visible while using another app. Use **Options → Disconnect Spotify** to remove the saved connection.

If automatic matching finds no timed lyrics, tap **Find lyrics** to pick a recording manually. This switches to the position slider and **Start lyrics**. Tap **Follow Spotify** to resume automatic sync. Open **Options → Timing adjustment** to fine-tune when the lyrics appear.

## Configure a build

Register a Web API app with `app.lyricfloat.oauth://callback` as its redirect URI and set the public `SPOTIFY_CLIENT_ID` build setting. No client secret is needed. Spotify Development Mode requires a Premium app owner and approved testers. Open `LyricFloat.xcodeproj` in Xcode and select an iPhone target to build. A build without an app registration offers manual lyric search. [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) · [Spotify development access](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)

For Spotify sync, lyric lookup sends the track's title, artist, album, and duration to LRCLIB. Playback and sign-in requests use Spotify's own endpoints. Review Spotify's policy and confirm permission for the feature before distributing a Spotify-connected build. [Spotify Developer Policy](https://developer.spotify.com/policy)
