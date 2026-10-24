# SmartFit Privacy Policy — Basic 1.0 draft

Proposed effective date: 24 October 2026. Android application: `com.ugk.smartfit`, version `1.0.0+23`.

Operator: **publisher name matching the Google Play account, to be supplied by the owner**. Privacy and support contact: **mhgd3250905@gmail.com**. This draft has not been published at a public URL. Complete the operator name and verify the final candidate before publishing it as the effective policy.

## Scope

SmartFit Basic provides exercise browsing, fixed workout routines, timed practice, and local workout results. It does not require an account. This release does not enable chat, online generation, cloud sync, advertising, behavioral analytics, or remote crash reporting. This policy describes this Basic release. Any future online functionality will require updated disclosures and any applicable choices before it is provided.

## Information processed on your device

The app stores workout plans, the last plan, workout titles and dates, durations, completion counts and session results, safety-check completion and training-restriction states, appearance and audio preferences, and local demonstration/playback files in app-specific storage. These support workout playback, recent results, safety restrictions, and your settings.

The safety check asks about pregnancy/postpartum status, recent surgery or exercise restrictions, acute injury, and cardiovascular risks. The app saves only whether the check is complete and whether training is restricted. It does not save individual answers or upload them.

The app does not collect movement or health measurements through the camera, microphone, location, health platforms, or body sensors. It does not automatically recognize posture. Workout completion information comes from the local player workflow.

## Network access and components

This Basic build has no online-generation key, configured AI service address, or remote demonstration source. It does not send workout records, plans, safety states, or a device identifier to a developer server. Video playback may use a loopback service at `127.0.0.1` / `localhost` to serve media to the system WebView. That traffic stays on the same device and is not an internet upload.

The app uses Flutter, the system WebView, UGK training components, local preference storage, and audio components for its interface, training, storage, and playback. The candidate has no advertising or behavioral analytics SDK. Android cloud backup and device-transfer backup are disabled by app configuration. Services provided separately by Google Play, the operating system, or the device manufacturer are governed by their respective policies.

## Use and sharing

Local information is used for training, history, safety restrictions, and preferences. This Basic release does not collect it on a developer server, share it with third parties, or sell it.

If you choose to email support, we use the address, message, and attachments you provide to address your request. Do not send passwords, keys, or unnecessary health information. This is an external email initiated by you, not an automatic app upload. You may ask the support address to delete information you supplied by email after the matter is resolved, subject to any applicable legal or necessary security-record retention requirements.

## Permissions

`INTERNET` permits the sockets needed for on-device loopback media playback. `ACCESS_NETWORK_STATE` allows the local media component to observe connectivity. Training/audio components may declare `WAKE_LOCK` to maintain necessary playback or screen behavior during a workout. The final signed AAB's merged manifest is the definitive permission inventory.

This release does not request runtime access to the camera, microphone, location, contacts, photo library, broad file storage, activity recognition, body sensors, health platforms, advertising identifiers, or notifications.

## Retention, deletion, and protection

Records and preferences remain in this device's app-specific storage until you clear the app's storage or uninstall it. Showing only recent history does not mean older underlying session records have been deleted. Clearing media cache does not delete workout history or safety states.

There is no cloud account or cloud workout database. The developer cannot remotely recover or delete records on your device. Use Android's app settings to clear storage, or uninstall the app, to remove local app data. Check whether you still need the records first. This release disables Android cloud and device-transfer backup and does not promise cross-device restoration.

We use operating-system app isolation and app-specific storage. Device unlocking, manual copies, rooted devices, and changes to operating-system security are outside the app's control. No storage or communication method can provide absolute security.

## Fitness use and minors

SmartFit is for general fitness demonstrations. It is not a medical device and does not diagnose, treat, cure, or prevent any medical condition. The publisher must confirm the intended audience and store age selections before submission; this draft does not claim a completed child-directed compliance assessment. Consult a qualified professional before exercise if you have pregnancy/postpartum, injury, surgery, chronic illness, or other exercise-related risks.

## Updates and contact

If features or data practices change, the policy and effective date will be updated. Contact **mhgd3250905@gmail.com** with privacy, local-data, or support questions.
