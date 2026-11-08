# JBL One app teardown (BandBox-relevant findings)

Everything here comes from **static decompilation of the JBL One Android app**, not from
a device-firmware image. The on-device firmware was never downloaded (see *Firmware /
OTA pipeline* for how it could be). The app is actually the richer source for the control
protocol: it ships named Kotlin/Java classes for the whole "V5" BLE command set that
[protocol-notes.md](protocol-notes.md) reverse-engineers byte-by-byte. A device firmware
image would mainly add the DSP audio routing and the USB-descriptor layout, neither of
which is in the app.

## Provenance / how to reproduce

- **App:** JBL One `com.jbl.oneapp`, versionName **2.8.4** (versionCode 2026091118,
  built 2026-09-11), minSdk 29 / targetSdk 36. Internal build tag seen in classes:
  `hkoneRelease_2.8.1_2026-09-11`.
- **Obtained** from Google Play via an Android emulator (the app is JBL-signed, not a
  third-party mirror). Pulled with `adb pull $(adb shell pm path com.jbl.oneapp)`.
- **Decompiled** with `jadx`. Package names in the decompile are rewritten to
  `com.widget.*`; the original is `com.harman.*` (both appear — jadx remapped most code to
  `com.widget` while string literals keep `com.harman`). The BandBox is internally called
  **"PartyBand"** and the Trio variant **"Trio"** (Solo is the other variant).
- Emulator/tooling details for next time are in Claude's memory (`jbl-one-app-protocol-map`).

## The V5 BLE command set = your property IDs, named

`com.harman.v5protocol.bean.devinfofeat.V5DevInfoFeatID` is an enum of **182 features**,
each `(name, id, valueSize, payloadClass)`. The `id` is the same u16 property ID used in
the GET/SET/EVENT records in [protocol-notes.md](protocol-notes.md); `valueSize` is the
payload length (`var` = variable). Each feature's byte encoding is in the sibling
`V5<Name>.java` bean (`fromPayload` / `valuePayload`). IDs below are hex.

This is the decoder ring for the whole protocol. Cross-references to the hand-captured
notes are in *Confirmations & corrections*.

### Complete feature-ID table (182 entries, sorted by ID)

