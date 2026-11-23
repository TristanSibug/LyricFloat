# Lyric Float Remote

This experimental iOS 17+ build reads the currently playing song from the Spotify app on the same iPhone. It uses Spotify’s App Remote SDK to test account access and Picture in Picture sync. The app has its own bundle ID so testers can install it alongside Lyric Float 0.8.0.

## Configure Spotify for this build

Open the Spotify Dashboard registration used by the IPA. In **Settings**, enable **iOS**, add the iOS bundle ID `app.lyricfloat.remote`, and add the redirect URI `app.lyricfloat.remote.oauth://callback`. Test with a Spotify account outside that registration’s user list. [Spotify Dashboard](https://developer.spotify.com/dashboard) · [Spotify iOS setup](https://developer.spotify.com/documentation/ios/getting-started)

## Test on an iPhone

1. Sideload the IPA. In Spotify, sign in with the test account and play a song with known timed lyrics.
2. Open **Lyric Float Remote** and tap **Connect Spotify**. Approve the request in Spotify. Check whether the track and lyrics appear or note the error shown.
3. Tap **Float lyrics** and go back to Spotify. Pause, seek, and skip to a different song with timed lyrics. Check whether the floating window responds before reopening Lyric Float Remote.

The build checks playback every three seconds and keeps App Remote active during Picture in Picture for this test. Spotify recommends disconnecting when the app becomes inactive, so report any frozen lyrics or connection errors during the test. Tap **Connect Spotify** after a fresh app launch. [Spotify App Remote lifecycle](https://developer.spotify.com/documentation/ios/concepts/application-lifecycle)

## Build from source

Open `LyricFloat.xcodeproj` in Xcode. The project pins Spotify’s iOS SDK at 5.0.1 via Swift Package Manager. Set `SPOTIFY_CLIENT_ID` to the public ID of the configured Spotify app, then choose an iPhone target.

Lyric lookup sends the track’s title, artist, album, and duration to LRCLIB. Verify that the use case is permitted before offering a wider Spotify-connected release. [Spotify Developer Policy](https://developer.spotify.com/policy)
