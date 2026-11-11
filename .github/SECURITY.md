# Security Policy

## Supported versions

GR Lab is in early development and has no packaged releases yet. Security fixes land on the `dev`
branch, so only its latest commit is supported.

| Version | Security updates |
| --- | --- |
| Latest commit on `dev` | Supported |
| Older commits and builds made from them | Not supported |

Before reporting a problem, reproduce it with a build of the latest `dev` commit when it is safe to
do so.

## Reporting a vulnerability

Do not disclose suspected vulnerabilities in a public issue, discussion, pull request, or social
media post. Submit a
[private vulnerability report](https://github.com/jeph/gr-lab/security/advisories/new) instead.

Include enough information to investigate without exposing private data:

- The GR Lab commit, the build (`dev` or `prod`), your phone model and its Android or iOS version.
- The camera model and firmware version, if a camera is involved.
- The security impact and who could exploit it.
- Minimal reproduction steps or a proof of concept. Demo mode, which runs against the simulated
  camera, is enough for many problems.
- Sanitized logs or screenshots, if relevant.
- Any suggested mitigation or fix.

Never include your camera's Wi-Fi password, its serial number, its Bluetooth or Wi-Fi address or
network name, or your photos. GR Lab's debug log holds all of those except the photos, so remove
them from any part of the log you send. The maintainer will not ask you for them.

Reports will be assessed privately. If the report is accepted, the maintainer will coordinate a fix
and public disclosure as appropriate. Please allow time to investigate before publishing details.
Reporters can be credited in a published advisory if they want attribution.

## In scope

Examples of security issues in GR Lab include:

- GR Lab sending anything to a destination other than the camera, or keeping or sharing data beyond
  what its [privacy policy](../app/assets/privacy.md) describes.
- The camera's Wi-Fi password, the debug log or other app data becoming readable by another app, a
  backup or the network in a way the privacy policy does not describe.
- A way to make GR Lab join a network, or talk to a device, that is not the paired camera.
- A file name, file list, image, look or other response from a camera, or from a device posing as
  one, that makes GR Lab read, write or delete files outside its own storage and its album, or run
  code.
- Another app on the phone controlling GR Lab or a camera through it.
- Build, signing or packaging issues that could allow code substitution.

## Out of scope

The following are not vulnerabilities in this project by themselves:

- How the camera itself works: its Bluetooth pairing, its Wi-Fi network, and its HTTP interface,
  which is unencrypted and open to any device on the camera's network. That is Ricoh's firmware, and
  GR Lab cannot change it.
- The debug log holding the camera's Wi-Fi password and identifiers while debug logging is on, and
  whatever an exported log reveals to the person it was shared with. The privacy policy describes
  both.
- The simulated camera and demo mode, which are test tools with sample data.
- What `research/` documents about the camera's protocol and firmware.
- Social engineering or phishing that does not exploit GR Lab.
- Vulnerabilities that require root or jailbreak access, a compromised phone, or a user
  intentionally giving an attacker access to an unlocked phone.

Vulnerabilities in the camera's firmware, Ricoh's apps, Android, iOS or Flutter are outside this
project's control and should be reported through their own security processes. You may also notify
this project privately when a GR Lab-side mitigation could protect its users.

## Safe research

- Test only with cameras, phones and data you own or have explicit permission to use.
- Prefer demo mode and an emulator or simulator over your everyday phone and camera.
- Do not access, retain, or disclose another person's photos or data.
- Stop testing if you encounter data or access outside your authorization.
