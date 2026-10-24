# Installing Manager

**English** | [中文](INSTALL.zh-CN.md)

No programming knowledge needed. Follow the steps in order; it takes about 5 minutes.

**You need:** a Mac with macOS 13 (Ventura) or later, and Google Chrome.
Microsoft Edge, Brave, Arc and Vivaldi work too, with the same steps.

---

## Step 1: Download

1. Open the [latest release page](https://github.com/songxiaofeng1981/html-manager/releases/latest).
2. Under **Assets**, click **`html-manager-v1.5.0.zip`** (the version number may be higher).
   Don't click "Source code": that needs developer tools.
3. Open your Downloads folder and double-click the zip file. A folder named `html-manager-v1.5.0` appears.

## Step 2: Run the installer

1. Open Terminal: press `⌘ Space`, type `Terminal`, press Return.
2. In the Terminal window, type `bash` followed by **one space**. Don't press Return yet.
3. Drag **`install.sh`** from the `html-manager-v1.5.0` folder into the Terminal window.
   The line now looks like `bash /Users/yourname/Downloads/html-manager-v1.5.0/install.sh`.
4. Press Return.

After a few seconds you'll see **"Done!"** and Chrome's extensions page opens.

> **Why Terminal and not a double-click?** macOS blocks double-clicking scripts downloaded from the internet,
> and the setting to allow them is well hidden. Starting the script from Terminal avoids that.
> The installer only copies files into your own user folder and never asks for your password.

## Step 3: Add the extension to Chrome

The installer opened `chrome://extensions` for you. If not, type `chrome://extensions` in Chrome's address bar and press Return.

1. Turn on **Developer mode** (top right).
2. Click **Load unpacked** (top left).
3. A folder picker opens. Press `⌘ Shift G`, then `⌘ V` (the installer already copied the folder path), then Return.
4. Click **Select**.
5. On the Manager card, click **Details** and turn on **Allow access to file URLs**. This lets Manager open your HTML files in new tabs and show thumbnails.
6. Click the puzzle icon in Chrome's toolbar, then the pin next to **Manager**, to keep it in the toolbar.

> Developer mode is needed because the extension isn't in the Chrome Web Store yet.
> Chrome may sometimes remind you that a developer-mode extension is installed; that's expected.

## Step 4: Create your library

1. Click the **Manager** icon in the toolbar.
2. The first time, it shows **Start your library**. Click **Create Library**. Manager creates `Manager.html` and a `Manager_Files` folder in Downloads and changes nothing else.
   - Want the library somewhere else, such as an external disk? Click **Choose Folders…** first, enter the folder, then create it.
3. If macOS asks whether *"Manager Helper" may access files in your Downloads folder*, click **Allow**.

## Step 5: Import your first HTML files

1. Click **Import New HTML** in the sidebar. Manager lists the HTML files in Downloads that are not in the library yet.
2. Tick the files you want. For each, check the **category** and **2–4 tags** (click "+ Tag" to pick from the vocabulary).
3. Click **Archive and Import**. The files move into `Manager_Files` and get thumbnails.

Done. 🎉 You can now delete the downloaded `html-manager-v1.5.0` folder and the zip file.

---

## Keeping the library on an external disk

1. Connect the disk and, in Finder, drag the whole library (`Manager.html`, `Manager_Files`, `.thumbs`) onto it, for example into `/Volumes/MyDisk/`.
2. In Manager, click the folder button at the bottom of the sidebar (**Folders**).
3. Set **Library** to the folder on the disk, for example `/Volumes/MyDisk`. Leave **New files** empty (that means Downloads).
   Not sure of the path? Select the folder in Finder and press `⌥ ⌘ C` to copy it.
4. Click **Save**. If macOS asks about access to removable volumes, click **Allow**.

New downloads still arrive in Downloads; importing moves them to the library on the disk.
When the disk isn't connected, Manager shows "The library folder is not available"; connect it and click Retry.

## Updating to a new version

1. Download and unzip the new release (Step 1).
2. Run `bash install.sh` again (Step 2).
3. In `chrome://extensions`, click the reload icon (↻) on the Manager card.

Your library and folder settings are kept.

## Trouble?

| What you see | What to do |
|---|---|
| The page says **The Mac helper is not connected** | Do Step 2 again. Then check that the ID on the Manager card in `chrome://extensions` is `jpencbldoocakpdbgolffgemckpimnph`. |
| The page says **The Mac helper needs updating** | Do Step 2 again with the new version's folder, then click reload in `chrome://extensions`. |
| The page says **No access to the folders** | Open **System Settings → Privacy & Security → Files and Folders**, find **Manager Helper**, turn on **Downloads Folder** (and **Removable Volumes**), then click **Retry**. |
| The page says **The library folder is not available** | The disk holding the library isn't connected, or the folder was renamed. Connect it and click Retry, or fix the path in Folders. |
| Cards have no thumbnails, or files won't open | In `chrome://extensions`, open Manager's **Details** and turn on **Allow access to file URLs**. |
| Importing says **No thumbnail could be made** | Select that HTML file in Finder and press Space. If it previews, try again; if not, the file may be damaged. |
| Terminal says `No such file or directory` | Make sure there is a space after `bash`, and that you dragged the `install.sh` file, not the whole folder. |
| Terminal says "No ready-made helper in this folder" | You downloaded "Source code" instead of the release zip. Go back to Step 1. |
| Chrome says **Manifest file is missing or unreadable** | You picked the wrong folder in Step 3. Choose `~/Applications/Manager HTML/extension` (press `⌘ Shift G` and paste). |

To check the helper without Chrome, run this in Terminal:

```bash
bash "$HOME/Library/Application Support/Manager HTML/selftest.sh"
```

It shows where the library is, how many documents it finds and how many are waiting to be imported.

Still stuck? Please [open an issue](https://github.com/songxiaofeng1981/html-manager/issues/new/choose) with your macOS version and what you see. English or Chinese is fine.

## Uninstalling

1. Open Terminal, paste this line and press Return. It removes the helper, its settings and the extension files. **Your library and HTML files are not touched.**
   ```bash
   bash "$HOME/Library/Application Support/Manager HTML/uninstall.sh"
   ```
2. In `chrome://extensions`, click **Remove** on Manager.
