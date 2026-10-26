#!/usr/bin/env bash
# Screenshots of the release build on an emulator, with sample data from TMDB (see Demo.kt).
set -x
APK="$1"
P=com.jm2kool.matinee
mkdir -p out
adb install -r "$APK"
adb shell settings put system screen_off_timeout 1800000
shot() { sleep "$1"; adb exec-out screencap -p > "out/$2.png"; }
launch() { adb shell am force-stop $P; adb shell am start -n $P/.MainActivity --ez preview true "$@"; }

launch --ez splash true; shot 0.9 00-splash-leader; shot 1.0 01-splash-brand
launch; shot 16 02-home
adb shell input swipe 540 1800 540 500 600; shot 3 02b-home-scrolled
adb shell input swipe 540 1800 540 300 600; shot 3 02c-home-scrolled-more
launch --es tab diary; shot 12 03-diary
launch --es tab library; shot 12 04-library
launch --es tab profile; shot 14 05-profile
adb shell input swipe 540 1800 540 400 600; shot 3 05b-profile-scrolled
launch --es tab search; shot 10 06-search
launch --es open show; shot 14 07-show
launch --es open show --ei scroll 1500; shot 18 08-show-scrolled
launch --es open show --ei scroll 3200; shot 18 09-show-episodes
launch --es open show2 --ei scroll 5200; shot 18 10-show-info
launch --es sheet log; shot 14 11-log
launch --es sheet quiz; shot 16 12-quiz
launch --es sheet shake; shot 14 13-random-pick
launch --es open list; shot 14 14-list-deck
launch --es sheet settings; shot 10 15-settings
adb logcat -d -b crash > out/crash.txt || true
adb logcat -d | grep -iE "matinee|AndroidRuntime|FATAL" | tail -300 > out/logcat.txt || true
ls -la out