| Hex | Dec | Feature | Bytes | Payload class |
|-----|-----|---------|-------|---------------|
| 0x0000 | 0 | UnsupportedFeatureList | var | V5UnsupportedFeatureList |
| 0x0002 | 2 | HeartBeat | 0 | V5HeartBeat |
| 0x0006 | 6 | DeviceName | var | V5DeviceName |
| 0x0008 | 8 | LeftSerialNumber | var | V5LeftSerialNumber |
| 0x000A | 10 | DeviceMacAddress | 6 | V5DeviceMacAddress |
| 0x000C | 12 | FirmwareVersion | 14 | V5FirmwareVersion |
| 0x000D | 13 | LeftDeviceBatteryStatus | 1 | V5LeftDeviceBatteryStatus |
| 0x000E | 14 | RightDeviceBatteryStatus | 1 | V5RightDeviceBatteryStatus |
| 0x000F | 15 | FactoryReset | 0 | V5FactoryReset |
| 0x0011 | 17 | ManualPowerOff | 2 | V5ManualPowerOff |
| 0x0012 | 18 | AutoPowerOff | 2 | V5AutoPowerOff |
| 0x0013 | 19 | AutoStandby | 2 | V5AutoStandby |
| 0x002E | 46 | BLEPairedStatusEcho | 1 | BLEPairedStatus |
| 0x0031 | 49 | SyncTimeFeature | 16 | V5SyncTimeFeature |
| 0x003A | 58 | AuthenticateMode | 1 | V5AuthenticateMode |
| 0x003B | 59 | AuthenticateButtonIsPressed | 1 | V5AuthenticateButtonIsPressed |
| 0x0045 | 69 | PowerStatus | 1 | V5PowerStatus |
| 0x004A | 74 | AuthenticationAlgorithm | 1 | V5AuthAlgorithm |
| 0x004B | 75 | AdvancedAuthenticateDevice | var | V5AdvancedAuthenticateDevice |
| 0x004F | 79 | ManualPowerOn | 2 | V5ManualPowerOn |
| 0x0056 | 86 | RemotePowerEnableStatus | 1 | V5RemotePowerEnableStatus |
| 0x0B80 | 2944 | AuracastAssistantInfo | var | V5AuracastAssistantInfo |
| 0x0B81 | 2945 | AuracastAssistantScanControl | 2 | V5AuracastAssistantScanControl |
| 0x0B82 | 2946 | AuracastAssistantGroupInfo | 41 | V5AuracastAssistantGroupInfo |
| 0x0B83 | 2947 | AuracastAssistantGroupSelection | var | V5AuracastAssistantGroupSelection |
| 0x0B84 | 2948 | AuracastAssistantSubgroupInfo | var | V5AuracastAssistantSubgroupInfo |
| 0x0B85 | 2949 | AuracastAssistantSubgroupPlay | 3 | V5AuracastAssistantSubgroupPlay |
| 0x0B86 | 2950 | AuracastAssistantBroadcasterEnable | 1 | V5AuracastAssistantBroadcasterEnable |
| 0x0B87 | 2951 | AuracastAssistantBroadcasterStart | 1 | V5AuracastAssistantBroadcasterStart |
| 0x0B88 | 2952 | AuracastAssistantBroadcasterPassword | 16 | V5AuracastAssistantBroadcasterPassword |
| 0x0B89 | 2953 | AuracastAssistantMacAddress | 6 | V5AuracastAssistantMacAddress |
| 0x0B8A | 2954 | AuracastAssistantBroadcasterName | var | V5AuracastAssistantBroadcasterName |
| 0x0B8B | 2955 | AuracastAssistantSubgroupName | var | V5AuracastAssistantSubgroupName |
| 0x0BA0 | 2976 | LEAudioStatusForV5Portable | 1 | V5LEAudioStatus |
| 0x0BA1 | 2977 | ActiveAudioSource | 1 | V5ActiveAudioSource |
| 0x0BA2 | 2978 | AudioSourceInfo | var | V5AudioSourceInfo |
| 0x0BA3 | 2979 | PairedBTDeviceList | var | V5PairedBTDeviceList |
| 0x0BA4 | 2980 | OperatePairedBTDevice | 7 | V5OperatePairedBTDevice |
| 0x0BA5 | 2981 | BTPairingMode | 2 | V5BTPairingMode |
| 0x0C00 | 3072 | MicConnectionStatus | 1 | V5PortableMicConnectionStatus |
| 0x0C05 | 3077 | EasySingMicEffect | 1 | V5EasySingMicEffect |
| 0x0C09 | 3081 | Mic1Echo | 1 | V5Mic1Echo |
| 0x0C0A | 3082 | Mic1Reverb | 1 | V5Mic1Reverb |
| 0x0C0B | 3083 | MicSensitivityInLevelFeature | 1 | V5MicSensitivityInLevelFeature |
| 0x0C0C | 3084 | Mic1SensitivityIndBFeature | 4 | V5Mic1SensitivityIndBFeature |
| 0x0C0D | 3085 | Mic2Echo | 1 | V5Mic2Echo |
| 0x0C0E | 3086 | Mic2Reverb | 1 | V5Mic2Reverb |
| 0x0C0F | 3087 | Mic2SensitivityInLevelFeature | 1 | V5Mic2SensitivityInLevelFeature |
| 0x0C10 | 3088 | Mic2SensitivityIndBFeature | 4 | V5Mic2SensitivityIndBFeature |
| 0x0C12 | 3090 | EasySingMicCount | 1 | V5EasySingMicCount |
| 0x0C14 | 3092 | EasySingMicGenerationQuery | 1 | V5EasySingMicGenerationQuery |
| 0x0C15 | 3093 | EasySingMicGenerationVersion | 2 | V5EasySingMicGenerationVersion |
| 0x0C16 | 3094 | EasySingMicBatteryQuery | 1 | V5EasySingMicBatteryQuery |
| 0x0C17 | 3095 | EasySingMicBattery | 2 | V5EasySingMicBattery |
| 0x0C1E | 3102 | IndividualMicVolumeQuery | 1 | V5IndividualMicVolumeQuery |
| 0x0C1F | 3103 | EasySingIndividualMicVolume | 2 | V5EasySingIndividualMicVolume |
| 0x0C30 | 3120 | EasySingMicDongleStatusQuery | 1 | V5EasySingMicDongleStatusQuery |
| 0x0C31 | 3121 | EasySingMicDongleStatus | 2 | V5EasySingMicDongleStatus |
| 0x0C40 | 3136 | FeedbackToneStatusForV5Portable | 1 | V5PortableFeedbackToneStatus |
| 0x0CB1 | 3249 | SleepSetting | 4 | V5SleepSetting |
| 0x0CB3 | 3251 | SleepCountDown | 4 | V5SleepCountDown |
| 0x0D00 | 3328 | LightingStatus | 1 | V5LightingStatus |
| 0x0D40 | 3392 | LightShow | 1 | V5LightShow |
| 0x0D41 | 3393 | LightBrightness | 1 | V5LightBrightness |
| 0x0D42 | 3394 | LightingTemperature | 1 | V5LightingTemperature |
| 0x0D43 | 3395 | LightingSpeed | 1 | V5LightingSpeed |
| 0x0D45 | 3397 | BassBoostLight | 1 | V5BassBoostLight |
| 0x0D46 | 3398 | LightColorPresets | 1 | V5LightColorPresets |
| 0x0D47 | 3399 | LightingCustomColor | 3 | V5LightingCustomColor |
| 0x0D48 | 3400 | LightingLoopInfo | 1 | V5LightingLoopInfo |
| 0x0D4A | 3402 | LightingEffectInfoList | var | V5LightingEffectInfoList |
| 0x0D4B | 3403 | LightingGroupID | 4 | V5LightingGroupID |
| 0x0D60 | 3424 | LightingEffectReset | 0 | V5LightingEffectReset |
| 0x0D61 | 3425 | LightingSunsetMode | 5 | V5LightingSunsetMode |
| 0x0D62 | 3426 | ChargingLight | 1 | V5ChargingLight |
| 0x0D80 | 3456 | RGBColorLooping | 4 | V5RGBColorLooping |
| 0x0E01 | 3585 | EqInfoQuery | 1 | V5EqInfoQuery |
| 0x0E02 | 3586 | EqInfo | var | V5EqInfoWrap |
| 0x0E7E | 3710 | EqInfoPortable | var | V5EqInfoPortableWrap |
| 0x0E7F | 3711 | EqSetPortable | var | V5SetEqPortableWrap |
| 0x0E80 | 3712 | SmartEQ | 1 | V5SmartEQ |
| 0x1008 | 4104 | TotalPlaybackTime | 4 | V5TotalPlaybackTime |
| 0x2004 | 8196 | AuracastMode | 1 | V5AuracastMode |
| 0x2005 | 8197 | AuracastStandardQuality | 1 | V5AuracastStandardQuality |
| 0x2006 | 8198 | PlaytimeBoost | 1 | V5PlaytimeBoost |
| 0x2007 | 8199 | MoodSound | 1 | V5MoodSound |
| 0x2009 | 8201 | BassBoost | 1 | V5BassBoost |
| 0x200A | 8202 | USBStatusFeature | 1 | V5USBStatusFeature |
| 0x200B | 8203 | AIVocalRemoval | 1 | V5AIVocalRemoval |
| 0x200F | 8207 | FeedbackToneStatus | 1 | V5FeedbackToneStatus |
| 0x2011 | 8209 | IdentifyDevice | 1 | V5IdentifyDevice |
| 0x2C00 | 11264 | PartyStatus | 1 | V5PartyStatus |
| 0x2C01 | 11265 | PartyGroupType | 1 | V5PartyGroupType |
| 0x2C02 | 11266 | PartyConnectionStatus | 1 | V5PartyConnectionStatus |
| 0x2C03 | 11267 | PartyRole | 1 | V5PartyRole |
| 0x2C04 | 11268 | PartyChannelType | 1 | V5PartyChannelType |
| 0x2C05 | 11269 | PartyGroupName | 16 | V5PartyGroupName |
| 0x2C06 | 11270 | PartyGroupID | 4 | V5PartyGroupId |
| 0x2C07 | 11271 | PartyGroupAction | 1 | V5GroupAction |
| 0x2C80 | 11392 | LLSConnectionStatus | 1 | V5LLSConnectionStatus |
| 0x2C81 | 11393 | PartyPartnerMacAddress | 6 | V5PartyPartnerMacAddress |
| 0x2D00 | 11520 | EasySingKaraokeBass | 1 | V5EasySingKaraokeBass |
| 0x2D01 | 11521 | EasySingKaraokeTreble | 1 | V5EasySingKaraokeTreble |
| 0x2D02 | 11522 | EasySingKaraokeEcho | 1 | V5EasySingKaraokeEcho |
| 0x2D40 | 11584 | AudioOperation | 1 | V5AudioOperation |
| 0x2D41 | 11585 | AudioMuteStatus | 1 | V5AudioMuteStatus |
| 0x2D42 | 11586 | AudioVolume | 1 | V5AudioVolume |
| 0x2D43 | 11587 | SongName | var | V5SongName |
| 0x2D44 | 11588 | ArtistName | var | V5ArtistName |
| 0x2D47 | 11591 | AudioContentDetected | 1 | V5AudioContentDetected |
| 0x3000 | 12288 | DrumStartEnd | 1 | V5DrumStartEnd |
| 0x3001 | 12289 | DrumTempo | 1 | V5DrumTempo |
| 0x3002 | 12290 | DrumSequence | 1 | V5DrumSequence |
| 0x3003 | 12291 | DrumTap | 0 | V5DrumTap |
| 0x3040 | 12352 | MetronomeStartEnd | 1 | V5MetronomeStartEnd |
| 0x3041 | 12353 | MetronomeTempo | 1 | V5MetronomeTempo |
| 0x3042 | 12354 | MetronomeSequence | 1 | V5MetronomeSequence |
| 0x3043 | 12355 | MetronomeTap | 0 | V5MetronomeTap |
| 0x3080 | 12416 | AIStemSeparationKaraokeMode | 1 | V5AIStemSeparationKaraokeMode |
| 0x3081 | 12417 | AIStemSeparationTrackType | 2 | V5AIStemSeparationTrackType |
| 0x3082 | 12418 | AIStemSeparationTrackVolume | 2 | V5AIStemSeparationTrackVolume |
| 0x3083 | 12419 | AIStemSeparationTrackTypeQuery | 1 | V5AIStemSeparationTrackTypeQuery |
| 0x3084 | 12420 | AIStemSeparationTrackVolumeQuery | 1 | V5AIStemSeparationTrackVolumeQuery |
| 0x3085 | 12421 | AIStemSeparationMode | 1 | V5AIStemSeparationMode |
| 0x30C0 | 12480 | PitchStartEnd | 1 | V5PitchStartEnd |
| 0x30C1 | 12481 | PitchChange | 1 | V5PitchChange |
| 0x3100 | 12544 | TunerStartEnd | 1 | V5TunerStartEnd |
| 0x3101 | 12545 | TunerMode | 1 | V5TunerMode |
| 0x3102 | 12546 | TunerBassMode | 1 | V5TunerBassMode |
| 0x3103 | 12547 | TunerTempo | 2 | V5TunerTempo |
| 0x3104 | 12548 | TunerString | 1 | V5TunerString |
| 0x3106 | 12550 | TunerResult | 10 | V5TunerResult |
| 0x3107 | 12551 | TunerChromaticTuning | 1 | V5TunerChromaticTuning |
| 0x3108 | 12552 | ChromaticTuningResult | 11 | V5ChromaticTuningResult |
| 0x3140 | 12608 | LooperRecordingOperation | 1 | V5LooperRecordingOperation |
| 0x3141 | 12609 | LooperMusicSignalReportIntervalFeature | 2 | V5LooperMusicSignalReportIntervalFeature |
| 0x3142 | 12610 | LooperMusicSignalFeature | 4 | V5LooperMusicSignalFeature |
| 0x3143 | 12611 | LooperRecordTimeLengthFeature | 2 | V5LooperRecordTimeLengthFeature |
| 0x3144 | 12612 | AudioDataTrimmingFeature | 4 | V5AudioDataTrimmingFeature |
| 0x3145 | 12613 | LooperRecordPlayOperation | 1 | V5LooperRecordPlayOperation |
| 0x3146 | 12614 | LooperRecordPlayTimestamp | 2 | V5LooperRecordPlayTimestamp |
| 0x3147 | 12615 | LooperNumberOfBars | 1 | V5LooperNumberOfBarsFeature |
| 0x3148 | 12616 | LooperLayerCount | 1 | V5LooperLayerCount |
| 0x3149 | 12617 | LooperRecordCountDown | 2 | V5LooperRecordCountDown |
| 0x314A | 12618 | LooperRecordEstimatedTimeDuration | 4 | V5LooperRecordEstimatedTimeDuration |
| 0x314B | 12619 | LooperRecordTimeLeft | 4 | V5LooperRecordTimeLeft |
| 0x3180 | 12672 | OutputRecordStorageLocationFeature | 1 | V5OutputRecordStorageLocationFeature |
| 0x3181 | 12673 | OutputRecordingStartStopFeature | 1 | V5OutputRecordingStartStopFeature |
| 0x3182 | 12674 | OutputSeparateTracksEnableFeature | 1 | V5OutputSeparateTracksEnableFeature |
| 0x3186 | 12678 | OutputRecordFilePath | var | V5OutputRecordFilePath |
| 0x3187 | 12679 | OutputDirectMonitorMode | 1 | V5OutputDirectMonitorMode |
| 0x31C0 | 12736 | MasterControlEQInfoQuery | 1 | V5MasterControlEQInfoQuery |
| 0x31C1 | 12737 | MasterControlEQInfo | var | V5MasterControlEQInfo |
| 0x31C2 | 12738 | MicKeyboardEQInfoQuery | 2 | V5MicKeyboardEQInfoQuery |
| 0x31C3 | 12739 | MicKeyboardEQInfo | 14 | V5MicKeyboardEQInfo |
| 0x3400 | 13312 | ChannelInputStatusQuery | 1 | V5ChannelInputStatusQuery |
| 0x3401 | 13313 | ChannelInputStatus | 3 | V5ChannelInputStatus |
| 0x3402 | 13314 | GuitarPickupQuery | 1 | V5GuitarPickupQuery |
| 0x3403 | 13315 | GuitarPickup | 2 | V5GuitarPickup |
| 0x3404 | 13316 | AUXType | 1 | V5AUXType |
| 0x3405 | 13317 | ChannelVolumeQuery | 2 | V5ChannelVolumeQuery |
| 0x3406 | 13318 | ChannelVolume | 3 | V5ChannelVolume |
| 0x3407 | 13319 | AuxOutputMode | 1 | V5AuxOutputMode |
| 0x3440 | 13376 | GuitarPresetAllSimpleInfo | var | V5GuitarPresetAllSimpleInfoList |
| 0x3441 | 13377 | GuitarPresetSelectQuery | 1 | V5GuitarPresetSelectQuery |
| 0x3442 | 13378 | GuitarPresetSelect | 2 | V5GuitarPresetSelect |
| 0x3443 | 13379 | GuitarPresetInfoQuery | 1 | V5GuitarPresetInfoQuery |
| 0x3444 | 13380 | GuitarPresetInfo | var | V5GuitarPresetInfo |
| 0x3445 | 13381 | GuitarPresetSlotInfo | var | V5GuitarPresetSlotInfo |
| 0x3446 | 13382 | GuitarPresetOperation | var | V5GuitarPresetOperation |
| 0x3447 | 13383 | GuitarPresetOnProductList | var | V5GuitarPresetOnProductList |
| 0x3448 | 13384 | GuitarPresetMyFavoriteListQuery | 1 | V5GuitarPresetMyFavoriteListQuery |
| 0x3449 | 13385 | GuitarPresetMyFavoriteList | var | V5GuitarPresetMyFavoriteList |
| 0x344A | 13386 | GuitarPresetGenreList | var | V5GuitarPresetGenreList |
| 0x3800 | 14336 | PrepareOtaPath | 1 | V5PrepareOtaPath |
| 0x3801 | 14337 | DeviceOOBE | 1 | V5DeviceOOBE |
| 0x3802 | 14338 | BackwardScreen | 1 | V5BackwardScreen |
| 0x3803 | 14339 | PageInUseStatusQuery | 1 | V5PageInUseStatusQuery |
| 0x3804 | 14340 | PageInUseStatus | 2 | V5PageInUseStatus |
| 0x3805 | 14341 | BandBoxSupportedFeatureList | var | V5BandBoxSupportedFeatureList |
| 0x3806 | 14342 | MicBrandModelQuery | 1 | V5MicBrandModelQuery |
| 0x3807 | 14343 | MicBrandModel | 5 | V5MicBrandModel |

