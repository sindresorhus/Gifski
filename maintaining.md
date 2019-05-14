## Maintaining Gifski

### Testing system services

First, we need to install the app:
1. Archive the app.
1. Once you have your archive in the Organizer window, right-click on it and click **Show in Finder**.
1. Right-click again, now on the latest `Gifski_DATE_.xcarchive` and click **Show package contents**.
1. Open `/Products/Applications` and move `Gifski.app` to your `Applications` folder.

Then, we need to check if our system has the latest service installed:
1. In your terminal, enter the command:
```bash
/System/Library/CoreServices/pbs -dump | grep Gifski.app
```
1. If you see `NSBundlePath = "/Applications/Gifski.app”` - you're good to go.
1. If you don't see the line above, try updating the cache using command:
```bash
/System/Library/CoreServices/pbs -update
```

Now make sure you have enabled the service in your settings:
1. Go to your **System Preferences** -> **Keyboard**.
1. Now click on the **Shortcuts** tab at the top.
1. On the left panel select `Services` and on the right panel search for `Convert to Gif with Gifski` service - enable it.