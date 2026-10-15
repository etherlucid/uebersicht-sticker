#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdbool.h>

/**
 * Checks whether any audio is currently actively playing through any unmuted
 * output audio device on macOS.
 *
 * Returns true if at least one audio output stream on an active device is running.
 */
static bool isAudioPlaying(void) {
    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 dataSize = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &prop, 0, NULL, &dataSize) != noErr) {
        return false;
    }

    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID devices[deviceCount];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &prop, 0, NULL, &dataSize, devices) != noErr) {
        return false;
    }

    for (UInt32 i = 0; i < deviceCount; i++) {
        AudioDeviceID dev = devices[i];

        // Ensure device has output streams
        AudioObjectPropertyAddress streamProp = {
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        UInt32 streamSize = 0;
        if (AudioObjectGetPropertyDataSize(dev, &streamProp, 0, NULL, &streamSize) != noErr || streamSize == 0) {
            continue;
        }

        // Check if device is muted
        AudioObjectPropertyAddress muteProp = {
            kAudioDevicePropertyMute,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        UInt32 isMuted = 0;
        UInt32 mSize = sizeof(isMuted);
        if (AudioObjectGetPropertyData(dev, &muteProp, 0, NULL, &mSize, &isMuted) == noErr && isMuted != 0) {
            continue;
        }

        // Check if device is running somewhere
        UInt32 isRunning = 0;
        UInt32 runSize = sizeof(isRunning);
        AudioObjectPropertyAddress runProp = {
            kAudioDevicePropertyDeviceIsRunningSomewhere,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        if (AudioObjectGetPropertyData(dev, &runProp, 0, NULL, &runSize, &isRunning) == noErr && isRunning != 0) {
            UInt32 sCount = streamSize / sizeof(AudioStreamID);
            AudioStreamID streams[sCount];
            if (AudioObjectGetPropertyData(dev, &streamProp, 0, NULL, &streamSize, streams) == noErr) {
                for (UInt32 s = 0; s < sCount; s++) {
                    UInt32 active = 0;
                    UInt32 aSize = sizeof(active);
                    AudioObjectPropertyAddress aProp = {
                        kAudioStreamPropertyIsActive,
                        kAudioObjectPropertyScopeGlobal,
                        kAudioObjectPropertyElementMain
                    };
                    if (AudioObjectGetPropertyData(streams[s], &aProp, 0, NULL, &aSize, &active) == noErr && active != 0) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

int main(void) {
    bool playing = isAudioPlaying();
    fputs(playing ? "1\n" : "0\n", stdout);
    return 0;
}
