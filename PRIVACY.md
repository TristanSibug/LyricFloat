# Lyric Float Privacy Policy

## Spotify connection

When you choose **Connect Spotify**, the Spotify app handles authorization. Lyric Float uses Spotify App Remote to read the current track and playback position so it can display lyrics in time with the song. Lyric Float saves the Spotify authorization token in the iPhone’s Keychain so it can reconnect when you reopen the app. [Spotify Privacy Policy](https://www.spotify.com/legal/privacy-policy/)

## Lyric lookup

Lyric Float requests timed lyrics directly from LRCLIB over HTTPS. The request includes the current track’s title, artist, duration, and album name when available. It also identifies the app and version. LRCLIB receives the IP address associated with the request. Your Spotify authorization token stays on your device. [LRCLIB API documentation](https://lrclib.net/docs)

## Information stored on your iPhone

Lyric Float saves your theme and font preferences on your iPhone. Your Home Screen icon selection is handled by iOS. When you enable floating lyrics or Lock Screen lyrics, iOS displays the current lyrics on that surface.

## Disconnect Spotify

In Lyric Float, open **Options** and choose **Disconnect Spotify**. This deletes the saved Spotify authorization token from the Keychain, stops playback sync, and clears the current track and lyrics in the app. You can also manage app access from your Spotify account. [Spotify account app permissions](https://www.spotify.com/account/apps/)

## Contact

For privacy questions about Lyric Float, open a GitHub issue. Keep private account information out of public issues. [Lyric Float issues](https://github.com/TristanSibug/lyric-float/issues)