(The enum also defines `PrepareOtaPath` at 0x3800 and the OTA/DFU path; the AWS
`/otaUpdates` strings elsewhere in the app are an unrelated bundled SDK — see
*Firmware / OTA pipeline*.)

## Value encodings (enums and payloads)

Byte layouts for the beans that matter most. Each is from the bean's `fromPayload` /
`valuePayload`.

**Channels and inputs**
- `V5ChannelNumber`: `Master=0, CH1=1, CH2=2, CH3=3, CH4=4`
- `V5CHInputType`: `Unknown=0, Mic=1, Guitar=2, LineIn=3, AUX_INSTRUMENT=4`
- **ChannelVolume (0x3406)** = 3 bytes `[channelNumber, inputType, volume(0–32)]`.
  Confirms the notes' `(channel, input type)` key; `(0,*)` is Master.
- **ChannelInputStatus (0x3401)** = 3 bytes `[channelNumber, isDetected(0/1), inputType]`.
- **ChannelVolumeQuery (0x3405)** / **ChannelInputStatusQuery (0x3400)**: 1-param queries
  that make the device EVENT the matching status.

**Audio source / playback**
- `V5AudioSource`: `None=0, BT=1, AUX=2, USBFlashDisk=3, Optical=4, FMRadio=5, DABRadio=6,
  UAC=7, RCA=8, A2B=9, Coaxial=10, Auracast=16`. **UAC=7 is the USB-Audio-Class feed to a
  computer.**
