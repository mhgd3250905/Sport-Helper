# SmartFit Privacy Policy — 1.0 release candidate text

Policy date: 24 October 2026. Android application: `com.ugk.smartfit`, intended candidate `1.0.0+25`. Public policy entry: https://smartfit-store.pages.dev/privacy/en/ . This repository text does not establish that build25 has been built, verified, or released.

Service name: **SmartFit**. Developer display name: **Bboy Ug1yk**; this does not infer a legal entity name. Privacy and support: **mhgd3250905@gmail.com**. The public site has been deployed. Build25 declares collection and sharing for the network-data scope below; the release receipt records final-package verification and actual Console saving.

## Scope

This candidate retains the accepted version's original conversational home, exercise library, plans, local rules and fallback behavior, workout player, and settings. No account is required. Existing AI entrances, prompts, and memory settings remain visible. This build has no injected API key, so it does not enable online AI requests. Some online paths may remain unavailable; this candidate does not redesign those entrances. There is no advertising, behavioral analytics, or remote crash reporting service.

## Information processed on your device

The app stores plans, titles and dates, durations, completion counts and session results, safety-check completion and restriction states, preferences, and local playback files. It also retains recent conversations, training conditions, a locally generated device UUID, memory settings, and any existing local AI memories. The UUID and memories are not sent through AI requests when the key is empty. These data support the original conversation, local planning, workout, history, safety, and settings functions.

The safety conversation asks about pregnancy/postpartum status, recent surgery or exercise restrictions, acute injury, and cardiovascular risks. In addition to the final safety states, the original conversation log may retain questions and your selected answers. It is not accurate to say that only two boolean values are stored. There are no enabled AI requests in this candidate, but local records may be included in system backup or device transfer as explained below.

The app does not collect movement or health measurements through the camera, microphone, location, health platforms, or body sensors. It does not automatically recognize posture. Workout completion information comes from the local player workflow.

## Network access and components

No API key is injected. Public AI addresses already in the original code remain unchanged; an address is not a secret and does not create an AI request without a key. Video playback uses an on-device loopback service at `127.0.0.1` / `localhost` to serve media to the system WebView. Loopback playback does not itself send workout records to the internet.

Some demonstrations are built in. Other demonstrations can be downloaded over HTTPS from Cloudflare delivery at the base `https://smartfit-media.pages.dev/v0.3.0-app/` and used after byte-length and SHA checks. A request exposes an IP address, request time, requested media path, and ordinary HTTP metadata such as a User-Agent to the network service. A media path may contain an exercise identifier, so the service can observe which demonstration was requested. The app does not attach its local device UUID, conversations, safety answers, full plans or workout records, or AI memories to these media requests. The system network stack may also send normal protocol metadata.

Cloudflare may process or retain network data for delivery, caching, security, abuse prevention, and service operation under its service and privacy rules. We do not promise that there are no access logs, that all request data is processed only ephemerally in memory, or an unverified fixed retention period. Public policy and support pages are also hosted on Cloudflare and generate normal website requests when opened. See [Cloudflare’s Privacy Policy](https://www.cloudflare.com/privacypolicy/). These network data support content delivery and fraud prevention, security, and compliance. We do not use the IP address to infer your location.

The app uses Flutter, the system WebView, UGK training components, local preference storage, and audio components. It has no advertising or behavioral analytics SDK. The original default Android backup configuration is retained. Depending on Android version, account, user settings, and device rules, the system may back up eligible preferences and app files to the user's platform backup service or transfer them to another device. Data may therefore leave the current device. This policy does not promise that backup is disabled or that all data always stays on-device. Backup encryption, retention, restoration, and deletion follow the relevant platform's rules.

## Use and sharing

App records support the conversation, planning, workout, history, safety, and settings functions. This candidate does not enable AI requests sending those records, and does not sell them. Cloudflare media and policy-page requests generate the network data described above; system backup or device transfer may also transfer app data. An empty API key is not a promise that every data path is exclusively on-device.

If you choose to email support, we use the address, message, and attachments you provide to address your request. Do not send passwords, keys, or unnecessary health information. This is an external email initiated by you, not an automatic app upload. You may ask the support address to delete information you supplied by email after the matter is resolved, subject to any applicable legal or necessary security-record retention requirements.

## Permissions

`INTERNET` permits on-device loopback playback, HTTPS media downloads, and public policy pages. `ACCESS_NETWORK_STATE` supports connectivity and Wi-Fi download preferences. The verified build24 manifest declares `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, and `WAKE_LOCK` through the fixed UGK training component’s media playback foreground service. Build25 keeps that component; its actual merged AAB manifest remains the final inventory.

After you start a workout, the training service supports local spoken guidance, chimes, and session timing when the screen is locked or the activity is in the background. The component creates a continuing training notification and a system media session, and holds a time-bounded CPU wake lock during the session; the training page also keeps the screen awake. You can return to the app to pause or end the workout. The service is released at completion, allowing a short closing-audio tail, or when the player is left or disposed. It also stops when the app task is removed. Pausing or muting does not necessarily stop the service immediately: it may remain for the current workout session.

These capabilities support local workout playback and execution. They do not record the microphone or read body sensors, and the foreground service itself does not upload workout records. Separate media downloads still generate the network data described above. The notification's display follows Android rules. There are no advertising or full-screen notification permissions. System backup is a separate platform data path. The signed AAB's merged manifest is the definitive permission and service inventory.

This release does not request runtime access to the camera, microphone, location, contacts, photo library, broad file storage, activity recognition, body sensors, health platforms, advertising identifiers, or notifications.

## Retention, deletion, and protection

Records and preferences remain in this device's app-specific storage until you clear the app's storage or uninstall it. Showing only recent history does not mean older underlying session records have been deleted. Clearing media cache does not delete workout history or safety states.

There is no developer-provided cloud account or workout sync database, and the developer cannot remotely delete device records. Android's app settings can clear local storage, and uninstalling removes local app data. Starting a new conversation and clearing memory affect those respective data only, not every workout record. Check what you need to keep first. Clearing or uninstalling the app does not guarantee deletion of platform backups. Manage those copies through the device or platform backup settings; reinstalling the app may restore previously backed-up data.

We use operating-system app isolation and app-specific storage. Device unlocking, manual copies, rooted devices, and changes to operating-system security are outside the app's control. No storage or communication method can provide absolute security.

## Fitness use and minors

SmartFit is for general fitness demonstrations. It is not a medical device and does not diagnose, treat, cure, or prevent any medical condition. The intended audience is teenagers aged 13 and above and adults; the app is not designed for children under 13. Minors should follow their guardian’s and qualified professionals’ guidance. A content rating and a target-audience selection are different matters, and do not establish that every exercise is suitable for everyone. Consult a qualified professional before exercise if you have pregnancy/postpartum, injury, surgery, chronic illness, or other exercise-related risks.

## Updates and contact

If features or data practices change, the policy and effective date will be updated. Contact **mhgd3250905@gmail.com** with privacy, local-data, or support questions.
