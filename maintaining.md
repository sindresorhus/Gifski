## Maintaining

### Testing system services

First, we need to install the app:
1. Archive the app.
2. Once you have your archive in the Organizer window, right-click it, and click **Show in Finder**.
3. Right-click again, now on the latest `Gifski_DATE_.xcarchive`, and click **Show Package Contents**.
4. Open `/Products/Applications` and move `Gifski.app` to your `Applications` directory.

Then, we need to check if our system has the latest service installed:
1. In your terminal, enter the command:
```bash
/System/Library/CoreServices/pbs -dump | grep Gifski.app
```
2. If you see `NSBundlePath = "/Applications/Gifski.app”` - you're good to go.
3. If you don't see the line above, try updating the cache:
```bash
/System/Library/CoreServices/pbs -update
```

### Troubleshooting system services

Sometimes the service doesn't work and it's really hard to understand why without any tools. You can use a debug flag on the instance of `Finder` app and see the logs it dumps:

```bash
/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder -NSDebugServices com.sindresorhus.Gifski
```