- **ActiveAudioSource (0x0BA1)** = 1 byte, one of the above (the current music source).
- **AudioVolume (0x2D42)** = 1 byte 0–32: the music-playback source volume (BT/UAC/USB/AUX),
  *not* a per-channel volume. See the correction below.
- **AudioOperation (0x2D40)**: transport, `STOP=0, PAUSE=1, PLAY=2, PREV=3, NEXT=4,
  VOLUME_UP=5, VOLUME_DOWN=6`.
- **AudioMuteStatus (0x2D41)** = 1 byte `isMuted` (mutes the music source).
- **AudioContentDetected (0x2D47)**: `OFF=0, NO_AUDIO=1, MUSIC=2, VOCAL=3`.
- **AUXType (0x3404)**: `Instrument=1, Music=2` (what the 3.5 mm aux jack is treated as).

**Recording / output (see *Silent DI* below)**
- **OutputRecordStorageLocationFeature (0x3180)**: `StoreOnPhone=0, StoreOnFlashDriver=1,
  StoreOnPC=2`.
- **OutputRecordingStartStopFeature (0x3181)** = 1 byte start/stop.
- **OutputSeparateTracksEnableFeature (0x3182)**: `Disable=0, Enable=1` (multitrack USB).
- **OutputRecordFilePath (0x3186)** = string.
- **OutputDirectMonitorMode (0x3187)** = 1 byte `isOn` (`01`=on, `00`=off).
- **USBStatusFeature (0x200A)**: `Status NOT_INSERTED=0 / INSERTED=1` plus the `V5AudioSource`
  it enumerates as (UAC vs USBFlashDisk).
