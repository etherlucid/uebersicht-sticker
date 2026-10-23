#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

/**
 * 1. Fast-path: Check real-time frequency bars from Cava if active.
 * When audio plays, cava produces non-zero FFT bars (0-100 scale).
 * Returns: peak bar value (0-100) if active, or -1 if unavailable/stale.
 */
static int getCavaPeakLevel(void) {
    struct stat st;
    if (stat("/tmp/cava_bars.txt", &st) != 0) return -1;
    time_t now = time(NULL);
    if (now - st.st_mtime > 3) return -1; // Cava inactive or stale

    FILE *f = fopen("/tmp/cava_bars.txt", "r");
    if (!f) return -1;
    char buf[512];
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return -1;
    }
    fclose(f);

    int maxVal = 0;
    char *p = buf;
    while (*p) {
        if (*p >= '0' && *p <= '9') {
            int val = 0;
            while (*p >= '0' && *p <= '9') {
                val = val * 10 + (*p - '0');
                p++;
            }
            if (val > maxVal) maxVal = val;
        } else {
            p++;
        }
    }
    return maxVal;
}

/**
 * 2. Medium-path: Check NowPlaying playback state file if recent.
 * When media is paused in Spotify, Apple Music, YouTube, etc., rate changes to 0 immediately.
 * Returns: 80 if actively playing music, 0 if paused, -1 if unavailable.
 */
static int checkNowPlayingLevel(void) {
    struct stat st;
    if (stat("/tmp/nowplaying_state.json", &st) != 0) return -1;
    time_t now = time(NULL);
    if (now - st.st_mtime > 4) return -1; // Stale

    FILE *f = fopen("/tmp/nowplaying_state.json", "r");
    if (!f) return -1;
    char buf[512];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    if (n == 0) return -1;
    buf[n] = '\0';

    char *rateStr = strstr(buf, "\"last_rate\":");
    if (rateStr) {
        rateStr += 12;
        while (*rateStr == ' ') rateStr++;
        if (*rateStr == '1') return 80;
        if (*rateStr == '0') return 0;
    }
    return -1;
}

/**
 * 3. Fallback: Check CoreAudio hardware output streams across all active devices.
 * Returns true if an unmuted output device has an active output stream running.
 */
static bool isCoreAudioPlaying(void) {
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

int main(int argc, char *argv[]) {
    int level = 0;

    int cava = getCavaPeakLevel();
    if (cava != -1) {
        level = cava;
    } else {
        int np = checkNowPlayingLevel();
        if (np != -1) {
            level = np;
        } else {
            level = isCoreAudioPlaying() ? 40 : 0;
        }
    }

    if (argc > 1) {
        int threshold = atoi(argv[1]);
        if (threshold <= 0) threshold = 20;
        fputs(level >= threshold ? "1\n" : "0\n", stdout);
    } else {
        printf("%d\n", level);
    }
    return 0;
}
