# RHVoice Android — Forced Direct Boot Migration Failure (Test Build)

**Branch:** `android-direct-boot-failure`
**Status:** RUNTIME TEST CASE ONLY — this build intentionally crashes. It must never be released or merged into `master`.

## 1. Purpose

RHVoice for Android supports [Direct Boot](https://developer.android.com/privacy-and-security/direct-boot) (API 24+). On the first start after the feature is installed, the app migrates its storage (shared preferences, downloaded voice packages, voice data, `RHVoice.conf` and user dictionaries) from credential protected storage into device protected storage, so the TTS engine can speak on the lock/PIN screen after a reboot, before the user unlocks the device.

This build answers the question: **what does the app do, which exception is thrown, and what appears in the logs when that migration fails and never completes?** The migration code has been deliberately sabotaged so the failure is reproducible on any API 24+ device, immediately, every time.

## 2. Exactly what was modified

Only **one file** was changed to cause the failure:

`src/android/RHVoice-core/src/main/java/com/github/olga_yakovleva/rhvoice/android/DirectBoot.java`

`DirectBoot` is the class that owns the whole migration: it is invoked from `MyApplication.onCreate()` (every process start), `RHVoiceService.onCreate()` / `onUserUnlocked()`, `OnMyPackageReceiver` (after an app update), and from `DataManager`/`DataPack` sync scheduling. All of these funnel into `DirectBoot.migrate()`, which is where the failure is injected.

Three modifications, all guarded by a single new flag:

### 2.1 New flag (lines 39–46)

```java
static final boolean FORCE_MIGRATION_FAILURE = true;
```

Setting this to `false` restores completely normal behavior.

### 2.2 The synchronous migration steps are skipped (lines 124–128, inside `migrate(Context, Runnable)`)

```java
synchronized (DirectBoot.class) {
    if (!FORCE_MIGRATION_FAILURE) {
        migrateSharedPreferences(appContext, directContext, state);
        migratePrivateDir(appContext, directContext, state, PACKAGE_DIR);
    }
    ...
}
```

Normally, the shared preferences (`<package>_preferences`, `dir`) and the downloaded-packages directory (`app_packages`) are moved to device protected storage synchronously, before the background phase starts. With the flag on, **nothing is migrated and no `migrated.*` markers are ever written** to the `direct_boot` state preferences, so from the app's point of view the migration is permanently outstanding.

### 2.3 The background migration phase is replaced by a deliberate crash (lines 138–150, inside `migrate(Context, Runnable)`)

```java
if (FORCE_MIGRATION_FAILURE) {
    Log.e(TAG, "TEST BUILD: forcing Direct Boot migration failure; the migration will never complete and the process will now crash");
    migrationExecutor.execute(() -> {
        throw new IllegalStateException("RHVoice TEST: forced Direct Boot migration failure (simulated device protected storage error); this test build never completes the migration");
    });
    return;
}
```

Normally the background phase runs `Config.syncToDirectBootStorage()` (config file + user dictionaries) and migrates the voice-data directory (`app_data`), then calls `finishMigration()`, which clears the `migrationInProgress` flag and runs every completion callback queued by `MyApplication`, `RHVoiceService`, `DataManager` and `DataPack`.

With the flag on:

- `finishMigration()` is **never called** — `DirectBoot.isMigrationInProgress()` stays `true` for the life of the process and no completion callback ever runs. The migration literally never completes.
- The `IllegalStateException` is thrown on the migration executor thread and is **intentionally left uncaught**. Android's default uncaught-exception handler logs it as a `FATAL EXCEPTION` and kills the whole process.

No other file was modified. In particular, the exception handling that the production code uses for real failures (`catch (RuntimeException …)` blocks in `DirectBoot`, `Config.syncToDirectBootStorage`, etc.) is untouched — it is simply bypassed.

## 3. Exception that is thrown

| | |
|---|---|
| Type | `java.lang.IllegalStateException` |
| Message | `RHVoice TEST: forced Direct Boot migration failure (simulated device protected storage error); this test build never completes the migration` |
| Thread | the single-threaded migration executor (default executor thread name, e.g. `pool-2-thread-1`) — **not** the main thread |
| Handling | uncaught → `FATAL EXCEPTION` → process is killed by the runtime |

## 4. What the logs show

Capture with any of:

```
adb logcat -s RHVoice.DirectBoot:* AndroidRuntime:*
adb logcat -b crash
adb shell dumpsys dropbox --print data_app_crash
adb bugreport
```

Expected sequence (release and debug builds alike — the injected log line uses `Log.e` unconditionally, and the ProGuard config uses `-dontobfuscate`, so class and method names stay readable in release builds):

```
E RHVoice.DirectBoot: TEST BUILD: forcing Direct Boot migration failure; the migration will never complete and the process will now crash
E AndroidRuntime: FATAL EXCEPTION: pool-2-thread-1
E AndroidRuntime: Process: com.github.olga_yakovleva.rhvoice.android, PID: <pid>
E AndroidRuntime: java.lang.IllegalStateException: RHVoice TEST: forced Direct Boot migration failure (simulated device protected storage error); this test build never completes the migration
E AndroidRuntime: 	at com.github.olga_yakovleva.rhvoice.android.DirectBoot.lambda$migrate$0(DirectBoot.java:148)
E AndroidRuntime: 	at com.github.olga_yakovleva.rhvoice.android.DirectBoot$$ExternalSyntheticLambda0.run(...)
E AndroidRuntime: 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:...)
E AndroidRuntime: 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:...)
E AndroidRuntime: 	at java.lang.Thread.run(Thread.java:...)
```

Notes for testers:

- The `RHVoice.DirectBoot` line is logged on the thread that triggered the migration (usually the main thread, from `MyApplication.onCreate`) immediately before the crashing task is scheduled, so it always precedes the `FATAL EXCEPTION` block.
- The exact thread number (`pool-N-thread-1`), the synthetic lambda frame name, and the `DirectBoot.java` line number may vary slightly between builds/toolchains; the exception type and message string are the stable identifiers.
- The crash is also recorded in the system DropBox (`data_app_crash`) and, on most devices, in *Settings → Apps → RHVoice → App crash info* / manufacturer diagnostics.

## 5. Observable device behavior

On any device running **Android 7.0 (API 24) or newer**:

- **Normal (unlocked) operation:** every start of the RHVoice process triggers `DirectBoot.migrate()` from `MyApplication.onCreate()`, so the process crashes within milliseconds of starting — whether it was started by opening the RHVoice UI, by the system binding the TTS service, or by a WorkManager job. Opening the app shows the UI at most briefly, followed by the system "RHVoice keeps stopping" dialog. Speech requests from screen readers or other TTS clients fail; the system TTS framework will attempt to rebind the engine, causing repeated background crashes until Android's crash-loop backoff stops restarting it. Expect *multiple* identical `FATAL EXCEPTION` entries in the log.
- **During actual Direct Boot (after reboot, before the user unlocks):** `migrate()` returns early because the user is still locked, so **no crash happens on the lock screen itself**. However, because the migration never ran, device protected storage contains no voice data, so the engine reports "No voice data" (tag `RHVoice.Service`) and stays silent. The first crash then occurs immediately after the user unlocks the device (`ACTION_USER_UNLOCKED` → `MyApplication.onUserUnlocked()` → `migrate()`).
- **After an app update:** `OnMyPackageReceiver` (`MY_PACKAGE_REPLACED`) also calls `migrate()`, so the crash fires right after installing the update, without any user interaction.
- **While the process is (briefly) alive:** `DirectBoot.isMigrationInProgress()` remains `true`, so `DataWorker` and `PackageDirectoryWorker` return `Result.retry()` and voice-pack sync/download work is indefinitely deferred — this is the designed "migration pending" behavior, observable in `adb shell dumpsys jobscheduler` / WorkManager state as perpetually retrying jobs.

On devices **older than API 24**, Direct Boot is not supported, `migrate()` short-circuits before the injected code, and the app behaves completely normally. Test devices must run Android 7.0+.

## 6. Data safety and reverting

- The forced failure **does not read, move, or delete any user data**. The synchronous migration steps are skipped entirely; the crash happens before any file operation. Installed voices, settings and dictionaries remain intact in credential protected storage.
- To restore normal behavior, set `FORCE_MIGRATION_FAILURE = false` in `DirectBoot.java` (or install a build from `master`). On the next start the real migration runs from the beginning and completes normally, because no `migrated.*` markers were ever written by the test build.