- **AuxOutputMode (0x3407)**: `SilentMode=0, MonitorMode=1`.

**Tuner**
- **TunerStartEnd (0x3100)** on/off; **TunerMode (0x3101)**: `Auto=0, String1..String6=1..6`;
  **TunerBassMode (0x3102)** on/off; **TunerString (0x3104)** selected string;
  **TunerResult (0x3106)** the live feed; **TunerChromaticTuning (0x3107)** +
  **ChromaticTuningResult (0x3108)** the chromatic variant.

**Guitar / pickup / stem / pitch**
- **GuitarPickup (0x3403)** `PickupTypeEnum: High=0, Low=1, Mid=2` — these are the internal
  names for what the UI shows as Single coil / Active / Passive humbucker.
- **AIStemSeparationTrackType (0x3081)** `Nothing=0, Guitar=1, Vocal=2, Drum=3, Bass=4`;
  **AIStemSeparationMode (0x3085)** on/off; **AIStemSeparationKaraokeMode (0x3080)** on/off;
  **AIStemSeparationTrackVolume (0x3082)**.
- **PitchChange (0x30C1)** signed semitones; **PitchStartEnd (0x30C0)** active flag.

**Model identity / OOBE**
- **DeviceOOBE (0x3801)** carries `SoloMusicianEnum: RESET=0, GUITARIST=1,
  GUITAR_VOCALIST=2, SINGER=3` — the Solo's "which musician" setup. (Trio uses the full
  4-channel model instead.)
