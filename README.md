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

While lyrics are visible in the app, tap **Show on Lock Screen**. The Live Activity shows **Song title ⋅ Artist Name** above the current line and uses your lyric font and theme. Tap **Remove from Lock Screen** in Lyric Float to end it.

Use a sideloading tool that keeps and signs the included app extension. After about 15 seconds without fresh playback data, the card shows **Tap to refresh**. Tapping it opens Lyric Float and tries your saved Spotify connection. [Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## Build from source

The **Test Locked Lyrics** button in this experimental build uses iOS 26’s continued processing API. It starts while a song is playing and shows the current line in the system’s progress Live Activity. Lock your iPhone and check whether it advances through the rest of the song. A pause, track change, sync interruption, or iOS cancellation ends the test. Installation and background-task admission after AltStore signing need a device test. [Apple continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)

Open `LyricFloat.xcodeproj` in Xcode. The project pins Spotify’s iOS SDK at 5.0.1 via Swift Package Manager. Set `SPOTIFY_CLIENT_ID` to the public ID of the configured Spotify app, then choose an iPhone target.

Lyric lookup sends the track’s title, artist, album, and duration to LRCLIB. Verify that the use case is permitted before offering a wider Spotify-connected release. [Spotify Developer Policy](https://developer.spotify.com/policy)
