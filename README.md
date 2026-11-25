# Lyric Float Remote

This experimental iOS 17+ build reads the currently playing song from the Spotify app on the same iPhone. It uses Spotify’s App Remote SDK to test account access and Picture in Picture sync. The app has its own bundle ID so testers can install it alongside Lyric Float 0.8.0.

## Configure Spotify for this build

Open the Spotify Dashboard registration used by the IPA. In **Settings**, enable **iOS**, add the iOS bundle ID `app.lyricfloat.remote`, and add the redirect URI `app.lyricfloat.remote.oauth://callback`. Test with a Spotify account outside that registration’s user list. [Spotify Dashboard](https://developer.spotify.com/dashboard) · [Spotify iOS setup](https://developer.spotify.com/documentation/ios/getting-started)

## Test on an iPhone

1. Sideload the IPA. In Spotify, sign in with the test account and play a song with known timed lyrics.
2. Open **Lyric Float Remote** and tap **Connect Spotify**. Approve the request in Spotify. Check whether the track and lyrics appear or note the error shown.
3. Tap **Float lyrics** and go back to Spotify. Pause, seek, and skip to a different song with timed lyrics. Check whether the floating window responds before reopening Lyric Float Remote.

The build checks playback every three seconds and keeps App Remote active during Picture in Picture. After you connect, Lyric Float saves the authorization in the iPhone Keychain and tries to reconnect when you reopen the app. If Spotify needs permission again, start a song and tap **Connect Spotify**. **Disconnect Spotify** clears the saved connection. [Spotify App Remote lifecycle](https://developer.spotify.com/documentation/ios/concepts/application-lifecycle)

## Show lyrics on the Lock Screen

While lyrics are visible in the app, tap **Show on Lock Screen**. The lyrics card uses your selected font and theme. Spotify’s player already shows the song and artist. Tap **Remove from Lock Screen** in Lyric Float to end the session.

Use a sideloading tool that keeps and signs the included app extension. After about 15 seconds without fresh playback data, the card shows **Tap to refresh**. Tapping it opens Lyric Float and tries your saved Spotify connection. [Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

On iOS 26, **Show on Lock Screen** also starts a background sync session for up to 15 minutes. To test it, lock your iPhone and let the current song finish or skip it from Spotify’s Lock Screen controls. The lyrics card looks up timed lyrics for each new song. iOS may show a separate **Lyric Float** progress card. A pause or connection loss of about 30 seconds can end sync, and iOS can end the task early. [Apple continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)

When the sync session ends, Lyric Float removes its lyrics card and shows the reason in the app. Tap **Show on Lock Screen** again to start another session.

## Build from source

Open `LyricFloat.xcodeproj` in Xcode. The project pins Spotify’s iOS SDK at 5.0.1 via Swift Package Manager. Set `SPOTIFY_CLIENT_ID` to the public ID of the configured Spotify app, then choose an iPhone target.

Lyric lookup sends the track’s title, artist, album, and duration to LRCLIB. Verify that the use case is permitted before offering a wider Spotify-connected release. [Spotify Developer Policy](https://developer.spotify.com/policy)