- **PageInUseStatus (0x3804)** = 2 bytes `[page, state]` — the app tells the device which
  screen is open. This is the notes' `SET 0x3804 = 01 02 / 01 00` around tuner start/stop.

### BandBox capability bitmap — decode of your captured 0x3805

`BandBoxSupportedFeatureList (0x3805)` is a list of 1-byte capability IDs
(`BandboxSupportFeatureEnum`):

| ID | Capability | ID | Capability |
|----|-----------|----|-----------|
| 1 | ChromaticTuning | 8 | Stereo |
| 2 | Drum | 9 | UkuleleTuner |
| 3 | LooperDrumMode | 10 | Looper |
| 4 | LooperMetronomeMode | 11 | ThreeLevelGuitarGain |
| 5 | OutputPhoneMode | 12 | AITrackTypeOfBass |
| 6 | OutputUsbDriveMode | 13 | **OutputPC** |
| 7 | Scales | 14 | **AuxOutSetting** |

The Trio value captured in the notes — `01 02 03 04 05 06 09 0a 0b 0d` — therefore decodes
as: ChromaticTuning, Drum, LooperDrumMode, LooperMetronomeMode, OutputPhoneMode,
OutputUsbDriveMode, UkuleleTuner, Looper, ThreeLevelGuitarGain, **OutputPC**. It does **not**
include Scales(7), Stereo(8), AITrackTypeOfBass(12) or **AuxOutSetting(14)**. That is a
concrete, device-specific fact that shapes the DI options below.

## Silent DI — "record to the computer, keep the speaker quiet"

Background: a true dry+wet split isn't possible; "dry" means selecting the **Bypassed**
tone. "Silent" is a separate lever. The decompile shows these candidates, all plain writes
over the existing BLE link (no firmware flash, no extra hardware):

1. **OutputDirectMonitorMode (0x3187)** — best candidate. 1-byte `01`/`00`. It is the
   "direct monitor" toggle on the app's **Output/recording** screen
   (`com.harman.partyband.output.OutputViewModel`), where recording targets the **PC over
   UAC** (`StoreOnPC`, source `UAC`). The write is literally
   `new V5OutputDirectMonitorMode(isEnable)`. Turning direct monitor **off** is the normal
   interface way to stop the device playing the live input through its own speaker while the
   USB record continues. Your captured 0x3805 includes **OutputPC**, so PC recording is
   supported on the Trio.
2. **AuxOutputMode (0x3407) = SilentMode(0)** — the "silent practice" mode. **Caveat:** this
   is gated by capability **AuxOutSetting(14)**, which is **absent** from your captured
   0x3805, so this mode is probably **not available** on the Trio firmware you have. Worth a
   GET to confirm, but don't count on it.
