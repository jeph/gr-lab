# GR Lab privacy policy

Last updated: 10 November 2026

GR Lab is an app for Ricoh GR cameras. It pairs with your camera over Bluetooth, connects to the camera's own Wi-Fi network, and lets you browse and download your photos and videos and shoot remotely. GR Lab has no accounts, no analytics, no advertising and no crash reporting. It sends nothing to the developer or to anyone else.

## What GR Lab keeps on your phone

GR Lab keeps the following in its own app storage on your phone:

- Your settings: the theme, the language if you chose one, whether GR Lab connects to your camera when it is nearby, the auto-disconnect time, the Shoot mode you used last and whether debug logging is on.
- Your paired cameras: the name you gave each one, its model, serial number, firmware version, Bluetooth name and address, the identifier your phone uses for it, when you paired it and whether your phone has already joined its Wi-Fi.
- A record of your downloads: which files from which camera you have saved, with the date and size the camera reported for each (so GR Lab notices when a camera later holds a different file under the same name), and downloads still waiting.
- Your saved looks: the name you gave each one, its Image Control settings, where it came from (a photo's file name or a Custom slot) and, for a look saved from a photo, a smaller copy of that photo, which way up it was taken and the Image Control settings it was taken with.
- Copies of what your cameras sent, so the Library opens quickly: the list of files on each camera with their date, size and orientation, thumbnails and previews, videos you played, and files that are still being downloaded. These are kept in the app's cache, which your phone may clear when it needs space. GR Lab keeps the thumbnails and previews of all your cameras to 256 MB and the videos you played to 1 GB: when they grow past that, it deletes the ones you looked at or played longest ago first, and fetches them from the camera again when you open them. It does not delete what is on screen, a video while it is open or a video still being copied.
- The debug log, when it is on (see below).

GR Lab reads your camera's Wi-Fi password from the camera over Bluetooth each time it connects and passes it to your phone's Wi-Fi system to join the camera's network. The password is not saved with your paired cameras. While debug logging is on, though, the password is written to the debug log on your phone, like the rest of the exchange with the camera (see below).

Photos and videos you download are saved to your phone's photo library, in an album called GR Lab: on iOS an album in Photos, on Android the GR Lab folder under Pictures. From then on they are yours and are managed by your photo app; GR Lab does not change or delete them.

The demo version of GR Lab uses a simulated camera with sample photos included in the app. It keeps its data apart from that of real cameras.

On Android, GR Lab turns off backup to your Google account. When you move to a new Android phone with a cable or Wi-Fi transfer, Android can still copy GR Lab's data, including the debug log, to the new phone. On iOS, GR Lab leaves all of its data out of your iCloud and computer backups.

## What GR Lab sends, and to whom

GR Lab communicates only with your camera:

- Over Bluetooth, to pair with the camera, find it nearby, wake it, turn on its Wi-Fi, read its Wi-Fi network name and password, work as a remote shutter with its shooting settings, and read and write the looks in its Custom slots C1 to C3. When pairing, GR Lab gives the camera your phone's name, which the camera shows in its list of paired devices. On Android this is the device name you set; on iOS it is the model, such as iPhone.
- Over the camera's own Wi-Fi network, to list, preview and download your photos and videos, show the camera's live view and shoot. These requests go only to the camera, at the address 192.168.0.1 on its network.

GR Lab makes no other network connections. It sends nothing to the developer or to third parties: no analytics, no usage statistics, no crash reports, no update checks and no advertising. Its fonts and license texts are included in the app.

## The debug log

The debug log helps find bugs. While it is on, GR Lab records every exchange with your camera in full, along with the app's own messages and errors. The log therefore contains your camera's serial number, its Bluetooth name and address, its Wi-Fi network name and password, the names, dates and sizes of the files on the camera and your phone's name. It does not contain your photos or videos.

Debug logging is off unless you turn it on, under Settings, Debug log, Enable debug logging. It is on by default only in GR Lab Dev, the test version of the app. The log is limited to about 50 MB; the oldest entries are deleted first.

The log stays on your phone. On iOS it is in GR Lab's app storage. On Android it is in GR Lab's folder under Android/data, which developer tools on a computer connected to the phone can also read. It is not in backups, except that Android can copy it when you transfer to a new phone (see above); clear the log first if you don't want that. Otherwise it leaves your phone only if you tap Export log and choose where to send it in the share sheet; the app you choose then handles it under its own terms. Because the log contains your camera's Wi-Fi password, share it only with someone you trust, such as the developer when you report a bug.

## Permissions

On Android, GR Lab asks for or uses:

- Nearby devices (Bluetooth scan and connect), to find, pair with and control your camera. GR Lab tells Android that it does not use Bluetooth scans to work out your location, and it does not ask for location access.
- Wi-Fi and network access, to join the camera's Wi-Fi network, which Android asks you to approve, to check that the phone is on it and to send the camera's traffic over it.
- Internet, which Android requires for any network connection. GR Lab uses it only to talk to the camera.

Saving photos and videos to Pictures needs no permission on the Android versions GR Lab runs on.

On iOS, GR Lab asks for:

- Bluetooth, to find, pair with, wake and control your camera.
- Local network, to talk to the camera over its Wi-Fi network.
- Photos, to save the photos and videos you download to the GR Lab album. iOS lets an app keep an album only with full access to your library, so that is what GR Lab asks for. It uses the access only to add what you download and to find the album named GR Lab; it does not look at, change or delete your other photos and videos. If you allow limited access or Add Photos Only instead, GR Lab still saves what you download, outside the album.
- Joining the camera's Wi-Fi network, which iOS asks you to approve. GR Lab also reads the name of the Wi-Fi network your phone is on, only to check that it has joined the camera.

GR Lab does not use your location, camera, microphone, contacts or notifications.

## Deleting your data

- Forget camera, on the camera's page under Cameras, removes the camera from GR Lab's paired cameras and deletes what GR Lab keeps about it: the cached file list, thumbnails, previews and videos of that camera, its downloads still waiting and the record of its files you saved. Photos and videos you saved to your photo library stay there, and so do your saved looks, including those saved from that camera. The debug log is not changed; Clear log deletes it. Your phone's Bluetooth settings may still list the camera, and the camera may still list your phone; you can remove those entries in the phone's Bluetooth settings and on the camera.
- Delete, in a saved look's menu under Looks, removes the look and its copy of the photo from your phone. Looks you loaded into the camera's Custom slots stay on the camera.
- Clear log, under Settings, Debug log, deletes the debug log from your phone.
- Uninstalling GR Lab deletes everything GR Lab keeps on your phone, including the debug log. Photos and videos you saved to your photo library stay there.

## Children

GR Lab is not directed at children. It sends no personal information about anyone, children included, to the developer or to third parties.

## Contact

If you have a question about this policy or about GR Lab, contact jeph, GR Lab's developer, by opening an issue in GR Lab's GitHub repository, jeph/gr-lab, at github.com/jeph/gr-lab.

## Changes to this policy

When GR Lab changes what it keeps on your phone, what it sends or the permissions it asks for, this policy is updated in the next version of the app and the date at the top changes.
