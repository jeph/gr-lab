# GR Photo privacy policy

Last updated: 12 November 2026

GR Photo is an app for Ricoh GR cameras. It pairs with your camera over Bluetooth, connects to the camera's own Wi-Fi network, and lets you browse and download your photos and videos and shoot remotely. GR Photo has no accounts, no analytics, no advertising and no crash reporting. It sends nothing to the developer or to anyone else.

## What GR Photo keeps on your phone

GR Photo keeps the following in its own app storage on your phone:

- Your settings: the theme, the language if you chose one, whether GR Photo connects to your camera when it is nearby, the auto-disconnect time, the Shoot mode you used last and whether debug logging is on.
- Your paired cameras: the name you gave each one, its model, serial number, firmware version, Bluetooth name and address, the identifier your phone uses for it, when you paired it and whether your phone has already joined its Wi-Fi.
- A record of your downloads: which files from which camera you have saved, with the date and size the camera reported for each (so GR Photo notices when a camera later holds a different file under the same name), and downloads still waiting.
- Your saved looks: the name you gave each one, its Image Control settings, where it came from (a photo's file name or a Custom slot) and, for a look saved from a photo, a smaller copy of that photo, which way up it was taken and the Image Control settings it was taken with.
- Copies of what your cameras sent, so the Library opens quickly: the list of files on each camera with their date, size and orientation, thumbnails and previews, videos you played, and files that are still being downloaded. These are kept in the app's cache, which your phone may clear when it needs space. GR Photo keeps the thumbnails and previews of all your cameras to 256 MB and the videos you played to 1 GB: when they grow past that, it deletes the ones you looked at or played longest ago first, and fetches them from the camera again when you open them. It does not delete what is on screen, a video while it is open or a video still being copied.
- The debug log, when it is on (see below).

GR Photo reads your camera's Wi-Fi password from the camera over Bluetooth each time it connects and passes it to your phone's Wi-Fi system to join the camera's network. The password is not saved with your paired cameras. While debug logging is on, though, the password is written to the debug log on your phone, like the rest of the exchange with the camera (see below).

Photos and videos you download are saved to your phone's photo library, in an album called GR Photo: on iOS an album in Photos, on Android the GR Photo folder under Pictures. From then on they are yours and are managed by your photo app; GR Photo does not change or delete them.

The demo version of GR Photo uses a simulated camera with sample photos included in the app. It keeps its data apart from that of real cameras.

On Android, GR Photo turns off backup to your Google account. When you move to a new Android phone with a cable or Wi-Fi transfer, Android can still copy GR Photo's data, including the debug log, to the new phone. On iOS, GR Photo leaves all of its data out of your iCloud and computer backups.

## What GR Photo sends, and to whom

GR Photo communicates only with your camera:

- Over Bluetooth, to pair with the camera, find it nearby, wake it, turn on its Wi-Fi, read its Wi-Fi network name and password, work as a remote shutter with its shooting settings, and read and write the looks in its Custom slots C1 to C3. When pairing, GR Photo gives the camera your phone's name, which the camera shows in its list of paired devices. On Android this is the device name you set; on iOS it is the model, such as iPhone.
- Over the camera's own Wi-Fi network, to list, preview and download your photos and videos, show the camera's live view and shoot. These requests go only to the camera, at the address 192.168.0.1 on its network.

GR Photo makes no other network connections. It sends nothing to the developer or to third parties: no analytics, no usage statistics, no crash reports, no update checks and no advertising. Its fonts and license texts are included in the app.

## The debug log

The debug log helps find bugs. While it is on, GR Photo records every exchange with your camera in full, along with the app's own messages and errors. The log therefore contains your camera's serial number, its Bluetooth name and address, its Wi-Fi network name and password, the names, dates and sizes of the files on the camera and your phone's name. It does not contain your photos or videos.

Debug logging is off unless you turn it on, under Settings, Debug log, Enable debug logging. It is on by default only in GR Photo Dev, the test version of the app. The log is limited to about 50 MB; the oldest entries are deleted first.

The log stays on your phone. On iOS it is in GR Photo's app storage. On Android it is in GR Photo's folder under Android/data, which developer tools on a computer connected to the phone can also read. It is not in backups, except that Android can copy it when you transfer to a new phone (see above); clear the log first if you don't want that. Otherwise it leaves your phone only if you tap Export log and choose where to send it in the share sheet; the app you choose then handles it under its own terms. Because the log contains your camera's Wi-Fi password, share it only with someone you trust, such as the developer when you report a bug.

## Permissions

On Android, GR Photo asks for or uses:

- Nearby devices (Bluetooth scan and connect), to find, pair with and control your camera. GR Photo tells Android that it does not use Bluetooth scans to work out your location, and it does not ask for location access.
- Wi-Fi and network access, to join the camera's Wi-Fi network, which Android asks you to approve, to check that the phone is on it and to send the camera's traffic over it.
- Internet, which Android requires for any network connection. GR Photo uses it only to talk to the camera.
- Notifications, to show a running download with its progress and buttons to pause or cancel it while you use another app. Android asks you to allow them the first time you download. GR Photo sends no other notifications, and downloads run whether or not you allow them.
- Running in the background and keeping the phone awake, only while downloads run, so that they carry on when you leave GR Photo or lock the phone.

Saving photos and videos to Pictures needs no permission on the Android versions GR Photo runs on.

On iOS, GR Photo asks for:

- Bluetooth, to find, pair with, wake and control your camera.
- Local network, to talk to the camera over its Wi-Fi network.
- Photos, to save the photos and videos you download to the GR Photo album. iOS lets an app keep an album only with full access to your library, so that is what GR Photo asks for. It uses the access only to add what you download and to find the album named GR Photo; it does not look at, change or delete your other photos and videos. If you allow limited access or Add Photos Only instead, GR Photo still saves what you download, outside the album.
- Joining the camera's Wi-Fi network, which iOS asks you to approve. GR Photo also reads the name of the Wi-Fi network your phone is on, only to check that it has joined the camera.

On iOS 26 and later, iOS shows a running download on the Lock Screen and in the Dynamic Island while you use another app. That needs no permission.

GR Photo does not use your location, camera, microphone or contacts. It shows notifications only on Android, and only for running downloads.

## Deleting your data

- Forget camera, on the camera's page under Cameras, removes the camera from GR Photo's paired cameras and deletes what GR Photo keeps about it: the cached file list, thumbnails, previews and videos of that camera, its downloads still waiting and the record of its files you saved. Photos and videos you saved to your photo library stay there, and so do your saved looks, including those saved from that camera. The debug log is not changed; Clear log deletes it. Your phone's Bluetooth settings may still list the camera, and the camera may still list your phone; you can remove those entries in the phone's Bluetooth settings and on the camera.
- Delete, in a saved look's menu under Looks, removes the look and its copy of the photo from your phone. Looks you loaded into the camera's Custom slots stay on the camera.
- Clear log, under Settings, Debug log, deletes the debug log from your phone.
- Uninstalling GR Photo deletes everything GR Photo keeps on your phone, including the debug log. Photos and videos you saved to your photo library stay there.

## Children

GR Photo is not directed at children. It sends no personal information about anyone, children included, to the developer or to third parties.

## Contact

If you have a question about this policy or about GR Photo, contact jeph, GR Photo's developer, by opening an issue in GR Photo's GitHub repository, jeph/gr-photo, at github.com/jeph/gr-photo.

## Changes to this policy

When GR Photo changes what it keeps on your phone, what it sends or the permissions it asks for, this policy is updated in the next version of the app and the date at the top changes.