3. **AudioMuteStatus (0x2D41)** mutes the music-playback source, not the instrument channels,
   so it doesn't help here.
4. **Master volume** (ChannelVolume `0x3406` with channel `Master=0`) and the per-channel
   volumes all sit *before* whatever the USB feed taps, most likely, so turning them down
   would quiet the recording too — not a silent-DI lever on their own.

**Still needs a hardware test** (the app proves the controls exist and their byte encoding;
it does not prove the DSP routing): set `0x3187 = 00` with the BandBox connected and watch
the Mac's input meter — if the speaker goes quiet while the UAC level holds, that's the
silent DI. Then a Stagehand "silent DI" switch = select Bypassed + `SET 0x3187 = 00`.

## Confirmations & corrections to protocol-notes.md

The app's names line up with the hand-captured IDs and resolve several unknowns. High-value
items:

**Corrections**
- **0x2d42 is `AudioVolume`**, the music-playback source volume (BT/USB/UAC/AUX), *not*
  "channel 4 volume." Per-channel volumes (including CH4) use `0x3406` with the channel-number
  byte; `(04 04)` in 0x3406 is channel 4 / AUX_INSTRUMENT input.
- **0x0c0c / 0x0c10** (the "unknown float32" per channel) are **Mic1/Mic2 SensitivityIndB**
  (mic sensitivity in dB). The empty neighbours **0x0c0b / 0x0c0f** are the same in "level"
  form (`Mic1/Mic2 SensitivityInLevel`).
- **0x0c09 / 0x0c0d** ("mic delay") are **Mic1Echo / Mic2Echo**; **0x0c0a / 0x0c0e** are
  **Mic1Reverb / Mic2Reverb** (echo, not delay).
- **0x3101 / 0x3102 / 0x3104** (the tuner "readings = 0") are the tuner **Mode**
  (Auto/String1–6), **BassMode**, and **String**; **0x3107** is **ChromaticTuning** (with
  result at 0x3108). The live feed is 0x3106 (`TunerResult`), as already decoded.
- **0x3448 / 0x3449** are the **My Favorite** preset list (`GuitarPresetMyFavoriteList`), not
  the speaker's hardware preset buttons.

**Newly named (were "read once on connect; unknown")**
- 0x0ba1 = `ActiveAudioSource`, 0x3404 = `AUXType`, 0x3407 = `AuxOutputMode`,
  0x3145 = `LooperRecordPlayOperation`, 0x3148 = `LooperLayerCount`, 0x3000 = `DrumStartEnd`,
  0x3040 = `MetronomeStartEnd`, 0x2c00–0x2c05 = `Party*`, 0x000c = `FirmwareVersion`
  (14-byte form; distinct from the 2-byte 0x0004 the notes already record), 0x1008 =
  `TotalPlaybackTime`.
- 0x3804 (noted as "tuner UI mode/page") = `PageInUseStatus` `[page, state]` — the app marks
  which screen is open; 0x3803 is its query.

**Confirmations** (app name = captured meaning): 0x0002 HeartBeat, 0x0006 DeviceName,
0x0008 Serial, 0x000a MAC, 0x000d Battery, 0x0031 SyncTime, 0x3100 Tuner on/off,
0x3106 tuner feed, 0x3400/0x3401 channel input status, 0x3402/0x3403 pickup,
0x3405/0x3406 channel volume, 0x31c2/0x31c3 mic/keyboard EQ, 0x3080–0x3085 AI stem
separation, 0x30c0/0x30c1 pitch, 0x3440–0x344a guitar-preset family, 0x3805 capability list.

## Firmware / OTA pipeline (how to actually get a firmware image)

The real device-firmware path (not the AWS-SDK red herring):

- **Check endpoint:** `GET https://storage.lscloud.harman.com/pb-ota-prod/ota-config`
  with header `x-api-key: <app key>` and query `?pid=<product id>&current_fw_version=<ver>`.
  Interface `com.widget.http.n0`; base URL set in `ApiClient` (`pb` = PartyBox/PartyBand).
- **Response** `OtaConfig` (wrapped with a `baseUrl`) is turned into a `RemoteUpdateModel`
  with: `remoteUrl` (the firmware **.bin** URL), `md5`, `releaseVersion`, `whatsNewMap`
  (changelog per language), and `wirelessMicTargetVersion` (a separate OTA image for the
  EasySing wireless mic).
- **Apply:** the app downloads the bin to `filesDir/Firmware/`, verifies md5, then streams it
  to the device over BLE: `PrepareOtaPath (0x3800)` then the GATT DFU flow
  (`com.harman.command.*.gatt.ota.*`: `ReqDfuStart/SetDfuData/Apply/Cancel`).
- So a firmware image can be fetched without waiting for an OTA: call `ota-config` with the
  Trio's `pid` and a low `current_fw_version`, read `remoteUrl`, download the bin. The
  `x-api-key` is embedded in the app (`assets/api_key.txt`); it's not reproduced here.
- Latest Trio release seen publicly: 25.28.41.50.00 (July 2025).

## Cloud endpoints and services

Hosts the app talks to (base URLs from `ApiClient`):
- `https://apis.onecloud.harman.com/` — main OneCloud API. Interface `o0` paths incl.
  `oneapp/v1|v2/content/*` (product-support-list, product-usage, marketing/product-banner),
  `apps/v1/auth/*` (login, refresh, logout, reset-password, check-existence),
  `apps/v1/customers/*` (+ `registered-products`), `apps/v1/feature-flags`,
  `apps/v1/diagnosis/initiate`, `apps/v1/current-location`, `apps/v1/marketing/campaigns`.
  Auth is `x-api-key` for content and `customer-token` for account calls.
- `https://storage.lscloud.harman.com/pb-ota-prod/` — firmware OTA config/binaries.
- `https://appstorage.onecloud.harman.com/` — static content (legal/privacy, deeplinks,
  guides); dev/stage variants exist.
- `https://bluetooth-events.onecloud.harman.com/` — analytics/telemetry.
- Music-service SDKs are bundled (Napster/Rhapsody, iHeart, TuneIn, Amazon Alexa,
  Chromecast) but are generic JBL-One speaker features, unrelated to BandBox.

## App architecture / other BandBox features

- **UI split.** Native screens under `com.harman.partyband.*`: `tuner`, `output` (recording),
  `guitarpreset`, plus a debug screen (`PartyBandDebugActivity`). The main mixer/tools UI is
  a **WebView** driven by `com.harman.webview.models.PartyBandHybridViewModel` through a JS
  bridge (`Js*` classes: `JsBandBoxModelInfo`, `JsBandBoxToolsStatus`, `JsBandBoxMicInfo`,
  `JsSetBandBoxModelInfo`, …). `BandBoxDevState` is the full device-state snapshot the bridge
  serialises to the web layer — a good map of what the Trio exposes (master volume, per-
  channel status/volume, aux type, master EQ, supported features, aux-output mode).
- **Tools** (all in the ID table): Drum machine (0x3000–0x3003), Metronome (0x3040–0x3043),
  Looper (0x3140–0x314b, incl. record/play, layer count, bars, countdown, time-left),
  AI Stem Separation (0x3080–0x3085), Pitch shift (0x30c0/0x30c1), Tuner incl. chromatic and
  ukulele, Output recorder (phone/USB-drive/PC, separate tracks, direct monitor).
- **EQ.** Master EQ (`EqInfo` 0x0e02 / query 0x0e01), portable EQ (0x0e7e/0x0e7f), SmartEQ
  (0x0e80), Master-control EQ (0x31c0/0x31c1), Mic/Keyboard EQ (0x31c2/0x31c3).
- **EasySing wireless mic.** A whole sub-family (0x0c05–0x0c31, 0x2d00–0x2d02, 0x3806/0x3807):
  mic count, generation, battery, dongle status, karaoke bass/treble/echo, brand/model — the
  Trio can pair JBL's wireless mics and OTA-update them separately.
- **Device authentication / anti-counterfeit.** `AuthenticateMode (0x3a)`,
  `AuthenticationAlgorithm (0x4a)`, `AdvancedAuthenticateDevice (0x4b)`, and a bundled
  `com.jbl.counterfeit.library` — the app runs a challenge/response to verify the speaker is
  genuine. Not required for the control protocol (Stagehand already drives the device without
  it), but it's why some `Authenticate*` IDs appear on connect.
- **Power/standby:** ManualPowerOn/Off (0x4f/0x11), AutoPowerOff (0x12), AutoStandby (0x13),
  PowerStatus (0x45), RemotePowerEnableStatus (0x56). **FactoryReset = 0x0f** (0-byte).

## Embedded credentials / assets (noted, not extracted)

`assets/` contains `api_key.txt` (the OneCloud `x-api-key`), and `alice.p12` /
`client.pkcs12` / `certificate_new` / `certificate_old` (client certs / keystores used for
the API and/or device authentication). Their contents are intentionally **not** reproduced
here. Lottie JSON animations for onboarding/calibration and the EULA/privacy HTML are also
in `assets/`.

## What this teardown does NOT cover

- The **device firmware image itself** (DSP audio routing, exact USB descriptors). The app
  can't show how the speaker internally routes dry vs processed audio to USB; that lives in
  firmware. The *Firmware / OTA pipeline* section is the route to obtain it if wanted.
- **Runtime confirmation.** Everything here is static. Byte encodings are from the beans;
  which features a given Trio firmware actually honours is confirmed only by the device
  (e.g. the 0x3805 capability list, and the silent-DI hardware test above).
